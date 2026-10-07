-- per-commit state, stored as a git TREE pinned by a local ref:
--  - `refs/local/<cid>` -> tree
--      meta.lua                 { now, open, tot, min0012, headless,
--                                 order_n }
--      members/<xx>/<enc(pub)>.lua  { reps, time, head?, dictator? }
--                               fanout by 2 hex chars of sha1(pub)
--      heads.txt                the due-heads index: "time member"
--                               per member with a waiting 12-24
--                               record, sorted by time
--      order/<nnnn>.txt         chunks of ORDER_K cids, one per line
--                               (lazy: the tail chunk is eager, the
--                               count lives in meta)
--      pending/<day>.txt        maturing entries of that day, one
--                               record per line: cid time maturity member
--      actions/<xx>/<cid>.lua   one entry, fanout by 2 hex chars
--  - `.lua` files are bare Lua table literals (no `return`); the
--    two bulk files are plain lines (gmatch beats the Lua parser)
--  - keyed by the derefed cid (callers resolve refs via GIT.deref)
-- Unchanged files share blobs across snapshots, so a snapshot costs
-- its touched blobs plus the trees on their paths, not the whole G.
-- `G.actions` and `G.members` are LAZY: an entry loads on first
-- access (one blob), `fetch`/`members`/`all`/`members_all` load
-- many in one batch. meta, heads, the pending window and the tail
-- order chunk are eager.
-- `refs/local/*` are LOCAL: sync never pushes or fetches them.

local M = {}

-- the window constants (tests load this module without the chain
-- globals)
local C = require "freechains.constants"

local ORDER_K = 200     -- cids per order chunk
M.ORDER_K = ORDER_K     -- (sync.lua: hardfork reads chunks)
local DAY     = 24*60*60

-- per-G cache, keyed by table identity (weak):
--  root        = the tree sha the G was read from (nil: fresh G),
--                then the one each write built (maybe not yet in git)
--  base        = the newest root git holds: listings and fetches by
--                path go through it, written paths by their blob sha
--  order_n/last = #G.order and its last cid as read/written: the
--                order is append-only, only the tail chunk changes
--  tree[path]  = blob sha        src[path] = content as written/read
--  dirs[dir]   = tree sha        kids[dir] = { name -> "blob"|"tree" }
--  shard[xx]   = true once `actions/xx` is listed into tree/kids
--  top         = true once the shard trees are listed
--  shards      = true once every shard's blobs are listed
local CACHE = setmetatable({}, { __mode = "k" })

-- known snapshots of the chain (REPO only): a write adds, `has_all`
-- fills many in one call, `has` answers from here when it can
local HAS = {}

--[[
-- The state ref name of `cid`.
-- Inputs:
--  - cid [string]: 40-hex commit hash
-- Outputs:
--  - [string]: "refs/local/<cid>"
-- Errors:
--  - none
-- Callers:
--  - write/has/read (state.lua): the one naming point
--  - discard (discard.lua): drops the refs of discarded commits
--]]
function M.ref (cid)
    return "refs/local/" .. cid
end

--[[
-- Member pubkey <-> file name: keys carry ' ' and '/', which base64
-- and key types never spell as '~' and '!'.
-- Inputs:
--  - s [string]: pubkey (enc) or file name without ".lua" (dec)
-- Outputs:
--  - [string]: the other form
-- Errors:
--  - none
-- Callers:
--  - write/read (state.lua): members/ paths
--]]
local function enc (s)
    return (s:gsub(" ", "~"):gsub("/", "!"))
end
local function dec (s)
    return (s:gsub("~", " "):gsub("!", "/"))
end

--[[
-- File paths of the entities.
-- Inputs:
--  - cid [string] | pub [string] | i [integer] | day [integer]
-- Outputs:
--  - [string]: path inside the tree
-- Errors:
--  - none
-- Callers:
--  - write/fetch (state.lua): entities to paths
--]]
local sha1     -- defined below (needed by mpath)
local function apath (cid)
    return "actions/" .. cid:sub(1, 2) .. "/" .. cid .. ".lua"
end
local function mpath (pub)
    return "members/" .. sha1(pub):sub(1, 2) .. "/" .. enc(pub) .. ".lua"
end
local function opath (i)
    return string.format("order/%04d.txt", i)
end
local function ppath (day)
    return string.format("pending/%08d.txt", day)
end

--[[
-- Pending records <-> lines: "cid time maturity member" (member
-- "-" when unsigned).
-- Inputs:
--  - rs [table]: records (encode) | s [string]: lines (decode)
-- Outputs:
--  - [string] | [table]: the other form
-- Errors:
--  - none
-- Callers:
--  - write/read (state.lua): pending buckets
--]]
local function rec_enc (rs)
    local ls = {}
    for i, r in ipairs(rs) do
        ls[i] = r.cid .. " " .. r.time .. " " .. r.maturity .. " " .. (r.member or "-")
    end
    return table.concat(ls, "\n") .. "\n"
end
local function rec_dec (s, into)
    for cid, time, mat, member in s:gmatch("(%x+) (%d+) (%S+) ([^\n]*)\n") do
        into[#into+1] = {
            cid      = cid,
            time     = tonumber(time),
            maturity = mat,
            member   = (member ~= "-") and member or nil,
        }
    end
end

--[[
-- Split a path into its dir and name ("" for the root).
-- Inputs:
--  - path [string]: "a/b/c.lua"
-- Outputs:
--  - [string, string]: dir, name
-- Errors:
--  - none
-- Callers:
--  - write/read (state.lua): tree bookkeeping
--]]
local function split (path)
    local d, name = path:match("^(.*)/([^/]+)$")
    if not d then
        return "", path
    end
    return d, name
end

