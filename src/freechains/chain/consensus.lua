local M = {}

--[[
-- Boundary octopus: common ancestor of every point where region between `a`
-- and `b` attaches to shared history.
-- Inputs:
--  - a [string]: 40-hex commit hash (one tip)
--  - b [string]: 40-hex commit hash (the other tip)
-- Outputs:
--  - [string]: the octopus merge-base cid
-- Errors:
--  - via exec: "bug found" if rev-list/merge-base fail
-- Callers:
--  - recv (sync.lua): where the remote replay starts
--  - meet (consensus.lua): floor of each inner fork
--]]
-- Sits BELOW every fork inside that region, so a replay starting
-- here re-derives all of it, including merges nested deeper than
-- the outer one.
-- With a single fork it degenerates to the pairwise merge-base.
function M.octopus (a, b)
    local out = exec {
        cmd = "git -C " .. REPO .. " rev-list --boundary " .. a .. "..." .. b
    }
    local boundary = {}
    for line in out:gmatch("[^\n]+") do
        local h = line:match("^%-(%x+)")
        if h then
            boundary[#boundary+1] = h
        end
    end
    return exec {
        cmd = "git -C " .. REPO .. " merge-base --octopus " .. table.concat(boundary, " ")
    }
end

--[[
-- Consensus: prefix reps from `G` decide the fork winner.
-- Traverse com..tip per side, collect signed keys, sum their G reps.
-- Higher sum wins, smaller cid breaks ties.
-- Inputs:
--  - G [table]: state at the fork floor (region prefix) with reps that vote
--  - a [string]: 40-hex commit hash (one tip)
--  - b [string]: 40-hex commit hash (the other tip)
-- Outputs:
--  - [string, string]: winner, loser (FF: ancestor loses)
-- Errors:
--  - via exec: "bug found" if git traversal fails
-- Callers:
--  - recv (sync.lua): pick fst/snd between local and remote
--  - meet (consensus.lua): order each inner fork's replay
--]]
-- Two ancestors, two different questions:
--   oct:  how much history must I RE-DERIVE
--         deep: below every fork in the region
--   base: what did each side CONTRIBUTE
--         shallow: disjoint, no shared commits
--
-- `com` is the pairwise merge-base, computed HERE so no caller can
-- pass the octopus `oct` instead: from a deeper point the two
-- ranges overlap, and since reps are summed over the SET of
-- authors, a commit both sides already hold hands its author's
-- full reps to whichever side lacked them -- letting undisputed
-- history decide a disputed merge.
function M.winner (G, a, b)
    local com = (exec {
        cmd = "git -C " .. REPO .. " merge-base " .. a .. " " .. b
    }):match("%x+")

    -- FF must be chosen
    if com == a then
        return b, a
    elseif com == b then
        return a, b
    end

    --[[
    -- The authors that signed `tip`'s side of the fork.
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
        local keys = {}
        local out = exec {
            cmd = "git -C " .. REPO .. " log --reverse --format=%H " .. com .. ".." .. tip
        }
        for cid in out:gmatch("%x+") do
            local key = SSH.pub.commit(REPO, cid)
            if key then
                keys[key] = true
            end
        end
        return keys
    end
    --[[
    -- Sum the G reps of a key set.
    -- Inputs:
    --  - keys [table]: set of pubkeys (key -> true)
    -- Outputs:
    --  - [integer]: sum of G.authors[key].reps (unknown = 0)
    -- Errors:
    --  - none
    -- Callers:
    --  - consensus (consensus.lua): the two sides' scores
    --]]
    local function reps (keys)
        local n = 0
        for key in pairs(keys) do
            local T = G.authors[key]
            if T then
                n = n + T.reps
            end
        end
        return n
    end
    local sa, sb = reps(collect_keys(a)), reps(collect_keys(b))
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
-- Outputs:
--  - [string?]: last commit applied
--  - [string?]: the voiding error (trunc only)
-- Errors:
--  - re-raises ACTION.apply rejections (trunc = false); a
--    malformed loser is caught earlier, on its own validation
-- Callers:
--  - recv (sync.lua): remote validation, then loser replay
--]]
-- visited: never re-processes a commit (`ACTION.apply` itself skips
-- an action already in `G`, so shared history never re-applies)
-- ancestor(cur,com): stops climb from descending below its floor
-- without these the inner meet underflows to a root
function M.replay (G, com, tip, trunc)
    local visited = {}
    local last          -- last commit applied

    --[[
    -- Is `a` an ancestor of `b`?
    -- Inputs:
    --  - a [string]: 40-hex commit hash
    --  - b [string]: 40-hex commit hash
    -- Outputs:
    --  - [string|false]: truthy iff ancestor (exec result)
    -- Errors:
    --  - none
    -- Callers:
    --  - climb (consensus.lua): stop at/below the floor
    --]]
    local function ancestor (a, b)
        return exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. a .. " " .. b
        }
    end
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
        if cur==com or visited[cur] or ancestor(cur,com) then
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
                -- second parent is the beg branch
                -- like positivity (n>0) is enforced in commit()
                local t = ACTION.is(cur) and ACTION.read(true, cur)
                local is_beg_merge = (t and t.action=='like')
                meet(G, com, p1, p2, is_beg_merge)
            end
            visited[cur] = true
            ACTION.apply(G, cur, beg)
            last = cur      -- not reached if `commit` raises
        end
    end

    --[[
    -- Resolve one fork: find its floor (octopus), climb there,
    -- then climb winner side first (consensus decides).
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
        local up = M.octopus(left, right)
        climb(G, com, up, false)
        local w = M.winner(G, left, right)
        if w == left then
            climb(G, up, left,  false)
            climb(G, up, right, right_is_beg)
        else
            climb(G, up, right, right_is_beg)
            climb(G, up, left,  false)
        end
    end

    local ok, e = pcall(climb, G, com, tip, false)
    if ok then
        return last
    elseif trunc then
        return last, e      -- loser: the rest is voided
    else
        error(e, 0)
    end
end

return M
