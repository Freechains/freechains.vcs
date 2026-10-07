local M = {}

-- memos: a commit's parents, and its raw object
local MEMO = {}
local OBJS = {}

--[[
-- The empty tree's hash.
-- All commits carry EMPTY trees, since all data lives in the commit MESSAGE.
-- Trees and blobs are not used by actions at all (the cid IS the commit).
-- Inputs:
--  - none
-- Outputs:
--  - [string]: 40-hex empty-tree hash
-- Errors:
--  - none
-- Callers:
--  - commit (git.lua): every minted commit uses it
--  - apply (action.lua): the anti-smuggling tree check
--]]
-- the SHA-1 of the empty tree is a constant of git itself
-- (`git hash-object -t tree /dev/null`); every chain repo is SHA-1
local tree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
function M.tree ()
    return tree
end

--[[
-- Mint a commit: the object written from Lua (no commit-tree), signed
-- by ssh-keygen as git signs (verify-commit accepts it).
-- Inputs:
--  - ref [boolean]:    true also moves HEAD; false mints loose only
--  - err [string?]:    exec err message on failure (nil: bug found)
--  - t [table]: commit data (what shapes the commit BYTES)
--      - parents [table]:  {cid [, cid]} parent hashes
--      - msg [string?]:    message metadata or nil (merge)
--      - date [integer?]:  unix secs, author+committer DATE or nil (merge, genesis)
--      - sign [string?]:   ssh private key path -> -S gpgsig
-- Outputs:
--  - [string]: the new commit's 40-hex cid
-- Errors:
--  - `err` (ERROR) or "bug found" when the key cannot sign
-- Callers:
--  - commit (action.lua): action mint
--  - recv (sync.lua): the loser-branch sync merge
--]]
function M.commit (ref, err, t)
    -- the object as `commit-tree` would write it: no process but
    -- the signer's (ssh-keygen, which git would run too)
    local date = (t.date or 0) .. " +0000"
    local hs = { "tree " .. M.tree() }
    for _, p in ipairs(t.parents) do
        hs[#hs+1] = "parent " .. p
    end
    hs[#hs+1] = "author - <-> " .. date
    hs[#hs+1] = "committer - <-> " .. date
    local msg = t.msg or ""
    if t.sign then
        -- as git does: `ssh-keygen -Y sign` over the unsigned object,
        -- the armored signature folded into a gpgsig header (the
        -- continuation lines start with a space)
        local path = REPO .. "sign-buf"
        local f = assert(io.open(path, "wb"))
        f:write(table.concat(hs, "\n"), "\n\n", msg)
        f:close()
        local ok = exec { err=false, stderr=false,
            cmd = "ssh-keygen -Y sign -n git -f " .. t.sign .. " " .. path,
        }
        os.remove(path)
        local g = ok and io.open(path .. ".sig", "rb")
        local sig = g and g:read("a")
        if g then
            g:close()
        end
        os.remove(path .. ".sig")
        if not sig then
            if err then
                ERROR(err)
            end
            error("bug found : ssh-keygen sign : " .. t.sign)
        end
        local ls = {}
        for l in sig:gmatch("[^\n]+") do
            ls[#ls+1] = l
        end
        hs[#hs+1] = "gpgsig " .. table.concat(ls, "\n ")
    end
    local body = table.concat(hs, "\n") .. "\n\n" .. msg
    local cid = require("freechains.chain.state").put("commit", body)
    OBJS[cid] = body
    if ref then
        exec {
            cmd = "git -C " .. REPO .. " update-ref HEAD " .. cid,
        }
    end
    return cid
end

--[[
-- Many ref updates in ONE `update-ref --stdin` (a post moves three
-- refs: its snapshot, its payload anchor, HEAD).
-- Inputs:
--  - ops [table]: array of update-ref stdin lines:
--    "update <ref> <new>", "create <ref> <new>", "delete <ref>"
-- Outputs:
--  - none
-- Errors:
--  - none: the batch is one transaction; if it fails (a `create` of
--    an existing ref), each line runs alone, failures ignored, as
--    the single calls did
-- Callers:
--  - post/like: the accepted action's refs
--  - state (consensus.lua): a run's deferred snapshot refs
--]]
function M.refs (ops)
    if #ops == 0 then
        return
    end
    local path = REPO .. "git-stdin"
    local function run (lines)
        local f = assert(io.open(path, "w"))
        f:write(table.concat(lines, "\n"), "\n")
        f:close()
        local ok = exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " update-ref --stdin < " .. path,
        }
        return ok
    end
    if (not run(ops)) and (#ops > 1) then
        for _, op in ipairs(ops) do
            run { op }
        end
    end
    os.remove(path)
end


--[[
-- The raw commit object of `cid` (headers, blank line, message),
-- memoized: one `cat-file` serves every parse of the same commit
-- (ACTION.is/read, the parents, the tree, the signature).
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed (immutable fact)
-- Outputs:
--  - [string?]: the object text, nil if `cid` is not a commit
--    (misses are not memoized: a fetch may bring it later)
-- Errors:
--  - none
-- Callers:
--  - parents/tree_of (git.lua): the header lines
--  - is/read (action.lua): the message
--  - signer (ssh.lua): the gpgsig header
--]]
function M.cat (cid)
    local out = OBJS[cid]
    if out == nil then
        out = exec { trim=false, err=false, stderr=false,
            cmd = "git -C " .. REPO .. " cat-file commit " .. cid,
        }
        if out then
            OBJS[cid] = out
        else
            out = nil
        end
    end
    return out
end

--[[
-- Memoize many commit objects in ONE `cat-file --batch` (a pull
-- reads every new commit several times: parents, parse, signature).
-- Inputs:
--  - cids [table]: array of 40-hex commit hashes
-- Outputs:
--  - none: `cat` serves them from memory
-- Errors:
--  - via exec: "bug found" if cat-file fails
-- Callers:
--  - recv (sync.lua): the remote's new commits
--]]
function M.cats (cids)
    local want = {}
    for _, cid in ipairs(cids) do
        if not OBJS[cid] then
            want[#want+1] = cid
        end
    end
    if #want == 0 then
        return
    end
    local path = REPO .. "git-stdin"
    local f = assert(io.open(path, "w"))
    f:write(table.concat(want, "\n"), "\n")
    f:close()
    local out = exec { trim=false,
        cmd = "git -C " .. REPO .. " cat-file --batch < " .. path,
    }
    os.remove(path)
    -- "<sha> <type> <size>\n<bytes>\n" per object, or "<sha> missing\n"
    local pos = 1
    while pos <= #out do
        local nl = out:find("\n", pos, true)
        local sha, ty, size = out:sub(pos, nl-1):match("^(%x+) (%a+) (%d+)$")
        if sha then
            size = tonumber(size)
            if ty == "commit" then
                OBJS[sha] = out:sub(nl+1, nl+size)
            end
            pos = nl + size + 2
        else
            pos = nl + 1
        end
    end
end

--[[
-- The tree of commit `cid`, from its header.
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed
-- Outputs:
--  - [string?]: 40-hex tree hash, nil if not a commit
-- Errors:
--  - none
-- Callers:
--  - apply (action.lua): the anti-smuggling tree check
--]]
function M.tree_of (cid)
    local out = M.cat(cid)
    return out and out:match("^tree (%x+)\n")
end

--[[
-- The value of a ref, from its loose file when git keeps one (HEAD
-- and a freshly moved `main` always; a beg's ref until a sweep packs
-- it), else `rev-parse`: a file read instead of a process.
-- Inputs:
--  - name [string]: a full ref name, or HEAD
-- Outputs:
--  - [string?]: 40-hex hash, nil if the ref does not exist
-- Errors:
--  - none
-- Callers:
--  - init (chain/init.lua): HEAD
--  - like (like.lua): a beg's ref
--  - recv (sync.lua): refs/genesis
--]]
function M.ref (name)
    local f = io.open(REPO .. name)
    if f then
        local s = f:read("l")
        f:close()
        local sym = s and s:match("^ref: (%S+)")
        if sym then
            return M.ref(sym)
        elseif s and s:match("^%x+$") then
            return s
        end
    end
    return exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " rev-parse --verify --quiet " .. name,
    } or nil
end

--[[
-- Resolve a ref/rev (HEAD, HEAD^1, refs/...) to its cid.
-- Inputs:
--  - rev [string]: anything rev-parse accepts
-- Outputs:
--  - [string]: 40-hex commit hash
-- Errors:
--  - via exec: "bug found" if rev-parse fails
-- Callers:
--  - init (chain/init.lua): G = state at HEAD
--  - post/like: parents of the mint
--  - sync (sync.lua): tips and merge parents
--]]
function M.deref (rev)
    -- parenthesized: exec returns (out, code)
    return (exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. rev,
    })
end

--[[
-- The git parents of `cid`: one step back in the DAG, memoized
-- (immutable fact, so only pass DEREFED cids: HEAD^1 moves).
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed
-- Outputs:
--  - [table]: array of parent cids, empty for a root;
--    the MEMOIZED table itself: NEVER mutate it
-- Errors:
--  - "bug found : not a commit" : unknown cid
-- Callers:
--  - backs/apply (action.lua): structural ancestry
--  - climb (consensus.lua): replay descent
--  - recv (sync.lua): beg parent validation
--  - list dag (list.lua): ups of each node
--]]
function M.parents (cid)
    if MEMO[cid] then
        return MEMO[cid]
    end
    -- the header lines, before the first blank line:
    --   tree <hash>
    --   parent <hash>      (0: root, 1: action, 2: merge)
    local out = M.cat(cid)
    if not out then
        error("bug found : not a commit : " .. cid)
    end
    local ps = {}
    for h in out:match("^(.-)\n\n"):gmatch("\nparent (%x+)") do
        ps[#ps+1] = h
    end
    MEMO[cid] = ps
    return ps
end

return M
