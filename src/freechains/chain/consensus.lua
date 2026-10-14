local M = {}

-- per-process memos of immutable DAG facts (commits never change):
--  - RANGE "com..tip" -> the commits of the range (list and set)
--  - BASE  "a b" -> merge-base of the pair (a < b)
--  - KEYS  "com..tip" -> the signer set of the range
local RANGE = {}
local BASE  = {}
local KEYS  = {}

--[[
-- The commits reachable from `tip` but not from `com`, once per
-- process (one walk serves the climb's floor test and the signers).
-- --topo-order: sync merges are dated 0 (git's date walk errs).
-- Inputs:
--  - com [string]: 40-hex commit hash (the floor)
--  - tip [string]: 40-hex commit hash
-- Outputs:
--  - [table]: { list = {cid, ...}, set = {cid=true} }
-- Errors:
--  - via exec: "bug found" if rev-list fails
-- Callers:
--  - winner (consensus.lua): each side's signers
--  - replay (consensus.lua): the climb stops outside the range
--]]
local function range (com, tip)
    local k = com .. ".." .. tip
    local r = RANGE[k]
    if not r then
        r = { list={}, set={} }
        local out = exec {
            cmd = "git -C " .. REPO .. " rev-list --topo-order " .. k
        }
        for cid in out:gmatch("%x+") do
            r.list[#r.list+1] = cid
            r.set[cid] = true
        end
        RANGE[k] = r
    end
    return r
end

--[[
-- The own-lineage state at `cid`: a function of the DAG below it.
-- Reads the snapshot, or derives it from the parents' states and
-- snapshots every commit on the way (never from a running replay).
--  - 1 parent: state(parent) + `cid`
--  - sync merge: state(winner) + loser side, `winner` decided by
--    the reps at the pair's merge-base
--  - beg merge (`like`): state(main) + beg side + `cid`
-- Inputs:
--  - cid  [string]: 40-hex commit hash, derefed
--  - refs [table?]: collects the new snapshots' ref lines for the
--    caller's one `GIT.refs` (else flushed here)
-- Outputs:
--  - [table]: the state at `cid` (a fresh copy: callers may mutate)
-- Errors:
--  - "malformed commit : expected 2-parent merge" : >2 parents
--  - re-raises ACTION.apply rejections
-- Callers:
--  - winner (consensus.lua): reps at the fork floor
--  - recv (sync.lua): remote validation, the new merge snapshot
--]]
-- A first-parent run without snapshots is collected first and
-- applied bottom-up, so long chains do not recurse.
function M.state (cid, refs)
    local run = {}
    local cur = cid
    local G
    -- the snapshots' refs: one update-ref at the end, or the caller's
    -- list (the caller flushes before anything reads them)
    local own = (refs == nil)
    refs = refs or {}
    while true do
        if STATE.has(cur) then
            G = STATE.read(cur)
            break
        else
            local ps = GIT.parents(cur)
            if #ps == 1 then
                run[#run+1] = cur
                cur = ps[1]
            elseif #ps == 2 then
                local l, r = ps[1], ps[2]
                local t = ACTION.read(false, cur)
                if t and t.action=='like' then
                    -- the beg's own lineage: its parent + itself, as admitted
                    if not STATE.has(r) then
                        local B = M.state(GIT.parents(r)[1])
                        ACTION.apply(B, r, true, refs)
                    end
                    G = M.state(l)
                    M.replay(G, l, r, false, true)
                else
                    local w, lo = M.winner(l, r)
                    G = M.state(w)
                    M.replay(G, w, lo, false)
                end
                ACTION.apply(G, cur, false, refs)
                break
            else
                error("malformed commit : expected 2-parent merge", 0)
            end
        end
    end
    -- the run's commits are new to the floor's state: no fetch to
    -- learn it; its shards, listed once (each write would list its own)
    STATE.absent(G, run)
    if #run > 1 then
        local pubs = {}
        for _, c in ipairs(run) do
            pubs[#pubs+1] = SSH.signer(REPO, c) or (G.open and C.anon) or nil
        end
        STATE.prelist(G, run, pubs)
    end
    for i = #run, 1, -1 do
        ACTION.apply(G, run[i], false, refs)
    end
    if own then
        STATE.flush(refs)
    end
    return G
end

--[[
-- Consensus: reps at the fork floor `com` decide the fork winner.
-- Traverse com..tip per side, collect signed keys, sum their reps at
-- `com` (own-lineage state, never the caller's running replay).
-- Higher sum wins, smaller cid breaks ties.
-- Inputs:
--  - a [string]: 40-hex commit hash (one tip)
--  - b [string]: 40-hex commit hash (the other tip)
--  - com [string?]: their merge-base, when the caller has it
-- Outputs:
--  - [string, string]: winner, loser (FF: ancestor loses)
-- Errors:
--  - via exec: "bug found" if git traversal fails
--  - re-raises M.state errors (the floor state)
-- Callers:
--  - recv (sync.lua): pick fst/snd between local and remote
--  - meet (consensus.lua): order each inner fork's replay
--  - state (consensus.lua): order a merge's two parents
--]]
-- `com` is the pairwise merge-base, computed HERE, and so is its
-- state: a caller's state depends on where its replay started (its
-- HEAD), so peers at the same DAG would score the same fork apart.
-- From a deeper point the two ranges would also overlap, and since
-- reps are summed over the SET of members, a commit both sides
-- already hold would hand its member's full reps to whichever side
-- lacked them -- letting undisputed history decide a disputed merge.
function M.winner (a, b, com)
    if not com then
        -- the pair's merge-base, once per process (symmetric)
        local k = (a < b) and (a .. " " .. b) or (b .. " " .. a)
        com = BASE[k]
        if not com then
            com = (exec {
                cmd = "git -C " .. REPO .. " merge-base " .. a .. " " .. b
            }):match("%x+")
            BASE[k] = com
        end
    end

    -- FF must be chosen
    if com == a then
        return b, a
    elseif com == b then
        return a, b
    end

    -- the floor: its `open` flag and the signers' members only
    -- (one batched read from the snapshot); else derived in full
    local G
    local peek = STATE.has(com)
    if peek then
        G = { members={} }
    else
        G = M.state(com)
    end

    --[[
    -- The members that signed `tip`'s side of the fork.
    -- Inputs:
    --  - tip [string]: one fork tip (com..tip is its region)
    -- Outputs:
    --  - [table]: set of pubkeys (key -> true)
    -- Errors:
    --  - via exec: "bug found" if git log fails
    -- Callers:
    --  - consensus (consensus.lua): once per side
    --]]
    local function collect_keys (tip)
        --[[
            com..tip = commits reachable from tip but not from com:
                        everything tip added since com
              com
              /  \
            c1    d1    com..a = {c1, c2}    <- what A contributed
             |     |    com..b = {d1, d2}    <- what B contributed
            c2    d2
            (a)   (b)
        ]]
        -- the range is immutable: once per process
        local memo = com .. ".." .. tip
        if KEYS[memo] then
            return KEYS[memo]
        end
        -- the range's commits in one batched read, then the signers;
        -- `anon`: an unsigned action (charged to the anon account in
        -- an open chain, known once the floor is read)
        local keys = { set={}, anon=false }
        local cids = range(com, tip).list
        GIT.cats(cids)
        for _, cid in ipairs(cids) do
            local key = SSH.signer(REPO, cid)
            -- `ACTION.is`: a merge is unsigned too, and it members nothing
            if key then
                keys.set[key] = true
            elseif ACTION.is(cid) then
                keys.anon = true
            end
        end
        KEYS[memo] = keys
        return keys
    end
    --[[
    -- Sum the G reps of a key set.
    -- Inputs:
    --  - keys [table]: set of pubkeys (key -> true)
    -- Outputs:
    --  - [integer]: sum of G.members[key].reps (unknown = 0)
    -- Errors:
    --  - none
    -- Callers:
    --  - consensus (consensus.lua): the two sides' scores
    --]]
    local function reps (keys)
        local n = 0
        for key in pairs(keys) do
            local T = G.members[key]
            if T then
                n = n + T.reps
            end
        end
        return n
    end

    local ra, rb = collect_keys(a), collect_keys(b)
    do
        local pubs = { C.anon }
        for k in pairs(ra.set) do pubs[#pubs+1] = k end
        for k in pairs(rb.set) do pubs[#pubs+1] = k end
        if peek then
            G.open, G.members = STATE.peek(com, pubs)
        else
            STATE.members(G, pubs)
        end
    end
    -- unsigned action in open chain -> anonymous
    local function keys (r)
        if not (r.anon and G.open) then
            return r.set
        end
        local t = { [C.anon]=true }
        for k in pairs(r.set) do
            t[k] = true
        end
        return t
    end
    local ka, kb = keys(ra), keys(rb)

    --[[
    -- Any member on this side is a dictator?
    -- Inputs:
    --  - keys [table]: set of pubkeys (key -> true)
    -- Outputs:
    --  - [boolean]: at least one dictator
    --]]
    local function dictator (keys)
        for key in pairs(keys) do
            local T = G.members[key]
            if T and T.dictator then
                return true
            end
        end
        return false
    end

    -- a DICTATOR side wins outright
    local da, db = dictator(ka), dictator(kb)
    if da ~= db then
        if da then
            return a, b
        else
            return b, a
        end
    end

    local sa, sb = reps(ka), reps(kb)
    if sa > sb then
        return a, b
    elseif sb > sa then
        return b, a
    elseif a < b then
        return a, b
    else
        return b, a
    end
end

--[[
-- Replay: climb from `com` up to `tip` in consensus order.
-- Calls `ACTION.apply` once per commit.
-- Inputs:
--  - G     [table]: state at `com`; MUTATED up to `tip`
--  - com   [string]: floor cid (already in G)
--  - tip   [string]: target cid
--  - trunc [boolean?]: the branch is a LOSER, so first failure voids the rest
--  - beg   [boolean?]: beg admission for the branch (beg merge)
-- Outputs:
--  - [string?]: last commit applied
--  - [string?]: the voiding error (trunc only)
-- Errors:
--  - re-raises ACTION.apply rejections (trunc = false); a
--    malformed loser is caught earlier, on its own validation
-- Callers:
--  - recv (sync.lua): loser replay
--  - state (consensus.lua): a merge's loser side
--]]
-- visited: never re-processes a commit (`ACTION.apply` itself skips
-- an action already in `G`, so shared history never re-applies)
-- inside (com..tip): stops climb from descending below its floor
-- without these the inner meet underflows to a root
function M.replay (G, com, tip, trunc, beg)
    local visited = {}
    local last          -- last commit applied

    -- the floor test: a commit the climb reaches (reachable from
    -- `tip`) is at/below `com` iff it is outside com..tip
    local inside = range(com, tip).set
    local climb, meet

    --[[
    -- Depth-first ascent com -> cur: parents first, then apply
    -- `cur` itself; a 2-parent merge recurses through `meet`.
    -- Inputs:
    --  - G   [table]: chain state; MUTATED
    --  - com [string]: floor cid (never descends below)
    --  - cur [string]: the commit to reach
    --  - beg [boolean]: beg admission for this branch
    -- Outputs:
    --  - none (sets upvalues `visited` and `last`)
    -- Errors:
    --  - "malformed commit : expected 2-parent merge" : >2 parents
    --  - re-raises ACTION.apply rejections
    -- Callers:
    --  - replay/meet (consensus.lua): mutual recursion
    --]]
    climb = function (G, com, cur, beg)
        if cur==com or visited[cur] or (not inside[cur]) then
            return
        else
            local ps = GIT.parents(cur)
            if #ps > 2 then
                error("malformed commit : expected 2-parent merge", 0)
            end
            local p1, p2 = ps[1], ps[2]
            if p2 == nil then
                climb(G, com, p1, beg)
            else
                -- only a `like` action merges (beg promotion): its
                -- second parent is the beg branch.
                -- a sync merge (or a malformed remote) reads nil:
                -- not a beg merge; `ACTION.apply` rejects malformed
                local t = ACTION.read(false, cur)
                meet(G, com, p1, p2, t and t.action=='like')
            end
            visited[cur] = true
            ACTION.apply(G, cur, beg)
            last = cur      -- not reached if `commit` raises
        end
    end

    --[[
    -- Resolve one fork: decide the winner BEFORE climbing, then
    -- climb winner side first (consensus decides). Shared history
    -- lands in the winner side's own order, never pre-applied.
    -- A beg merge keeps the writer's order: main, then the beg.
    -- Inputs:
    --  - G     [table]: chain state; MUTATED
    --  - com   [string]: outer floor cid
    --  - left  [string]: first parent (the merge's own history)
    --  - right [string]: second parent
    --  - right_is_beg [boolean]: right side is a beg promotion
    -- Outputs:
    --  - none
    -- Errors:
    --  - re-raises climb errors
    -- Callers:
    --  - climb (consensus.lua): on every 2-parent merge
    --]]
    meet = function (G, com, left, right, right_is_beg)
        if right_is_beg then
            climb(G, com, left,  false)
            climb(G, com, right, true)
        else
            local w, l = M.winner(left, right)
            climb(G, com, w, false)
            climb(G, com, l, false)
        end
    end

    local ok, e = pcall(climb, G, com, tip, beg or false)
    if ok then
        return last
    elseif trunc then
        return last, e      -- loser: the rest is voided
    else
        error(e, 0)
    end
end

return M
