C    = require "freechains.constants"
local ssh = require "freechains.chain.ssh"

REPO = ARGS.root .. "/chains/" .. ARGS.alias .. "/"
FC   = REPO .. ".freechains/"

function trailer (hash)
    local out = exec {
        cmd = "git -C " .. REPO ..
            " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. hash,
    }
    return out:match "(%S+)"
end

-- the git parents of `hash`: one step back in the DAG, no time
-- involved. Returns an array (empty for a root).
function parents (hash)
    local out = exec {
        cmd = "git -C " .. REPO .. " rev-list --parents -1 " .. hash,
        -- $ git rev-list --parents -1 a1b2c3...
        -- a1b2c3... d4e5f6... 7890ab...  # merge: 2 parents
    }
    local ps = {}
    for h in out:gmatch("%x+") do
        ps[#ps+1] = h
    end
    table.remove(ps, 1)
    return ps
end

-- post/like/revoke ancestors of `hash`: `parents` recursed through
-- `state` (and `merge`) commits, which are plumbing the protocol does
-- not expose. Returns an array of hashes (dedup'd).
function backs (hash)
    local ret = {}
    local see = {}
    local function rec (h)
        for _, p in ipairs(parents(h)) do
            local k = trailer(p)
            if k=='post' or k=='like' or k=='revoke' then
                if not see[p] then
                    see[p] = true
                    ret[#ret+1] = p
                end
            elseif k=='state' or k=='merge' then
                rec(p)
            else
                error("bug found : invalid trailer")
            end
        end
    end
    rec(hash)
    return ret
end

-- The four state files, all of them `serial` output and nothing else:
--
--   authors.lua   pubkey    -> { reps, time }
--   posts.lua     action id -> { reps, author, time, maturity, revoke }
--   order.lua     [ id, id, ... ]   consensus order
--   now.lua       newest time among all ancestors (causal high-water;
--                 a commit may sit at most `time.diff` below it, see
--                 `apply`. Genesis has no real ancestor, so `chains add`
--                 writes the chain creation time.)
--
-- The skel ships them EMPTY AND CANONICAL -- no comments, no examples.
-- `state_diff` compares them byte-for-byte against `serial`, so a
-- hand-written file anywhere in a tree is a false rejection on the
-- first commit that inherits it.
function write (G)
    local function f (V, file)
        local f = io.open(file, "w")
        f:write(serial(V))
        f:close()
    end

    f(G.authors, FC .. "state/authors.lua")
    f(G.posts,   FC .. "state/posts.lua")
    f(G.order,   FC .. "state/order.lua")
    f(G.now,     FC .. "state/now.lua")
end

-- The state a commit CARRIES vs the state a replay COMPUTED.
-- `write` is the writer, this is its verifier: both go through
-- `serial`, whose keys are sorted, so the bytes match exactly.
-- Returns the name of the first file that differs, or nil.
--
-- Two of the four files are deliberately absent:
--
-- `now` is DAG-derived, not replay-accumulated: `write` is called with
-- `PEAKS(...)` forced into `G.now` at every merge (sync.lua), so the
-- accumulated value is not what lands in the tree. `commit` in sync.lua
-- already checks it against the parents, which is stronger anyway.
--
-- `order` is BLOCKED on a separate bug: two honest peers can settle on
-- different orders for the same posts. In tst/bug-climb-ancestor the
-- nested-merge topology leaves A with [p1,p2,...] and D with [p2,p1,...]
-- permanently -- the two entries that forked at genesis, swapped. That
-- test only asserts D's order HOLDS every post, never the ordering, so
-- it passes. Until consensus is actually deterministic here, comparing
-- `order` is a false rejection, not a check.
function state_diff (G, hash)
    local T = {
        { "authors", G.authors },
        { "posts",   G.posts   },
    }
    for _, e in ipairs(T) do
        local name, V = e[1], e[2]
        local src = exec { trim=false,
            cmd = "git -C " .. REPO .. " show " .. hash ..
                ":.freechains/state/" .. name .. ".lua",
        }
        if src ~= serial(V) then
            return name
        end
    end
    return nil
end

-- a state file exactly as a commit's tree holds it: raw `serial`
-- bytes, so writer and verifier can compare byte-for-byte
local function tree_raw (hash, name)
    return exec { trim=false,
        cmd = "git -C " .. REPO .. " show " .. hash ..
            ":.freechains/state/" .. name .. ".lua",
    }
end

-- the whole state a commit CARRIES, shaped as an `apply` argument
local function tree_state (hash)
    local G = {}
    for _, name in ipairs { "authors", "posts", "order", "now" } do
        G[name] = load(tree_raw(hash, name))()
    end
    return G
end

-- The action `hash` performs, as `apply` arguments, decoded from the
-- commit alone plus the state it inherits -- never from a replay:
--
-- `beg` is not a free choice. A signed post validates as EXACTLY one
-- of beg / non-beg, decided by the author's reps in `pre`: `apply`
-- rejects a beg with reps>0 and a non-beg with reps<=0. So the flag
-- `chain post` passed is recoverable, and a forger who picks the
-- other one lands on a state that will not match.
--
-- A beg-accepting `like` is told apart by the target's `maturity`,
-- and it is a MERGE: `like -X ours` keeps OUR state files, so the beg
-- entry lives only on parent 2. Injected here exactly as `chain like`
-- does when it creates the commit.
--
-- Returns { kind, time, T }, or nil plus a reason.
local function action (pre, hash)
    local out = exec {
        cmd = "git -C " .. REPO ..
            " log -1 --format='%at %(trailers:key=Freechains,valueonly)' " .. hash,
    }
    local time, kind = out:match("(%S+)%s+(%S+)")
    time = tonumber(time)
    local key = ssh.verify(REPO, hash)

    if kind == 'post' then
        local reps = (pre.authors[key] and pre.authors[key].reps) or 0
        return { kind=kind, time=time, T = {
            hash = hash,
            sign = key,
            beg  = (key==nil) or (reps<=0),
        } }
    elseif kind=='like' or kind=='revoke' then
        -- vote metadata lives under .freechains/<kind>s/
        local file = exec {
            cmd = "git -C " .. REPO ..
                " diff-tree --no-commit-id -r --name-only " .. hash ..
                "^1 " .. hash .. " -- .freechains/" .. kind .. "s/",
        }
        file = file:match("(%S+)")
        if not file then
            return nil, "missing metadata file"
        end
        local f = load(exec {
            cmd = "git -C " .. REPO .. " show " .. hash .. ":" .. file,
        })
        if not f then
            return nil, "invalid lua metadata"
        end
        local ok, t = pcall(f)
        if (not ok) or type(t)~='table' then
            return nil, "invalid lua metadata"
        end

        -- beg merge: the target entry lives on parent 2 only
        local ps = parents(hash)
        if ps[2] and t.post then
            local P = load(tree_raw(ps[2], "posts"))()
            pre.posts[t.post] = pre.posts[t.post] or P[t.post]
        end

        local to_beg = (
            kind=='like' and math.type(t.n)=='integer' and t.n>0 and
            t.post and pre.posts[t.post] and
            pre.posts[t.post].maturity=="beg"
        )
        return { kind=kind, time=time, T = {
            hash   = hash,
            sign   = key,
            n      = t.n,
            post   = t.post,
            author = t.author,
            beg    = to_beg,
        } }
    else
        return nil, "invalid kind"
    end
end

-- Parent-relative verification of a `state` commit S:
--
--     state(S) == apply( state(parent(S)), action(parent(S)) )
--
-- Both sides are read from TREES, so the check is context-free: it
-- holds wherever S sits in the DAG, needs no accumulated `G`, no
-- `oct`, no climb order, and its result is a fact about content-
-- addressed data that can be memoized forever. This is what
-- `state_diff` cannot do, being relative to a replay.
-- See .claude/plans/260802-state-verify.md.
--
-- Returns nil when the link holds, else a short reason.
--
-- Out of scope here:
--
--   0 parents   genesis: the trusted anchor of the induction
--   2 parents   a merge: its state is `combine`, not `apply`, and
--               costs a replay of one side (`state_merge`)
--   `now`       already checked against `PEAKS(parents)` in `commit`
--   `order`     blocked on a separate bug: two honest peers settle
--               on DIFFERENT orders for the same posts, so comparing
--               it is a false rejection, not a check
--
-- Action commits need no link of their own: they only ADD files, so
-- the create-mode check already pins their state to their parent's.
function state_link (hash)
    assert(trailer(hash) == 'state', "bug found : not a state commit")

    local ps = parents(hash)
    if #ps == 0 then
        return nil          -- genesis
    end
    assert(#ps == 1, "bug found : merge : see state_merge")

    local up  = ps[1]
    local pre = tree_state(up)

    -- a `state` parent means no action between the two: the state
    -- must then survive unchanged
    if trailer(up) ~= 'state' then
        local A, err = action(pre, up)
        if not A then
            return err
        end
        local ok, err = apply(pre, A.kind, A.time, A.T)
        if not ok then
            return "apply : " .. err
        end
    end

    for _, name in ipairs { "authors", "posts" } do
        if serial(pre[name]) ~= tree_raw(hash, name) then
            return name
        end
    end
    return nil
end

-- REVOKED when either the author's or the community's net revoke sum is negative.
function is_revoked (p)
    local r = p.revoke or {}
    return ((r.author or 0) < 0) or ((r.others or 0) < 0)
end

-- posts hashes in a stable order: (time, hash); consolidated posts
-- (time == nil) sort last, then lexicographically by hash. Makes the
-- discount/consolidation scans deterministic across OS processes.
local function ordered (posts)
    local hs = {}
    for h in pairs(posts) do
        hs[#hs+1] = h
    end
    table.sort(hs, function (a, b)
        local ta = posts[a].time or math.huge
        local tb = posts[b].time or math.huge
        if ta == tb then
            return a < b
        else
            return ta < tb
        end
    end)
    return hs
end

-- a commit's OWN author date, which says nothing about its ancestors:
-- a post carries the state file of the commit BEFORE it, so its own
-- stamp lives nowhere else.
local function TIME (hash)
    return assert(tonumber((exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%at " .. hash,
    })))
end

-- the peak RECORDED in a commit's tree (`state/now.lua`): the newest
-- time among all of its ancestors. Derived, never trusted: `commit` in
-- sync.lua checks every stored value against its parents' before using
-- it. Only `state` commits are current -- a post/like may just ADD
-- files, so its tree still holds the previous state commit's value.
function PEAK (hash)
    local src = exec {
        cmd = "git -C " .. REPO .. " show " .. hash .. ":.freechains/state/now.lua",
    }
    return load(src)()
end

-- the peak COMPUTED over a set of commits: the peak each one recorded,
-- or its own time if newer (a post's tree still holds the PREVIOUS
-- peak, so its stamp lives nowhere else). The only place the fold
-- happens: `PEAKS(parents(h))` is the newest time causally preceding
-- `h`, the value a state commit must record, so writer and verifier
-- share the formula. Asserts on an empty set: only a root has no
-- parents, and no path takes a root this far.
function PEAKS (hs)
    local mx = nil
    for _, h in ipairs(hs) do
        local t = math.max(TIME(h), PEAK(h))
        mx = math.max(mx or t, t)
    end
    return assert(mx)
end

function apply (G, kind, time, T)
    local mutate = (kind ~= 'reps')

    -- TIME: monotonicity, discount, consolidation
    do
        -- causal freshness: a commit may sit at most `time.diff` below
        -- everything that precedes it. Read from the DAG, so it does not
        -- depend on the order a replay applies commits in (consensus order
        -- is not chronological order).
        if mutate then
            local up = PEAKS(parents(T.hash))
            if time < up-C.time.diff then
                return false, "too old"
            end
        end

        -- discount scan (maybe signed at same G.now)
        local sign = (mutate and T.sign) or nil
        if time>G.now or sign then
            for _, hash in ipairs(ordered(G.posts)) do
                local entry = G.posts[hash]
                if entry.maturity == "00-12" then
                    local subs = {}
                    for h2, other in pairs(G.posts) do
                        if other.author and other.time and other.time>entry.time then
                            subs[other.author] = true
                        end
                    end
                    if sign then
                        subs[sign] = true
                    end

                    local cur = 0
                    for a in pairs(subs) do
                        cur = cur + math.max(0, (G.authors[a] and G.authors[a].reps) or 0)
                    end
                    local tot = 0
                    for _, v in pairs(G.authors) do
                        tot = tot + math.max(0, v.reps)
                    end

                    local ratio = (tot>0 and cur/tot) or 0
                    local discount = C.time.half * math.max(0, 1 - 2*ratio)

                    if time >= entry.time + discount then
                        -- signed beg?
                        if entry.author then
                            G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                        end
                        entry.maturity = "12-24"
                    end
                end
            end
        end

        -- consolidation scan
        if time > G.now then
            for _, hash in ipairs(ordered(G.posts)) do
                local entry = G.posts[hash]
                if entry.maturity == "12-24" then
                    if time >= entry.time+C.time.full then
                        if entry.author then
                            local last = G.authors[entry.author].time
                            if time-last >= C.time.full then
                                G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                                G.authors[entry.author].time = last + C.time.full
                                entry.maturity = nil
                                entry.time  = nil
                            end
                        else
                            -- authorless (unsigned beg): consolidate, no credit
                            entry.maturity = nil
                            entry.time  = nil
                        end
                    end
                end
            end
        end

        if time > G.now then
            G.now = time
        end
    end

    if mutate then
        if kind == 'post' then
            -- validation
            assert(T.sign or T.beg)
            if T.sign then
                if T.beg then
                    local reps = G.authors[T.sign] and G.authors[T.sign].reps or 0
                    if reps > 0 then
                        return false, "--beg error : author has sufficient reputation"
                    end
                else
                    local reps = G.authors[T.sign] and G.authors[T.sign].reps or 0
                    if reps <= 0 then
                        return false, "insufficient reputation"
                    end
                end
            end

            -- mutation
            G.posts[T.hash] = {
                author   = T.sign,
                time     = time,
                maturity = (T.beg and 'beg') or (T.sign and '00-12') or 'beg',
                reps     = 0,
                revoke   = { author=0, others=0 },
            }
            if T.sign then
                G.authors[T.sign] = G.authors[T.sign] or { reps=0 }
                if not T.beg then
                    G.authors[T.sign].reps = G.authors[T.sign].reps - C.reps.cost
                    G.authors[T.sign].time = G.authors[T.sign].time or time
                        -- do not set for beg, bc not available to others
                end
            end

        elseif kind=='like' or kind=='revoke' then
            -- validation
            assert(T.sign, "bug found")
            if math.type(T.n)~='integer' or T.n==0 then
                return false, "invalid number : expects non-zero integer"
            end
            if (T.post and T.author) or (not T.post and not T.author) then
                return false, "invalid target : expects 'post' or 'author'"
            end
            -- revoke/unrevoke are post-only
            if kind=='revoke' and (not T.post) then
                return false, "invalid target : expects 'post'"
            end
            if T.post and (not G.posts[T.post]) then
                return false, "invalid target : post not found"
            end

            -- author self-revoke (right to be forgotten) is free and ungated
            local self_revoke = (
                kind=='revoke' and T.n<0 and G.posts[T.post].author==T.sign
            )

            -- must afford the full vote magnitude (no debt); self-revoke is free
            local reps = (G.authors[T.sign] and G.authors[T.sign].reps) or 0
            if (not self_revoke) and reps<math.abs(T.n) then
                return false, "insufficient reputation"
            end

            -- mutation
            if not self_revoke then
                G.authors[T.sign].reps = reps - math.abs(T.n)
            end
            local n = T.n * (100 - C.like.tax) // 100
            if T.post then
                local a = G.posts[T.post].author
                if not (self_revoke or (kind=='revoke' and T.n>0)) then
                    if a then
                        G.authors[a] = G.authors[a] or { reps=0 }
                        G.authors[a].reps = G.authors[a].reps + n//C.like.split
                    else
                        assert(T.beg)
                    end
                    G.posts[T.post].reps = G.posts[T.post].reps + n//C.like.split
                end

                -- revoke axis: sum the signed magnitude T.n (revoke n<0,
                -- unrevoke n>0). A positive `like` also counts as an
                -- `unrevoke` (the converse is false: a `dislike` never
                -- revokes). Author self-revoke feeds the absolute
                -- `author` channel; everyone else the `others` channel.
                if kind=='revoke' or T.n>0 then
                    local author = G.posts[T.post].author
                    local r = G.posts[T.post].revoke or { author=0, others=0 }
                    G.posts[T.post].revoke = r
                    if kind=='revoke' and author and T.sign==author then
                        r.author = r.author + T.n
                    else
                        r.others = r.others + T.n
                    end
                end

                if T.beg then
                    G.posts[T.post].maturity = "00-12"
                    G.posts[T.post].time = time
                    if a then
                        G.authors[a].time = G.authors[a].time or time
                    end
                end
            else
                G.authors[T.author] = G.authors[T.author] or { reps=0 }
                G.authors[T.author].reps = G.authors[T.author].reps + n
            end
        end
    end

    -- cap all authors at max
    for k, v in pairs(G.authors) do
        if v.reps > C.reps.max then
            v.reps = C.reps.max
        end
    end

    return true
end
