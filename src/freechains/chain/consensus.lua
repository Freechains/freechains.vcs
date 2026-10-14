local M = {}

-- Same actions, same order: the order of a merge is a function of
-- its PARENT SET, never of which pairs met first.
--  - a sync joins the maximal tips of both sides in ONE merge, its
--    parents sorted, dated 0, unsigned: the same tip set mints the
--    same commit on every peer (`join`)
--  - a merge's state ranks its parents by the reps at their common
--    floor (`rank`), then folds them in that order (`fold`)

-- per-process memos of immutable DAG facts (commits never change):
--  - RANGE "tip ^f1 ^f2" -> the commits of the range (list and set)
--  - BASES "a b c" -> the merge-bases of a set (sorted)
--  - KEYS  "tip ^f1 ^f2" -> the signer set of the range
--  - RANK  "a b c" -> the set, ranked
local RANGE = {}
local BASES = {}
local KEYS  = {}
local RANK  = {}

--[[
-- A sorted copy of a set of cids, and its memo key.
-- Inputs:
--  - ps [table]: array of 40-hex commit hashes
-- Outputs:
--  - [table]: sorted copy
--  - [string]: the cids joined by spaces
-- Errors:
--  - none
-- Callers:
--  - bases/rank/join (consensus.lua): set keys
--]]
local function sorted (ps)
    local s = table.move(ps, 1, #ps, 1, {})
    table.sort(s)
    return s, table.concat(s, " ")
end

--[[
-- The commits reachable from `tip` but not from any of `floors`,
-- once per process (one walk serves the climb's floor test and the
-- signers).
-- --topo-order: sync merges are dated 0 (git's date walk errs).
-- Inputs:
--  - floors [table]: array of 40-hex commit hashes
--  - tip    [string]: 40-hex commit hash
-- Outputs:
--  - [table]: { list = {cid, ...}, set = {cid=true} }
-- Errors:
--  - via exec: "bug found" if rev-list fails
-- Callers:
--  - rank (consensus.lua): each side's signers
--  - replay (consensus.lua): the climb stops outside the range
--]]
local function range (floors, tip)
    local k = tip
    for _, f in ipairs(floors) do
        k = k .. " ^" .. f
    end
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
-- The merge-bases of a set: its maximal common ancestors.
-- Inputs:
--  - ps [table]: array of 2+ 40-hex commit hashes
-- Outputs:
--  - [table]: sorted array of cids (several on a criss-cross)
-- Errors:
--  - via exec: "bug found" if merge-base fails
-- Callers:
--  - rank (consensus.lua): the floor of a set
--]]
function M.bases (ps)
    local s, k = sorted(ps)
    local bs = BASES[k]
    if not bs then
        local out = exec {
            cmd = "git -C " .. REPO .. " merge-base --all " ..
                ((#s > 2) and "--octopus " or "") .. k
        }
        bs = {}
        for h in out:gmatch("%x+") do
            bs[#bs+1] = h
        end
        table.sort(bs)
        BASES[k] = bs
    end
    return bs
end

--[[
-- The canonical merge of a set: parents sorted, dated 0, empty
-- message, unsigned, so the same set mints the same commit on
-- every peer (a set of one is that commit).
-- Inputs:
--  - ps [table]: array of 1+ 40-hex commit hashes, independent
-- Outputs:
--  - [string]: 40-hex commit hash
-- Errors:
--  - none
-- Callers:
--  - rank (consensus.lua): the floor of a criss-cross
--  - recv (sync.lua): the new main
--]]
function M.join (ps)
    if #ps == 1 then
        return ps[1]
    end
    return GIT.commit(false, nil, {
        parents = (sorted(ps)),
    })
end

--[[
-- The nearest actions below some commits, maximal: the tip set a
-- canonical merge of them joins (the genesis when there is none).
-- Inputs:
--  - revs [table]: array of 40-hex commit hashes
-- Outputs:
--  - [table]: sorted array of independent cids
-- Errors:
--  - via exec: "bug found" if merge-base fails
-- Callers:
--  - recv (sync.lua): my main and the remote's
--  - live (consensus.lua): after dropping voided tips
--]]
function M.tips (revs)
    local ts = ACTION.backs(revs)
    if #ts == 0 then
        return { GIT.ref("refs/genesis") }
    elseif #ts == 1 then
        return ts
    end
    local out = exec {
        cmd = "git -C " .. REPO .. " merge-base --independent " ..
            table.concat(ts, " "),
    }
    local T = {}
    for h in out:gmatch("%x+") do
        T[#T+1] = h
    end
    table.sort(T)
    return T
end

--[[
-- The own-lineage state at `cid`: a function of the DAG below it.
-- Reads the snapshot, or derives it from the parents' states and
-- snapshots every commit on the way (never from a running replay).
--  - 1 parent: state(parent) + `cid`
--  - sync merge: the fold of its parent set (`fold`)
--  - beg merge (`like`): state(main) + beg side + `cid`
-- Inputs:
--  - cid  [string]: 40-hex commit hash, derefed
--  - refs [table?]: collects the new snapshots' ref lines for the
--    caller's one `GIT.refs` (else flushed here)
-- Outputs:
--  - [table]: the state at `cid` (a fresh copy: callers may mutate)
-- Errors:
--  - "malformed commit : unexpected root" : a root but the genesis
--  - re-raises ACTION.apply rejections
-- Callers:
--  - rank (consensus.lua): reps at the fork floor
--  - fold (consensus.lua): the first parent's state
--  - recv (sync.lua): remote validation, the new main
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
            elseif #ps >= 2 then
                local t = ACTION.read(false, cur)
                if t and t.action=='like' and (#ps == 2) then
                    -- the beg's own lineage: its parent + itself, as admitted
                    local l, r = ps[1], ps[2]
                    if not STATE.has(r) then
                        local B = M.state(GIT.parents(r)[1])
                        ACTION.apply(B, r, true, refs)
                    end
                    G = M.state(l)
                    M.replay(G, { l }, r, false, true)
                else
                    G = M.fold(ps)
                end
                ACTION.apply(G, cur, false, refs)
                break
            else
                error("malformed commit : unexpected root", 0)
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
-- Consensus: rank a set of fork tips by the reps at their common
-- floor. Per tip, its side is what it holds beyond the floor; the
-- side's score sums the floor reps of its signers.
-- A dictator side first, then the higher score, then smaller cid.
-- Inputs:
--  - ps [table]: array of 2+ 40-hex commit hashes
-- Outputs:
--  - [table]: the same cids, winner first (a tip below the others,
--    a legacy fast-forward pair, ranks last: its side is empty)
-- Errors:
--  - via exec: "bug found" if git traversal fails
--  - re-raises M.state errors (the floor state)
-- Callers:
--  - fold (consensus.lua): the order of a merge's parents
--  - meet (consensus.lua): the order of an inner merge's parents
--]]
-- The floor is the set's merge-bases, computed HERE, and so is its
-- state: a caller's state depends on where its replay started (its
-- HEAD), so peers at the same DAG would score the same fork apart.
-- From a deeper point the sides would also overlap more, and since
-- reps are summed over the SET of members, a commit both sides
-- already hold would hand its member's full reps to whichever side
-- lacked them -- letting undisputed history decide a disputed merge.
-- Several bases (a criss-cross) form the floor as their own
-- canonical merge (`join`): its state is theirs, folded.
function M.rank (ps)
    local s, k = sorted(ps)
    if RANK[k] then
        return RANK[k]
    end
    local bs = M.bases(s)
    local isb = {}
    for _, b in ipairs(bs) do
        isb[b] = true
    end

    -- the floor: its `open` flag and the signers' members only
    -- (one batched read from the snapshot); else derived in full
    local com = M.join(bs)
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
    --  - tip [string]: one fork tip (bases..tip is its side)
    -- Outputs:
    --  - [table]: { set = pubkeys (key -> true), anon = boolean }
    -- Errors:
    --  - via exec: "bug found" if git log fails
    -- Callers:
    --  - rank (consensus.lua): once per side
    --]]
    local function collect_keys (tip)
        -- the range is immutable: once per process
        local memo = tip .. " ^" .. table.concat(bs, " ^")
        if KEYS[memo] then
            return KEYS[memo]
        end
        -- the range's commits in one batched read, then the signers;
        -- `anon`: an unsigned action (charged to the anon account in
        -- an open chain, known once the floor is read)
        local keys = { set={}, anon=false }
        local cids = range(bs, tip).list
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

    local rs = {}
    local pubs = { C.anon }
    for _, p in ipairs(s) do
        rs[p] = collect_keys(p)
        for key in pairs(rs[p].set) do
            pubs[#pubs+1] = key
        end
    end
    if peek then
        G.open, G.members = STATE.peek(com, pubs)
    else
        STATE.members(G, pubs)
    end

    -- per side: below the others, any dictator, the reps sum
    -- (unsigned action in open chain -> anonymous)
    local info = {}
    for _, p in ipairs(s) do
        local ks = rs[p].set
        if rs[p].anon and G.open then
            ks = { [C.anon]=true }
            for key in pairs(rs[p].set) do
                ks[key] = true
            end
        end
        local d, n = false, 0
        for key in pairs(ks) do
            local T = G.members[key]
            if T then
                n = n + T.reps
                d = d or (T.dictator and true or false)
            end
        end
        info[p] = { low=(isb[p] or false), dict=d, reps=n }
    end

    table.sort(s, function (a, b)
        local x, y = info[a], info[b]
        if x.low ~= y.low then
            return y.low
        elseif x.dict ~= y.dict then
            return x.dict
        elseif x.reps ~= y.reps then
            return x.reps > y.reps
        else
            return a < b
        end
    end)
    RANK[k] = s
    return s
end

--[[
-- The state of a parent set: the winner's own-lineage state, then
-- each other side replayed in rank order. A failure voids the rest
-- of ITS side only: the action is valid in its own branch, but not
-- in this order.
-- Inputs:
--  - ps [table]: array of 2+ 40-hex commit hashes
-- Outputs:
--  - [table]: the folded state (fresh)
--  - [string?]: the first voiding error
-- Errors:
--  - re-raises M.state errors (the winner's own lineage)
-- Callers:
--  - state (consensus.lua): a sync merge
--]]
function M.fold (ps)
    local r = M.rank(ps)
    local G = M.state(r[1])
    local err
    for i = 2, #r do
        local _, e = M.replay(G, table.move(r, 1, i-1, 1, {}), r[i], true)
        err = err or e
    end
    return G, err
end

--[[
-- The tips of a state's applied actions, below a tip set: a voided
-- tip gives way to its nearest applied ancestors.
-- Inputs:
--  - G [table]: the folded state of `T`
--  - T [table]: array of 40-hex commit hashes (the folded set)
-- Outputs:
--  - [table]: sorted array of independent cids (T itself when no
--    tip was voided)
--  - [boolean]: some tip was voided
-- Errors:
--  - via exec: "bug found" if merge-base fails
-- Callers:
--  - recv (sync.lua): never build on a voided action
--]]
function M.live (G, T)
    STATE.fetch(G, T)
    local out, seen, voided = {}, {}, false
    local stack = table.move(T, 1, #T, 1, {})
    while #stack > 0 do
        local c = table.remove(stack)
        if not seen[c] then
            seen[c] = true
            if (not ACTION.is(c)) or G.actions[c] then
                out[#out+1] = c
            else
                voided = true
                local bs = ACTION.backs(GIT.parents(c))
                STATE.fetch(G, bs)
                for _, b in ipairs(bs) do
                    stack[#stack+1] = b
                end
            end
        end
    end
    if not voided then
        return T, false
    end
    return M.tips(out), true
end

--[[
-- Replay: climb from the floors up to `tip` in consensus order.
-- Calls `ACTION.apply` once per commit.
-- Inputs:
--  - G      [table]: state holding `floors`; MUTATED up to `tip`
--  - floors [table]: array of floor cids (already in G)
--  - tip    [string]: target cid
--  - trunc  [boolean?]: the side is a LOSER, so first failure voids the rest
--  - beg    [boolean?]: beg admission for the side (beg merge)
-- Outputs:
--  - [string?]: last commit applied
--  - [string?]: the voiding error (trunc only)
-- Errors:
--  - re-raises ACTION.apply rejections (trunc = false)
-- Callers:
--  - fold (consensus.lua): a merge's loser sides
--  - state (consensus.lua): a beg merge's beg side
--]]
-- visited: never re-processes a commit (`ACTION.apply` itself skips
-- an action already in `G`, so shared history never re-applies)
-- inside (floors..tip): stops climb from descending below its floor
-- without these the inner meet underflows to a root
function M.replay (G, floors, tip, trunc, beg)
    local visited = {}
    local last          -- last commit applied

    -- the floor test: a commit the climb reaches (reachable from
    -- `tip`) is at/below the floors iff it is outside floors..tip
    local inside = range(floors, tip).set
    local climb, meet

    --[[
    -- Depth-first ascent floors -> cur: parents first, then apply
    -- `cur` itself; a merge recurses through `meet`.
    -- Inputs:
    --  - cur [string]: the commit to reach
    --  - beg [boolean]: beg admission for this branch
    -- Outputs:
    --  - none (sets upvalues `visited` and `last`)
    -- Errors:
    --  - re-raises ACTION.apply rejections
    -- Callers:
    --  - replay/meet (consensus.lua): mutual recursion
    --]]
    climb = function (cur, beg)
        if visited[cur] or (not inside[cur]) then
            return
        else
            local ps = GIT.parents(cur)
            if #ps == 1 then
                climb(ps[1], beg)
            elseif #ps >= 2 then
                -- only a `like` action merges (beg promotion): its
                -- second parent is the beg branch.
                -- a sync merge (or a malformed remote) reads nil:
                -- not a beg merge; `ACTION.apply` rejects malformed
                local t = ACTION.read(false, cur)
                meet(ps, t and t.action=='like' and (#ps == 2))
            end
            visited[cur] = true
            ACTION.apply(G, cur, beg)
            last = cur      -- not reached if `commit` raises
        end
    end

    --[[
    -- Resolve one inner merge: rank its parents BEFORE climbing,
    -- then climb them in that order (consensus decides). Shared
    -- history lands in the winner side's own order, never
    -- pre-applied. A beg merge keeps the writer's order: main, then
    -- the beg.
    -- Inputs:
    --  - ps     [table]: the merge's parents
    --  - is_beg [boolean]: the 2nd parent is a beg promotion
    -- Outputs:
    --  - none
    -- Errors:
    --  - re-raises climb errors
    -- Callers:
    --  - climb (consensus.lua): on every merge
    --]]
    meet = function (ps, is_beg)
        if is_beg then
            climb(ps[1], false)
            climb(ps[2], true)
        else
            for _, p in ipairs(M.rank(ps)) do
                climb(p, false)
            end
        end
    end

    local ok, e = pcall(climb, tip, beg or false)
    if ok then
        return last
    elseif trunc then
        return last, e      -- loser: the rest is voided
    else
        error(e, 0)
    end
end

return M