--[[
-- Register `path` (blob) and its dirs into the kids map.
-- Inputs:
--  - C    [table]: the G cache
--  - path [string]: a blob path
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - write (state.lua): new blobs
--]]
local function register (C, path)
    local d, name = split(path)
    C.kids[d] = C.kids[d] or {}
    C.kids[d][name] = "blob"
    while d ~= "" do
        local up, sub = split(d)
        C.kids[up] = C.kids[up] or {}
        C.kids[up][sub] = "tree"
        d = up
    end
end

--[[
-- Run a git command with stdin from a temp file holding `input`.
-- Inputs:
--  - dir   [string]: the bare repo dir
--  - args  [string]: git arguments
--  - input [string]: stdin bytes
-- Outputs:
--  - [string]: stdout, untrimmed
-- Errors:
--  - via exec: "bug found" on failure
-- Callers:
--  - write/read/fetch (state.lua): hash-object, mktree, cat-file
--]]
local function git_in (dir, args, input)
    local path = dir .. "state-stdin"
    local f = assert(io.open(path, "w"))
    f:write(input)
    f:close()
    local out = exec { trim=false,
        cmd = "git -C " .. dir .. " " .. args .. " < " .. path,
    }
    os.remove(path)
    return out
end

--[[
-- SHA-1 (pure Lua): git object ids computed locally, so every tree
-- of a snapshot goes to ONE `mktree --batch` (a parent needs its
-- children's ids). mktree's own output is checked against them.
-- Inputs:
--  - msg [string]: the bytes
-- Outputs:
--  - [string]: 40-hex digest
-- Errors:
--  - none
-- Callers:
--  - tree_id (state.lua)
--]]
function sha1 (msg)
    local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
    local ml = #msg
    msg = msg .. "\128" .. string.rep("\0", (55 - ml) % 64) .. string.pack(">I8", ml * 8)
    local w = {}
    for chunk = 1, #msg, 64 do
        for i = 0, 15 do
            w[i] = string.unpack(">I4", msg, chunk + i*4)
        end
        for i = 16, 79 do
            local x = w[i-3] ~ w[i-8] ~ w[i-14] ~ w[i-16]
            w[i] = ((x << 1) | (x >> 31)) & 0xFFFFFFFF
        end
        local a, b, c, d, e = h0, h1, h2, h3, h4
        for i = 0, 79 do
            local f, k
            if i < 20 then
                f = (b & c) | ((~b) & d)
                k = 0x5A827999
            elseif i < 40 then
                f = b ~ c ~ d
                k = 0x6ED9EBA1
            elseif i < 60 then
                f = (b & c) | (b & d) | (c & d)
                k = 0x8F1BBCDC
            else
                f = b ~ c ~ d
                k = 0xCA62C1D6
            end
            local t = ((((a << 5) | (a >> 27)) & 0xFFFFFFFF) + (f & 0xFFFFFFFF) + e + k + w[i]) & 0xFFFFFFFF
            e = d
            d = c
            c = ((b << 30) | (b >> 2)) & 0xFFFFFFFF
            b = a
            a = t
        end
        h0 = (h0 + a) & 0xFFFFFFFF
        h1 = (h1 + b) & 0xFFFFFFFF
        h2 = (h2 + c) & 0xFFFFFFFF
        h3 = (h3 + d) & 0xFFFFFFFF
        h4 = (h4 + e) & 0xFFFFFFFF
    end
    return string.format("%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
end

--[[
-- A git tree object id from its entries, in git's order (a tree
-- name sorts as "name/").
-- Inputs:
--  - ents [table]: array of { mode, name, sha }, mode "100644"|"040000"
-- Outputs:
--  - [string]: the tree id
--  - [string]: the `mktree` input lines for the same tree
-- Errors:
--  - none
-- Callers:
--  - write (state.lua)
--]]
local function tree_id (ents)
    table.sort(ents, function (a, b)
        local ka = a.name .. ((a.mode == "040000") and "/" or "")
        local kb = b.name .. ((b.mode == "040000") and "/" or "")
        return ka < kb
    end)
    local raw, ls = {}, {}
    for i, e in ipairs(ents) do
        local mode = (e.mode == "040000") and "40000" or e.mode
        raw[i] = mode .. " " .. e.name .. "\0" .. (e.sha:gsub("%x%x", function (h)
            return string.char(tonumber(h, 16))
        end))
        ls[i] = e.mode .. " " .. ((e.mode == "040000") and "tree" or "blob") .. " " .. e.sha .. "\t" .. e.name
    end
    local body = table.concat(raw)
    return sha1("tree " .. #body .. "\0" .. body), table.concat(ls, "\n")
end

--[[
-- Parse a `cat-file --batch='%(objectname) %(objectsize) %(rest)'`
-- output into path -> content.
-- Inputs:
--  - out [string]: the batch output
--  - f   [function]: called per (path, content)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - read/fetch (state.lua)
--]]
local function batch (out, f)
    local pos = 1
    while pos <= #out do
        local nl = out:find("\n", pos, true)
        local sha, size, path = out:sub(pos, nl-1):match("^(%x+) (%d+) (.+)$")
        if sha then
            size = tonumber(size)
            f(path, out:sub(nl+1, nl+size), sha)
            pos = nl + size + 2
        else
            pos = nl + 1    -- "<rev> missing"
        end
    end
end

--[[
-- Listings of the lazy trees into the cache, on demand.
-- Never overwrite: a blob or tree already cached is the NEWER one
-- (hashed or built by this write), the listing is the older.
-- Inputs:
--  - G   [table]: chain state
--  - top [string]: "actions" | "members"
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - fetch/all/write (state.lua)
--]]
local function keep_blob (C, path, sha)
    if not C.tree[path] then
        C.tree[path] = sha
    end
    local d, name = split(path)
    C.kids[d] = C.kids[d] or {}
    C.kids[d][name] = "blob"
end
local function keep_tree (C, path, sha)
    if not C.dirs[path] then
        C.dirs[path] = sha
    end
    local d, name = split(path)
    C.kids[path] = C.kids[path] or {}
    C.kids[d] = C.kids[d] or {}
    C.kids[d][name] = "tree"
end
-- some shards of `top` (actions|members): their blobs, one process
local function shards_top (G, top)
    local C = CACHE[G]
    if (not C) or (not C.root) or C.top[top] then
        return
    end
    C.top[top] = true
    local out = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. C.dir .. " ls-tree --format='%(objectname) %(path)' " .. C.base .. ":" .. top,
    }
    if not out then
        return
    end
    for sha, name in out:gmatch("(%x+) ([^\n]+)\n") do
        keep_tree(C, top .. "/" .. name, sha)
    end
end
-- every shard of `top`: all blobs (listings, reconciles)
local function shards_all (G, top)
    local C = CACHE[G]
    if (not C) or (not C.root) or C.shards[top] then
        return
    end
    C.shards[top] = true
    shards_top(G, top)
    local out = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. C.dir .. " ls-tree -r --format='%(objectname) %(path)' " .. C.base .. ":" .. top,
    }
    if not out then
        return
    end
    for sha, path in out:gmatch("(%x+) ([^\n]+)\n") do
        keep_blob(C, top .. "/" .. path, sha)
    end
