require "freechains.chain.common"
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
--  - higher sum wins, hash tiebreaker (smaller wins)
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
        for hash in out:gmatch("%x+") do
            local key = ssh.pubkey(REPO, hash)
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

-- `merge` is deliberately absent: those commits are built on a
-- detached head and discarded, so `main` never holds one
local KINDS = { post=true, like=true, revoke=true, state=true }

function commit (G, hash, beg)
    local key, err = ssh.verify(REPO, hash)

    local out = exec {
        cmd = "git -C " .. REPO .. " log -1 --format='%at %(trailers:key=Freechains,valueonly)' " .. hash
    }
    local time,kind = out:match("(%S+)%s+(%S+)")
    if not KINDS[kind] then
        error("invalid commit : invalid kind", 0)
    end

    if (not key) and err=='forged' then
        error("invalid " .. kind .. " : invalid signature", 0)
    end

    -- create-mode check (post/like): only additions allowed
    -- state check: closed path set, A or M only (no D)
    -- --cc handles merges and non-merges uniformly
    local diff = exec {
        cmd = "git -C " .. REPO ..
            " diff-tree --cc --no-commit-id -r --name-status " .. hash
    }
    if kind == 'state' then
        for status, path in diff:gmatch("(%a+)%s+(%S+)") do
            local ok = (
                (path == ".freechains/state/authors.lua") or
                (path == ".freechains/state/posts.lua")   or
                (path == ".freechains/state/order.lua")   or
                (path == ".freechains/state/now.lua")
            )
            if not ok then
                error (
                    "invalid state : " .. path
                    , 0
                )
            end
            if status:match("[^AM]") then
                error (
                    "invalid state : " .. path
                    , 0
                )
            end
        end
    else
        for status, path in diff:gmatch("(%a+)%s+(%S+)") do
            if status:match("[^A]") then
                error (
                    "invalid " .. kind ..
                        " : mode violation : " ..
                        status .. " " .. path
                    , 0
                )
            end
        end
    end

    if kind=='like' or kind=='revoke' then
        if not key then
            error("invalid " .. kind .. " : missing sign key", 0)
        end

        -- vote metadata lives under .freechains/<kind>s/
        local file = exec {
            cmd = "git -C " .. REPO .. " diff-tree --no-commit-id -r --name-only " .. hash .. "^1 " .. hash .. " -- .freechains/" .. kind .. "s/"
        }
        file = file:match("(%S+)")
        if not file then
            error("invalid " .. kind .. " : missing metadata file", 0)
        end
        local src = exec {
            cmd = "git -C " .. REPO .. " show " .. hash .. ":" .. file
        }
        local f = load(src)
        if not f then
            error("invalid " .. kind .. " : invalid lua metadata", 0)
        end
        local ok, t = pcall(f)
        if (not ok) or type(t)~='table' then
            error("invalid " .. kind .. " : invalid lua metadata", 0)
        end
        -- only a positive `like` accepts a beg
        local to_beg = (
            kind == 'like' and t.n > 0
            and t.post and (G.posts[t.post] and G.posts[t.post].maturity=="beg")
        )
        local ok, err = apply(G, kind, tonumber(time), {
            hash   = hash,
            sign   = key,
            n      = t.n,
            post   = t.post,
            author = t.author,
            beg    = to_beg,
        })
        if not ok then
            error("invalid " .. kind .. " : " .. err, 0)
        end
        G.order[#G.order+1] = hash
    elseif kind == 'post' then
        local ok, err = apply(G, 'post', tonumber(time), {
            hash = hash,
            sign = key,
            beg  = beg or (key == nil),
        })
        if not ok then
            error("invalid post : " .. err, 0)
        end
        G.order[#G.order+1] = hash
    else
        assert(kind == 'state')
        -- need to check now, since it is derived, not trusted
        local mx = PEAKS(parents(hash))
        if PEAK(hash) ~= mx then
            error("invalid state : now", 0)
        end
    end
end

-- Replay: climb from `com` up to `tip` in consensus order, calling
-- `commit` once per commit.
-- visited: never re-applies a shared commit (`G.order` seeds it)
-- ancestor(cur,com): stops climb from descending below its floor
-- without these the inner meet underflows to a root
function replay (G, com, tip)
    local visited = {}
    for _, h in ipairs(G.order) do
        visited[h] = true
    end
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
            local ps = parents(cur)
            assert(#ps <= 2, "bug: >2 parents")
            local p1, p2 = ps[1], ps[2]
            if p2 == nil then
                climb(G, com, p1, beg)
            else
                -- like positivity (n>0) is enforced in commit()
                local is_beg_merge = (trailer(cur) == "like")
                meet(G, com, p1, p2, is_beg_merge)
            end
            visited[cur] = true
            commit(G, cur, beg)
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

    climb(G, com, tip, false)
end
