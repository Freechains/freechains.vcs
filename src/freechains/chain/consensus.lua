local ssh = require "freechains.chain.ssh"

-- Boundary octopus:
-- The common ancestor of every point where the region between `a` and
-- `b` attaches to shared history.
-- Sits BELOW every fork inside that region, so a replay starting here
-- re-derives all of it, including merges nested deeper than the outer
-- one.
-- With a single fork it degenerates to the pairwise merge-base.
function octopus (a, b)
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

-- Consensus: prefix reps from G decide winner
--  - traverse com..tip, collect signed keys
--  - sum G.authors[key].reps for each side
--  - higher sum wins, cid tiebreaker (smaller wins)
--
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
function consensus (G, a, b)
    local com = (exec {
        cmd = "git -C " .. REPO .. " merge-base " .. a .. " " .. b
    }):match("%x+")

    -- FF must be chosen
    if com == a then
        return b, a
    elseif com == b then
        return a, b
    end

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
            local key = ssh.pub.commit(REPO, cid)
            if key then
                keys[key] = true
            end
        end
        return keys
    end
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

-- `merge` is deliberately absent as a kind: a sync merge carries no
-- action file and is pure topology (empty diff)
local KINDS = { post=true, like=true, revoke=true }

function commit (G, cid, beg)
    local ps = GIT.parents(cid)
    local aid = ACTION.aid(cid)
    -- a merge adds no time: dates are neutral, the action file is
    -- the one source of truth
    local time = 0

    -- not an action file: must be an empty merge
    if not aid then
        if #ps == 2 then
            local diff = exec {
                cmd = "git -C " .. REPO ..
                    " diff-tree --cc --no-commit-id -r --name-status " .. cid
            }
            if diff ~= "" then
                error("malformed commit : expected empty merge", 0)
            end
        else
            error("malformed commit : expected 2-parent merge", 0)
        end

    -- action file: check commit
    else
        -- the file's name must be its own hash: the aid binds content
        local h = exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " rev-parse " .. cid .. ":" .. ACTION.path(aid)
        }
        if h ~= aid then
            error("malformed commit : invalid action filename", 0)
        end
        local act = ACTION.read(false, aid)
        if not act then
            error("malformed commit : invalid action file", 0)
        end
        local kind = act.action
        if not KINDS[kind] then
            error("malformed commit : invalid action kind", 0)
        end

        -- the whole diff must be exactly: add the action file
        -- (--cc: one status letter per parent -> AA on a beg merge)
        -- checked even for an already-applied action: a duplicate
        -- must still be a clean add, not a tamper
        local diff = exec {
            cmd = "git -C " .. REPO ..
                " diff-tree --cc --no-commit-id -r --name-status " .. cid
        }
        if diff ~= (("A"):rep(#ps) .. "\t" .. ACTION.path(aid)) then
            error("malformed commit : expected clean add", 0)
        end

        -- stored `backs` must match calculated here
        do
            local backs = ACTION.backs(ps)
            if type(act.backs)~='table' or #act.backs~=#backs then
                error("malformed commit : invalid backs", 0)
            end
            for i, a in ipairs(backs) do
                if act.backs[i] ~= a then
                    error("malformed commit : invalid backs", 0)
                end
            end
        end

        if math.type(act.time) ~= 'integer' then
            error("malformed commit : invalid time", 0)
        end
        time = act.time

        if G.actions[aid] then
            -- the same action arrived in an earlier commit: already
            -- in G; only the snapshot below matters
            goto SNAP
        end

        -- B6: pin the file to the envelope. The file's `sign` must
        -- match the commit's verified signature; `time` needs no
        -- pin, the file itself is the signed source of truth
        local key, err = ssh.verify(REPO, cid)
        if (not key) and err=='forged' then
            error("malformed commit : invalid signature", 0)
        end
        if act.sign ~= key then
            error("malformed commit : invalid signature", 0)
        end

        if kind == 'post' then
            local ok, err = apply(G, 'post', act, {
                time    = time,
                aid     = aid,
                sign    = key,
                parents = ps,
                beg     = beg or (key == nil),
            })
            if not ok then
                error("invalid post : " .. err, 0)
            end
        else
            if not key then
                error("malformed commit : expected signature", 0)
            end
            -- only a positive `like` accepts a beg
            local to_beg = (
                kind == 'like'
                and (math.type(act.n)=='integer' and act.n>0)
                and (act.aid and G.actions[act.aid])
                and (G.actions[act.aid].maturity == "beg")
            ) or false
            local ok, err = apply(G, kind, act, {
                time    = time,
                aid     = aid,
                sign    = key,
                parents = ps,
                beg     = to_beg,
            })
            if not ok then
                error("invalid " .. kind .. " : " .. err, 0)
            end
        end
        G.order[#G.order+1] = aid
    end

    ::SNAP::

    -- snapshot: descendants PEAK on this commit. `now` is
    -- ancestry-accurate: the replay's G.now may already include
    -- sibling branches applied earlier in consensus order.
    -- NEVER overwrite: the first write is the commit's own-lineage
    -- state, and a refused sync must not corrupt local snapshots
    if not STATE.has(cid) then
        local sav = G.now
        G.now = math.max(time, STATE.peaks(ps))
        STATE.write(G, cid)
        G.now = sav
    end
end

-- Replay: climb from `com` up to `tip` in consensus order, calling
-- `commit` once per commit.
-- visited: never re-processes a commit (`commit` itself skips an
-- action already in `G`, so shared history never re-applies)
-- ancestor(cur,com): stops climb from descending below its floor
-- without these the inner meet underflows to a root
-- `trunc`: the branch is a LOSER, so the first failure voids the
-- rest: returns the last good cid and the error, instead of raising.
-- A malformed loser is caught earlier, when its branch is validated
function replay (G, com, tip, trunc)
    local visited = {}
    local last          -- last commit applied
    local function ancestor (a, b)
        return exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. a .. " " .. b
        }
    end
    local climb, meet

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
                local a = ACTION.aid(cur)
                local t = a and ACTION.read(false, a)
                local is_beg_merge = (t~=nil and t.action=='like')
                meet(G, com, p1, p2, is_beg_merge)
            end
            visited[cur] = true
            commit(G, cur, beg)
            last = cur      -- not reached if `commit` raises
        end
    end

    meet = function (G, com, left, right, right_is_beg)
        local up = octopus(left, right)
        climb(G, com, up, false)
        local w = consensus(G, left, right)
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

