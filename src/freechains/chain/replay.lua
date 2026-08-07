-- TODO : review : redesign : full file

-- The consensus replay machinery, shared by sync (recv) and the
-- startup state catch-up (S15.0): octopus/consensus pick the
-- region and its winner, commit() validates and applies ONE
-- commit, region() replays a whole com..tip range.

local ssh = require "freechains.chain.ssh"

local M = {}

-- Boundary octopus:
-- The common ancestor of every point where the region between `a` and
-- `b` attaches to shared history.
-- Sits BELOW every fork inside that region, so a replay starting here
-- re-derives all of it, including merges nested deeper than the outer
-- one.
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
function M.consensus (G, a, b)
    local com = (exec {
        cmd = "git -C " .. REPO .. " merge-base " .. a .. " " .. b
    }):match("%x+")
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

-- TODO : review : commit flow

function M.commit (G, cid, beg)
    local key, err = ssh.verify(REPO, cid)

    local time = tonumber((exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%at " .. cid
    }))

    -- one diff CLASSIFIES and MODE-CHECKS (par.5): the tree
    -- determines everything, no trailer to trust. Closed sets:
    --   A|AA .freechains/actions/<hex>.lua  exactly one (action;
    --        AA: added vs both parents -- beg-merge like)
    --   A    <payload outside .freechains/> posts only
    --                                       (in-tree until S10)
    -- TODO : DONE : S15.2 : M/MM state.lua cases die -- no
    -- state in the tree, so any M is a violation
    -- TODO : change : S10 : payloads leave the tree
    local aid, pays
    do
        local diff = exec {
            cmd = "git -C " .. REPO ..
                " diff-tree --cc --no-commit-id -r --name-status " .. cid
        }
        local acts = 0
        pays = 0
        for status, path in diff:gmatch("(%a+)%s+(%S+)") do
            local bad = true
            if (status=="A" or status=="AA") and
               path:match("^%.freechains/actions/%x+%.lua$") then
                acts = acts + 1
                aid = path:match("actions/(%x+)%.lua")
                bad = false
            elseif status=="A" and not path:match("^%.freechains/") then
                pays = pays + 1
                bad = false
            end
            if bad then
                error (
                    "invalid commit : mode violation : " ..
                        status .. " " .. path
                    , 0
                )
            end
        end
        if acts > 1 then
            error("invalid commit : multiple action files", 0)
        end
    end

    if not aid then
        -- no action file: only a merge is honest (S9.3/S11a);
        -- payloads only ride action commits
        if #parents(cid) < 2 then
            error("invalid commit : expects one action file", 0)
        end
        if pays > 0 then
            error("invalid merge : mode violation : payload", 0)
        end
        -- pure topology: records nothing, and (S15.2) there is
        -- no transmitted state left to verify
        return
    end

    -- action commit: its own file self-describes the kind
    -- TODO : change : S8.4 : action data via db[aid]
    -- data only: no globals to attacker Lua (see READ)
    local t
    do
        local src = exec {
            cmd = "git -C " .. REPO .. " show " .. cid ..
                ":.freechains/actions/" .. aid .. ".lua"
        }
        local f = load(src, nil, "t", {})
        local ok
        if f then
            ok, t = pcall(f)
        end
        if (not f) or (not ok) or type(t)~='table' then
            error("invalid commit : invalid lua metadata", 0)
        end
    end
    local kind = t.action
    if kind~='post' and kind~='like' and kind~='revoke' then
        error("invalid commit : invalid action", 0)
    end

    if (not key) and err=='forged' then
        error("invalid " .. kind .. " : invalid signature", 0)
    end
    if pays > 0 and kind ~= 'post' then
        error("invalid " .. kind .. " : mode violation : payload", 0)
    end

    -- TODO : DONE : S8.4 : the file's self-descriptions are
    -- TRUSTED by replay (par.2) -- so each is validated against
    -- the commit exactly once, here, at receive (par.6):
    do
        -- id integrity: the filename IS the blob's own hash
        local sha = (exec {
            cmd = "git -C " .. REPO .. " ls-tree " .. cid ..
                " -- .freechains/actions/" .. aid .. ".lua",
        }):match("blob (%x+)")
        if sha ~= aid then
            error("invalid " .. kind .. " : id mismatch", 0)
        end
        -- sign: otherwise Alice's file could replay under
        -- another committer's signature
        if t.sign ~= key then
            error("invalid " .. kind .. " : sign mismatch", 0)
        end
        if t.time ~= time then
            error("invalid " .. kind .. " : time mismatch", 0)
        end
    end

    -- duplicate net (par.4): the same action reaching us through
    -- two commits is ONE action -- skip re-apply deliberately
    -- (every applied action has a peak)
    if G.peaks[aid] then
        return
    end

    -- TODO : DONE : S16 : peak folds over T.backs, no
    -- PEAKS(parents) -- backs are GIT-derived here

    -- TODO : redesign : review
    local bs = {}
    for _, h in ipairs(backs(cid)) do
        bs[#bs+1] = assert(DB.aid(h), "bug found")
    end
    table.sort(bs)

    -- S8.4: `backs` is the file's claim of its DAG position --
    -- reject if it disagrees with git's truth (par.6, the
    -- two-DAG check); BACKS writes sorted, so order is exact
    do
        local same = (type(t.backs) == 'table') and (#bs == #t.backs)
        if same then
            for i = 1, #bs do
                if bs[i] ~= t.backs[i] then
                    same = false
                    break
                end
            end
        end
        if not same then
            error("invalid " .. kind .. " : backs mismatch", 0)
        end
    end

    if kind == 'post' then
        local ok, err = apply(G, 'post', time, {
            aid     = aid,
            backs   = bs,
            sign    = key,
            beg     = beg or (key == nil),
        })
        if not ok then
            error("invalid post : " .. err, 0)
        end
    else
        if not key then
            error("invalid " .. kind .. " : missing sign key", 0)
        end
        -- only a positive `like` accepts a beg
        local to_beg = (
            kind == 'like' and t.n > 0
            and t.post and (G.posts[t.post] and G.posts[t.post].maturity=="beg")
        )
        local ok, err = apply(G, kind, time, {
            aid     = aid,
            backs   = bs,
            sign    = key,
            n       = t.n,
            post    = t.post,
            author  = t.author,
            beg     = to_beg,
        })
        if not ok then
            error("invalid " .. kind .. " : " .. err, 0)
        end
    end
    G.order[#G.order+1] = aid
end

-- replay com..tip into G: validates and applies every commit of
-- the region in consensus order. Invalid commits error out --
-- callers pcall. Snapshots written at pure points (S15.1b).
function M.region (G, com, tip)
    -- visited: never re-applies a shared commit
    -- ancestor(cur,com): stops climb from descending below its floor
    -- without these the inner meet underflows to a root
    local visited = {}
    for _, i in ipairs(G.order) do
        visited[assert(DB.cid(i), "bug found")] = true
    end
    local function ancestor (a, b)
        return exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. a .. " " .. b
        }
    end
    local climb, meet

    -- S15.1b: `pure` = everything applied so far is an
    -- ancestor of `cur`, so G IS the state as of `cur`
    -- (writer semantics) and may be snapshotted. False
    -- on loser-side climbs: the winner is already in G.
    climb = function (G, com, cur, beg, pure)
        if cur==com or visited[cur] or ancestor(cur,com) then
            return
        else
            local ps = parents(cur)
            assert(#ps <= 2, "bug: >2 parents")
            local p1, p2 = ps[1], ps[2]
            if p2 == nil then
                climb(G, com, p1, beg, pure)
            else
                -- like positivity (n>0) is enforced in commit()
                -- only a beg-merge like is 2-parent WITH an
                -- action file
                local is_beg_merge = (DB.aid(cur) ~= nil)
                meet(G, com, p1, p2, is_beg_merge, pure)
            end
            visited[cur] = true
            M.commit(G, cur, beg)
            if pure then
                DB.snap(cur, G)
            end
        end
    end

    meet = function (G, com, left, right, right_is_beg, pure)
        local up = M.octopus(left, right)
        climb(G, com, up, false, pure)
        local w = M.consensus(G, left, right)
        if w == left then
            climb(G, up, left,  false, pure)
            climb(G, up, right, right_is_beg, false)
        else
            climb(G, up, right, right_is_beg, pure)
            climb(G, up, left,  false, false)
        end
    end

    climb(G, com, tip, false, true)
end

-- S15.0: state, SELF-HEALING like the index. The snapshot is
-- authoritative; a missing one means the commit was made behind
-- our back (raw git merge; fresh clone; crash between commit and
-- snap) -- rebuild by replaying the uncovered region.
-- TODO : DONE : S15.2 : tree-state seeding gone -- genesis is
-- DERIVED from the chain definition (trusted from nothing), so
-- a fresh clone bootstraps by replaying genesis -> HEAD here
function M.state_at (cid)
    local snap = REPO .. ".git/states/" .. cid .. ".lua"
    local f = io.open(snap)
    if f then
        f:close()
        return dofile(snap)
    end
    local ps = parents(cid)
    if #ps == 0 then
        -- genesis: pioneers from the definition, stamps from the
        -- pinned commit date (equals the writer's CMD.now, S1)
        local gen = READ(exec {
            cmd = "git -C " .. REPO .. " show " .. cid ..
                ":.freechains/genesis.lua",
        })
        local A = {}
        if gen.pioneers then
            local n = C.reps.max // #gen.pioneers
            for _, key in ipairs(gen.pioneers) do
                A[key] = { reps = n }
            end
        end
        local t = assert(tonumber((exec {
            cmd = "git -C " .. REPO .. " log -1 --format=%at " .. cid,
        })))
        local G = {
            authors = A,
            posts   = {},
            order   = {},
            now     = t,
            gen     = t,
            peaks   = {},
        }
        DB.snap(cid, G)
        return G
    end
    -- replay the region between the nearest covered base and cid
    -- (an impure interior commit gets REDERIVED purely from its
    -- own base here, so its snapshot is correct by construction)
    local com = (#ps == 1) and ps[1] or M.octopus(ps[1], ps[2])
    local G = M.state_at(com)
    M.region(G, com, cid)
    return G
end

function M.state ()
    return M.state_at((exec {
        cmd = "git -C " .. REPO .. " rev-parse HEAD",
    }))
end

return M