end

--[[
-- Load entries into `G.actions` in one batch, by PATH (no listing):
-- already loaded and known-missing cids are skipped, unknown ones
-- are remembered as missing.
-- Inputs:
--  - G    [table]: chain state; MUTATED (G.actions)
--  - cids [table]: array of cids
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - lazy (state.lua): one miss
--  - apply/advance (rules.lua): backs, target, maturing entries
--  - hardfork (sync.lua): order tail
--  - list (list.lua): revoked marks over the order
--  - all (state.lua): every entry
--]]
--[[
-- Load actions and members into `G` in ONE batch, by PATH (no
-- listing): already loaded and known-missing keys are skipped.
-- Inputs:
--  - G    [table]: chain state; MUTATED (G.actions, G.members)
--  - cids [table?]: array of cids
--  - pubs [table?]: array of pubkeys (nil entries allowed)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - fetch/members (state.lua): one kind each
--  - apply (action.lua): the action's backs, target, members and the
--    window advance will scan, together
--]]
function M.load (G, cids, pubs)
    local C = CACHE[G]
    if (not C) or (not C.root) then
        return
    end
    -- a path's blob sha when cached (listed, or written by this G:
    -- its tree may not be in git yet), else by path in `base`
    local function spec (path)
        return (C.tree[path] or (C.base .. ":" .. path)) .. " " .. path
    end
    local ls = {}
    for _, cid in ipairs(cids or {}) do
        if not (rawget(G.actions, cid) or C.missing[cid]) then
            C.missing[cid] = true   -- until proven present
            ls[#ls+1] = spec(apath(cid))
        end
    end
    for _, pub in pairs(pubs or {}) do
        if not (rawget(G.members, pub) or C.missing_m[pub]) then
            C.missing_m[pub] = true
            ls[#ls+1] = spec(mpath(pub))
        end
    end
    if #ls == 0 then
        return
    end
    local out = git_in(C.dir, "cat-file --batch='%(objectname) %(objectsize) %(rest)'",
        table.concat(ls, "\n") .. "\n")
    batch(out, function (path, s, sha)
        C.src[path] = s
        keep_blob(C, path, sha)
        if path:match("^actions/") then
            local cid = path:match("(%x+)%.lua$")
            C.missing[cid] = nil
            rawset(G.actions, cid, load("return " .. s)())
        else
            local pub = dec(path:match("([^/]+)%.lua$"))
            C.missing_m[pub] = nil
            rawset(G.members, pub, load("return " .. s)())
        end
    end)
end

function M.fetch (G, cids)
    M.load(G, cids, nil)
end

--[[
-- Load EVERY entry into `G.actions` (listings, reconciles).
-- Inputs:
--  - G [table]: chain state; MUTATED (G.actions)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - reps (reps.lua): actions/revokes listings
--  - recv (sync.lua): payload anchor reconcile
--]]
function M.all (G)
    local C = CACHE[G]
    if (not C) or (not C.root) then
        return
    end
    shards_all(G, "actions")
    local cids = {}
    for path in pairs(C.tree) do
        local cid = path:match("^actions/%x%x/(%x+)%.lua$")
        if cid then
            cids[#cids+1] = cid
        end
    end
    M.fetch(G, cids)
end

--[[
-- Load members into `G.members` in one batch, by PATH (no listing):
-- already loaded and known-missing keys are skipped.
-- Inputs:
--  - G    [table]: chain state; MUTATED (G.members)
--  - pubs [table]: array of pubkeys (nil entries allowed)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - lazy_members (state.lua): one miss
--  - apply/advance (rules.lua): signer, targets, window, due heads
--  - winner (consensus.lua): the two sides' keys
--  - members_all (state.lua): every member
--]]
function M.members (G, pubs)
    M.load(G, nil, pubs)
end

--[[
-- Load EVERY member into `G.members` (listings).
-- Inputs:
--  - G [table]: chain state; MUTATED (G.members)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - reps (reps.lua): members listing
--]]
function M.members_all (G)
    local C = CACHE[G]
    if (not C) or (not C.root) then
        return
    end
    shards_all(G, "members")
    local pubs = {}
    for path in pairs(C.tree) do
        local name = path:match("^members/%x%x/([^/]+)%.lua$")
        if name then
            pubs[#pubs+1] = dec(name)
        end
    end
    M.members(G, pubs)
end

--[[
-- The lazy `G.members` table: a miss loads the member's blob.
-- Inputs:
--  - G [table]: chain state; MUTATED (G.members gets a metatable)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - read (state.lua)
--]]
local function lazy_members (G)
    setmetatable(G.members, {
        __index = function (t, pub)
            if type(pub) ~= "string" then
                return nil
            end
            local C = CACHE[G]
            if C and C.missing_m[pub] then
                return nil
            end
            M.members(G, { pub })
            return rawget(t, pub)
        end,
    })
end

--[[
-- The lazy `G.actions` table: a miss loads the entry's blob.
-- Inputs:
--  - G [table]: chain state; MUTATED (G.actions gets a metatable)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - read/new (state.lua)
--]]
local function lazy (G)
    setmetatable(G.actions, {
        __index = function (t, cid)
            if type(cid) ~= "string" then
                return nil
            end
            local C = CACHE[G]
            if C and C.missing[cid] then
                return nil
            end
            M.fetch(G, { cid })
            return rawget(t, cid)
        end,
    })
end

--[[
-- The lazy `G.order` proxy: `#` is the count from meta, a read
-- loads its chunk, an append (index n+1) is raw.
-- Inputs:
--  - G [table]: chain state; MUTATED (G.order gets a metatable)
-- Outputs:
--  - none
-- Errors:
--  - assert: a write other than an append
-- Callers:
--  - read (state.lua)
--]]
local function lazy_order (G)
    setmetatable(G.order, {
        __len = function ()
            return G.order_n
        end,
        __index = function (t, i)
            if math.type(i) ~= "integer" or i < 1 or i > G.order_n then
                return nil
            end
            M.order(G, (i-1) // ORDER_K)
            return rawget(t, i)
        end,
        __newindex = function (t, i, v)
            assert(i == G.order_n+1, "bug found : order is append-only")
            G.order_n = i
            rawset(t, i, v)
        end,
    })
end

--[[
-- Load order chunk `i` (0-based), or every chunk (i == nil), in one
-- batch by path.
-- Inputs:
--  - G [table]: chain state; MUTATED (G.order)
--  - i [integer?]: the chunk, nil for all
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - lazy_order/read (state.lua)
--  - hardfork (sync.lua), list (list.lua): the whole order
--]]
function M.order (G, i)
    local C = CACHE[G]
    if (not C) or (not C.root) or (not G.order_n) then
        return
    end
    C.ochunks = C.ochunks or {}
    local want = {}
    local lo, hi = i or 0, i or ((G.order_n-1) // ORDER_K)
    for k = lo, hi do
        if not C.ochunks[k] then
            C.ochunks[k] = true
            want[#want+1] = (C.tree[opath(k)] or (C.base .. ":" .. opath(k))) .. " " .. opath(k)
        end
    end
    if #want == 0 then
        return
    end
    local out = git_in(C.dir, "cat-file --batch='%(objectname) %(objectsize) %(rest)'",
        table.concat(want, "\n") .. "\n")
    batch(out, function (path, s, sha)
        C.src[path] = s
        keep_blob(C, path, sha)
        local k = tonumber(path:match("(%d+)%.txt$"))
        local j = k*ORDER_K
        for cid in s:gmatch("%x+") do
            j = j + 1
            if not rawget(G.order, j) then
                rawset(G.order, j, cid)
            end
        end
    end)
end

--[[
-- A fresh dirty set: every entity of G, or none.
-- Inputs:
--  - G   [table]: chain state; MUTATED (G.dirty)
--  - all [boolean?]: mark every member and action (new G)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - read/write (state.lua): reset after a load or a snapshot
--  - genesis (chains.lua): a G built from scratch
--]]
function M.dirty (G, all)
    local D = { actions={}, members={}, pending={}, heads=all or false }
    if all then
        for k in pairs(G.actions) do
            D.actions[k] = true
        end
        for k in pairs(G.members) do
            D.members[k] = true
        end
        for _, r in ipairs(G.pending or {}) do
            D.pending[r.time] = true
        end
    end
    G.dirty = D
end

--[[
-- One `ls-tree` of many dirs into the cache: "top/" lists a top's
-- shard entries, "top/xx/" a shard's blobs, "top" the top's own
-- entry. Never overwrites a cached (newer) entry.
-- Inputs:
--  - C    [table]: the G's cache
--  - want [table]: array of paths as above
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - write/prelist (state.lua)
--]]
local function listing (C, want)
    if #want == 0 then
        return
    end
    local out = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. C.dir .. " ls-tree --format='%(objecttype) %(objectname) %(path)' " .. C.base .. " " .. table.concat(want, " "),
    }
    for ty, sha, path in (out or ""):gmatch("(%a+) (%x+) ([^\n]+)\n") do
        if ty == "tree" then
            keep_tree(C, path, sha)
        else
            keep_blob(C, path, sha)
        end
    end
    -- a shard listed by content ("top/xx/") hides its own entry when
    -- its top is listed too (git descends instead): its tree id is
    -- the one of its listed blobs, computed here, so a later rebuild
    -- of the top keeps the shard
    for _, w in ipairs(want) do
        local d = w:match("^(%a+/%x%x)/$")
        if d and (not C.dirs[d]) and C.kids[d] and next(C.kids[d]) then
            local ents = {}
            for name in pairs(C.kids[d]) do
                ents[#ents+1] = { mode="100644", name=name, sha=assert(C.tree[d .. "/" .. name]) }
            end
            keep_tree(C, d, (tree_id(ents)))
        end
    end
    -- likewise a top listed by content ("top/"): its id is the one of
    -- its shard entries, so an untouched top needs no listing later
    for _, w in ipairs(want) do
        local d = w:match("^(%a+)/$")
        if d and (not C.dirs[d]) and C.kids[d] and next(C.kids[d]) then
            local ents = {}
            for name in pairs(C.kids[d]) do
                ents[#ents+1] = { mode="040000", name=name, sha=assert(C.dirs[d .. "/" .. name]) }
            end
            keep_tree(C, d, (tree_id(ents)))
        end
    end
end

--[[
-- Mark cids known to be absent from the snapshot (a run's new
-- commits: descendants of the floor, so never in its state), so the
-- apply batch does not fetch each one to learn it is missing.
-- Inputs:
--  - G    [table]: chain state
--  - cids [table]: array of cids
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - state (consensus.lua): the run, before applying it
--]]
function M.absent (G, cids)
    local C = CACHE[G]
    if not C then
        return
    end
    for _, cid in ipairs(cids) do
        if not rawget(G.actions, cid) then
            C.missing[cid] = true
        end
    end
end

--[[
-- Pre-list, in ONE call, the dirs a run of writes will rebuild: both
-- tops and the shards of the given actions and members. Each write
-- then finds its listing cached (a run of N commits listed N times).
-- Inputs:
--  - G    [table]: chain state (read from a snapshot)
--  - cids [table]: the actions about to be written
--  - pubs [table]: the members about to be written (nil entries ok)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - state (consensus.lua): before applying a run
--]]
function M.prelist (G, cids, pubs)
    local C = CACHE[G]
    if (not C) or (not C.root) then
        return
    end
    local want = {}
    for _, top in ipairs { "actions", "members" } do
        if not C.top[top] then
            C.top[top] = true
            want[#want+1] = top .. "/"
        end
    end
    local function shard (top, d)
        if (not C.shards[top]) and (not C.shard[d]) then
            C.shard[d] = true
            C.kids[d] = C.kids[d] or {}
            want[#want+1] = d .. "/"
        end
    end
    for _, cid in ipairs(cids) do
        shard("actions", "actions/" .. cid:sub(1, 2))
    end
    for _, pub in pairs(pubs) do
        shard("members", "members/" .. sha1(pub):sub(1, 2))
    end
    listing(C, want)
end

--[[
-- Snapshot `G` at `cid`: the dirty entities become blobs, the trees
-- on their paths are rebuilt (mktree, bottom-up), the root is
-- pinned by the ref. Nothing else is rewritten.
-- Inputs:
--  - G   [table]: chain state (members/actions/order/pending/now)
--  - cid [string]: 40-hex commit hash, derefed
--  - dir [string?]: the bare repo dir (default REPO)
--  - refs [table?]: collects the ref's create line instead of running
--    it (the caller flushes many in one `GIT.refs`); `has` answers
--    true from here on either way
-- Outputs:
--  - none (G.dirty reset)
-- Errors:
--  - via exec: "bug found" if hash-object/mktree/update-ref fail
-- Callers:
--  - apply (action.lua): snapshot at every accepted commit
--  - recv (sync.lua): snapshot at the loser sync merge
--  - genesis (chains.lua): the empty state at the genesis
--]]
function M.write (G, cid, dir, refs)
    dir = dir or REPO
    local C = CACHE[G]
    if not C then
        C = { dir=dir, tree={}, src={}, dirs={}, kids={ [""]={} }, shard={}, shards={}, top={}, missing={}, missing_m={} }
        CACHE[G] = C
    end
    if refs then
        refs.blobs  = refs.blobs or {}
        refs.trees  = refs.trees or {}
        refs.caches = refs.caches or {}
        refs.caches[C] = true
    end

    -- 1. the changed files
    local changed = {}      -- path -> content
    local paths   = {}      -- stable order for the hash batch
    local function put (path, s)
        if C.src[path] ~= s then
            changed[path] = s
            paths[#paths+1] = path
        end
    end
    put("meta.lua", table_to_string {
        now=G.now, open=G.open, tot=G.tot, min0012=G.min0012,
        headless=G.headless, order_n=#G.order,
    } .. "\n")
    for pub in pairs(G.dirty.members) do
        put(mpath(pub), table_to_string(rawget(G.members, pub)) .. "\n")
    end
    if G.dirty.heads then
        local ls = {}
        for i, h in ipairs(G.heads) do
            ls[i] = h.time .. " " .. h.member
        end
        put("heads.txt", table.concat(ls, "\n") .. "\n")
    end
    for k in pairs(G.dirty.actions) do
        put(apath(k), table_to_string(rawget(G.actions, k)) .. "\n")
    end
    do
        -- order: append-only since the read, so only the chunks
        -- from the old tail on; a shorter or rewritten prefix
        -- (never expected) falls back to every chunk
        local n = #G.order
        local from = 0
        local on = C.order_n or 0
        if on > 0 and n >= on and G.order[on] == C.order_last then
            from = (on-1) // ORDER_K
        end
        for i = from, math.ceil(n/ORDER_K)-1 do
            local chunk = table.move(G.order, i*ORDER_K+1, math.min(n, (i+1)*ORDER_K), 1, {})
            put(opath(i), table.concat(chunk, "\n") .. "\n")
        end
        C.order_n    = n
        C.order_last = G.order[n]
    end
    do
        -- pending buckets by day of the member time: only the days
        -- marked dirty are rebuilt (sorted input); an emptied
        -- bucket loses its file
        local days = {}
        for t in pairs(G.dirty.pending) do
            days[t // DAY] = true
        end
        local buckets = {}
        for _, r in ipairs(G.pending) do
            local d = r.time // DAY
            if days[d] then
                buckets[d] = buckets[d] or {}
                table.insert(buckets[d], r)
            end
        end
        for d in pairs(days) do
            local path = ppath(d)
            if buckets[d] then
                put(path, rec_enc(buckets[d]))
                if not G.loaded[d] then
                    G.loaded[d] = true
                end
                local known = false
                for _, x in ipairs(G.pdays) do
                    if x == d then
                        known = true
                        break
                    end
                end
                if not known then
                    G.pdays[#G.pdays+1] = d
                    table.sort(G.pdays)
                end
            elseif C.tree[path] then
                C.tree[path] = nil
                C.src[path] = nil
                C.kids["pending"][path:match("([^/]+)$")] = nil
                paths[#paths+1] = path   -- rebuilds its dir
                for i, x in ipairs(G.pdays) do
                    if x == d then
                        table.remove(G.pdays, i)
                        break
                    end
                end
            end
        end
    end

    -- 2. blobs: one hash-object over temp files
    local hs = {}   -- paths that need a blob
    for _, path in ipairs(paths) do
        if changed[path] then
            hs[#hs+1] = path
        end
    end
    if refs then
        -- deferred: the ids now (git's blob hash, in Lua: 9 MB/s, a
        -- few ms per write), the objects at the flush, all in one call
        for _, path in ipairs(hs) do
            local s = changed[path]
            local sha = sha1("blob " .. #s .. "\0" .. s)
            C.tree[path] = sha
            C.src[path]  = s
            register(C, path)
            refs.blobs[#refs.blobs+1] = { dir=dir, sha=sha, src=s }
        end
    elseif #hs > 0 then
        local tmps = {}
        for i, path in ipairs(hs) do
            local tmp = dir .. "state-tmp-" .. i
            local f = assert(io.open(tmp, "w"))
            f:write(changed[path])
            f:close()
            tmps[i] = tmp
        end
        local out = git_in(dir, "hash-object -w --stdin-paths", table.concat(tmps, "\n") .. "\n")
        local i = 0
        for sha in out:gmatch("%x+") do
            i = i + 1
            local path = hs[i]
            C.tree[path] = sha
            C.src[path]  = changed[path]
            register(C, path)
            os.remove(tmps[i])
        end
        assert(i == #hs, "bug found : hash-object count")
    end

    -- 3. trees: every dir on a changed path, one `mktree --batch`
    -- per depth, deepest first (a parent needs its children's shas)
    local levels = {}
    for _, path in ipairs(paths) do
        local d = path
        repeat
            d = split(d)
            local depth = select(2, d:gsub("/", "")) + ((d == "") and 0 or 1)
            levels[depth] = levels[depth] or {}
            levels[depth][d] = true
        until d == ""
    end
    -- one listing serves every dir the write rebuilds from git: an
    -- untouched lazy top (its entry, for the root: the read lists
    -- neither `actions` nor `members`), a touched top (its shard
    -- entries, "top/"), a touched shard (its blobs, "top/xx/")
    if C.root then
        local want = {}
        local touched = {}
        for depth = #levels, 0, -1 do
            for d in pairs(levels[depth] or {}) do
                local top = d:match("^(%a+)/%x%x$")
                if (d == "actions") or (d == "members") then
                    touched[d] = true
                    if not C.top[d] then
                        C.top[d] = true
                        want[#want+1] = d .. "/"
                    end
                elseif top and (not C.shards[top]) and (not C.shard[d]) then
                    C.shard[d] = true
                    C.kids[d] = C.kids[d] or {}
                    want[#want+1] = d .. "/"
                end
            end
        end
        for _, top in ipairs { "actions", "members" } do
            if (not touched[top]) and (not C.dirs[top]) and (not (C.kids[""] or {})[top]) then
                want[#want+1] = top
            end
        end
        listing(C, want)
    end
    -- tree ids are computed here, deepest first, so the whole
    -- snapshot is ONE `mktree --batch`; its ids must agree
    local input = {}
    local built = {}
    for depth = #levels, 0, -1 do
        local ds = {}
        for d in pairs(levels[depth] or {}) do
            ds[#ds+1] = d
        end
        table.sort(ds)
        for _, d in ipairs(ds) do
            local ents = {}
            local pfx = (d == "") and "" or (d .. "/")
            for name, ty in pairs(C.kids[d] or {}) do
                if ty == "blob" then
                    ents[#ents+1] = { mode="100644", name=name, sha=assert(C.tree[pfx .. name]) }
                else
                    ents[#ents+1] = { mode="040000", name=name, sha=assert(C.dirs[pfx .. name]) }
                end
            end
            if #ents == 0 then
                -- git has no empty trees in listings: the dir goes
                local up, sub = split(d)
                C.kids[up][sub] = nil
                C.dirs[d] = nil
                C.kids[d] = nil
            else
                local id, ls = tree_id(ents)
                C.dirs[d] = id
                input[#input+1] = ls
                built[#built+1] = id
            end
        end
    end
    if refs then
        for i, ls in ipairs(input) do
            refs.trees[#refs.trees+1] = { dir=dir, id=built[i], ls=ls }
        end
        -- a long run (a clone) keeps memory bounded: objects out early
        if #refs.blobs > 512 then
            M.flush(refs, true)
        end
    elseif #built > 0 then
        local out = git_in(dir, "mktree --batch", table.concat(input, "\n\n") .. "\n")
        local i = 0
        for sha in out:gmatch("%x+") do
            i = i + 1
            assert(sha == built[i], "bug found : tree id : " .. sha .. " ~= " .. built[i])
        end
        assert(i == #built, "bug found : mktree count")
    end

    -- 4. the ref: create-only. NEVER overwrite: the first write is
    -- the commit's own-lineage state, and a refused sync must not
    -- corrupt local snapshots (a replay of a snapshotted commit
    -- lands here again and is refused)
    C.root = C.dirs[""] or assert(C.root)
    if refs then
        refs[#refs+1] = "create " .. M.ref(cid) .. " " .. C.root
    else
        exec { err=false, stderr=false,
            cmd = "git -C " .. dir .. " update-ref " .. M.ref(cid) .. " " .. C.root .. " ''",
        }
    end
    if dir == REPO then
        HAS[cid] = true
    end
    if not refs then
        C.base = C.root     -- in git now
    end
    M.dirty(G)
end

--[[
-- Materialize the deferred writes of a run, then its ref updates:
-- one `hash-object` for every blob, one `mktree` for every tree,
-- one `update-ref` (`GIT.refs`). The ids were computed at write
-- time and are checked against git's.
-- Inputs:
--  - ops  [table]: the refs list the writes filled (blobs, trees,
--    caches, and the ref lines)
--  - only [boolean?]: objects only, keep the ref lines (a long run
--    flushing early)
-- Outputs:
--  - none (ops emptied)
-- Errors:
--  - assert "bug found : blob/tree id" : an id git disagrees with
-- Callers:
--  - post/like: the accepted action
--  - state (consensus.lua), recv (sync.lua): a run
--]]
function M.flush (ops, only)
    local blobs, trees = ops.blobs or {}, ops.trees or {}
    if #blobs > 0 then
        local dir = blobs[1].dir
        local tmps = {}
        for i, b in ipairs(blobs) do
            local tmp = dir .. "state-tmp-" .. i
            local f = assert(io.open(tmp, "w"))
            f:write(b.src)
            f:close()
            tmps[i] = tmp
        end
        local out = git_in(dir, "hash-object -w --stdin-paths", table.concat(tmps, "\n") .. "\n")
        local i = 0
        for sha in out:gmatch("%x+") do
            i = i + 1
            assert(sha == blobs[i].sha, "bug found : blob id : " .. sha .. " ~= " .. blobs[i].sha)
            os.remove(tmps[i])
        end
        assert(i == #blobs, "bug found : hash-object count")
        ops.blobs = {}
    end
    if #trees > 0 then
        local dir = trees[1].dir
        local input = {}
        for i, t in ipairs(trees) do
            input[i] = t.ls
        end
        local out = git_in(dir, "mktree --batch", table.concat(input, "\n\n") .. "\n")
        local i = 0
        for sha in out:gmatch("%x+") do
            i = i + 1
            assert(sha == trees[i].id, "bug found : tree id : " .. sha .. " ~= " .. trees[i].id)
        end
        assert(i == #trees, "bug found : mktree count")
        ops.trees = {}
    end
    for C in pairs(ops.caches or {}) do
        C.base = C.root     -- in git now
    end
    if not only then
        GIT.refs(ops)
        for i = #ops, 1, -1 do
            ops[i] = nil
        end
    end
end

--[[
-- Whether `cid` has a snapshot.
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed
--  - dir [string?]: the bare repo dir (default REPO)
-- Outputs:
--  - [boolean]: refs/local/<cid> exists
-- Errors:
--  - none
-- Callers:
--  - apply (action.lua): NEVER overwrite the first snapshot
--  - recv (sync.lua): unsnapshotted incoming begs
--]]
function M.has (cid, dir)
    dir = dir or REPO
    if (dir == REPO) and (HAS[cid] ~= nil) then
        return HAS[cid]
    end
    local _, code = exec { stderr=false, err=false,
        cmd = "git -C " .. dir .. " show-ref --verify --quiet " .. M.ref(cid),
    }
    if dir == REPO then
        HAS[cid] = (code == 0)
    end
    return code == 0
end

--[[
-- Whether each of many cids has a snapshot, in ONE call (a pull
-- walks every new commit through `has`).
-- Inputs:
--  - cids [table]: array of 40-hex commit hashes
-- Outputs:
--  - none: `has` answers from memory
-- Errors:
--  - via exec: "bug found" if cat-file fails
-- Callers:
--  - recv (sync.lua): the remote's new commits
--]]
function M.has_all (cids)
    local ls = {}
    for _, cid in ipairs(cids) do
        if HAS[cid] == nil then
            HAS[cid] = false
            ls[#ls+1] = M.ref(cid) .. " " .. cid
        end
    end
    if #ls == 0 then
        return
    end
    local out = git_in(REPO, "cat-file --batch-check='%(objectname) %(rest)'",
        table.concat(ls, "\n") .. "\n")
    for _, cid in out:gmatch("(%x+) (%x+)\n") do
        HAS[cid] = true
    end
end

--[[
-- The state RECORDED at `cid` (trusted local bytes: load()-ed).
-- Eager: meta, members, order, pending. Lazy: actions.
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed and snapshotted
--  - dir [string?]: the bare repo dir (default REPO)
-- Outputs:
--  - [table]: the G written at `cid`
-- Errors:
--  - assert "bug found : no snapshot : <cid>" : missing ref
-- Callers:
--  - init (chain/init.lua): G = state at HEAD
--  - like (like.lua): beg-branch state preload
--  - recv (sync.lua): HEAD/beg-parent states
--  - state (consensus.lua): the nearest snapshot below a commit
--]]
function M.read (cid, dir)
    dir = dir or REPO
    -- the ref itself is the tree-ish everywhere below
    local root = M.ref(cid)
    local CC = { dir=dir, root=root, base=root, tree={}, src={}, dirs={}, kids={ [""]={} }, shard={}, shards={}, top={}, missing={}, missing_m={} }

    -- the eager dirs and meta, with their tree shas (`actions` is
    -- listed on demand)
    local ls = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. dir .. " ls-tree -r -t --format='%(objecttype) %(objectname) %(path)' " .. root .. " meta.lua heads.txt order pending",
    }
    assert(ls, "bug found : no snapshot : " .. cid)
    -- meta first: the pending window depends on it
    local blobs = {}
    local pend  = {}
    local ords  = {}
    for ty, sha, path in ls:gmatch("(%a+) (%x+) ([^\n]+)\n") do
        if ty == "tree" then
            keep_tree(CC, path, sha)
        else
            keep_blob(CC, path, sha)
            if path:match("^pending/") then
                pend[#pend+1] = path
            elseif path:match("^order/") then
                ords[#ords+1] = path
            else
                blobs[#blobs+1] = sha .. " " .. path
            end
        end
    end

    -- the tail order chunk rides the eager batch (every post
    -- appends to it)
    table.sort(ords)
    local tail = ords[#ords]
    if tail then
        blobs[#blobs+1] = CC.tree[tail] .. " " .. tail
    end
    -- so do the newest two pending days: the window is ~13h, two
    -- days at most, unless an old maturing record holds it open
    -- (then the rest loads below, after meta says so)
    table.sort(pend)
    for i = math.max(1, #pend-1), #pend do
        blobs[#blobs+1] = CC.tree[pend[i]] .. " " .. pend[i]
    end
    local out = ""
    if #blobs > 0 then
        out = git_in(dir, "cat-file --batch='%(objectname) %(objectsize) %(rest)'",
            table.concat(blobs, "\n") .. "\n")
    end

    local G = { actions={}, members={}, order={}, pending={}, loaded={}, pdays={}, heads={} }
    batch(out, function (path, s)
        CC.src[path] = s
        local d, name = path:match("^(.*)/([^/]+)%.%a+$")
        if path == "meta.lua" then
            local t = load("return " .. s)()
            G.now      = t.now
            G.open     = t.open
            G.tot      = t.tot
            G.min0012  = t.min0012
            G.headless = t.headless
            G.order_n  = t.order_n
        elseif path == "heads.txt" then
            for time, member in s:gmatch("(%d+) ([^\n]+)\n") do
                G.heads[#G.heads+1] = { time=tonumber(time), member=member }
            end
        elseif d == "order" then
            G.tail = s
        elseif d == "pending" then
            G.loaded[tonumber(name)] = true
            rec_dec(s, G.pending)
        end
    end)
    assert(G.tot, "bug found : snapshot without tot : " .. cid)
    lazy_members(G)
    -- order: lazy chunks behind a proxy; the tail chunk now (every
    -- post appends to it), the rest on demand or all at once
    CACHE[G] = CC
    if not G.order_n then
        -- no count in meta (older snapshot): load every chunk
        G.order_n = #ords * ORDER_K   -- an upper bound for the loads
        lazy_order(G)
        M.order(G)
        G.order_n = rawlen(G.order)
    else
        lazy_order(G)
        if tail then
            local k = tonumber(tail:match("(%d+)%.txt$"))
            CC.ochunks = { [k]=true }
            local j = k*ORDER_K
            for cid in G.tail:gmatch("%x+") do
                j = j + 1
                rawset(G.order, j, cid)
            end
        end
    end
    G.tail = nil
    -- pending: every bucket day is known, only the WINDOW is loaded:
    -- from the oldest maturing (00-12/beg) record or 13h back,
    -- whichever is older; older days load on demand (`M.day`)
    local lo = math.min(G.min0012 or G.now, G.now - C.time.half - C.time.diff) // DAY
    local want = {}
    for _, path in ipairs(pend) do
        local day = tonumber(path:match("(%d+)%.txt$"))
        G.pdays[#G.pdays+1] = day
        if (day >= lo) and (not G.loaded[day]) then
            want[#want+1] = CC.tree[path] .. " " .. path
            G.loaded[day] = true
        end
    end
    if #want > 0 then
        local out2 = git_in(dir, "cat-file --batch='%(objectname) %(objectsize) %(rest)'",
            table.concat(want, "\n") .. "\n")
        batch(out2, function (path, s)
            CC.src[path] = s
            rec_dec(s, G.pending)
        end)
    end
    if #G.pending > 0 then
        table.sort(G.pending, function (a, b)
            if a.time == b.time then
                return a.cid < b.cid
            end
            return a.time < b.time
        end)
    end

    CC.order_n    = #G.order
    CC.order_last = G.order[#G.order]
    lazy(G)
    M.dirty(G)
    return G
end

--[[
-- Load the pending bucket holding time `t`, if not loaded yet.
-- Inputs:
--  - G [table]: chain state; MUTATED (G.pending, G.loaded)
--  - t [integer]: a member time
-- Outputs:
--  - [integer]: the bucket day
-- Errors:
--  - none
-- Callers:
--  - pend/advance (rules.lua): before inserting or popping there
--]]
function M.day (G, t)
    local day = t // DAY
    if G.loaded[day] then
        return day
    end
    G.loaded[day] = true
    local CC = CACHE[G]
    local path = ppath(day)
    if not (CC and CC.root and CC.tree[path]) then
        return day
    end
    local out = git_in(CC.dir, "cat-file --batch='%(objectname) %(objectsize) %(rest)'",
        CC.tree[path] .. " " .. path .. "\n")
    batch(out, function (p, s)
        CC.src[p] = s
        rec_dec(s, G.pending)
    end)
    table.sort(G.pending, function (a, b)
        if a.time == b.time then
            return a.cid < b.cid
        end
        return a.time < b.time
    end)
    return day
end

--[[
-- The next bucket day after `day` that exists on disk, or nil.
-- Inputs:
--  - G   [table]: chain state (G.pdays, sorted)
--  - day [integer]: a bucket day
-- Outputs:
--  - [integer?]: the next day
-- Errors:
--  - none
-- Callers:
--  - advance (rules.lua): walking a member's queue forward
--]]
function M.next_day (G, day)
    for _, d in ipairs(G.pdays) do
        if d > day then
            return d
        end
    end
    return nil
end

return M
