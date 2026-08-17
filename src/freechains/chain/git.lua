-- immutable commit facts, straight from git, memoized:
--  - a commit's parents and date never change
--  - only hashes are cached, never refs (`HEAD^1` moves)

local M = {}

local MEMO = { parents={}, time={} }

local function memo (t, cid)
    return (cid:match("^%x+$") ~= nil) and t or {}
end

-- the git parents of `cid`: one step back in the DAG, no time
-- involved. Returns an array (empty for a root).
-- NEVER mutate the result

function M.parents (cid)
    local m = memo(MEMO.parents, cid)
    if m[cid] then
        return m[cid]
    end
    local out = exec {
        cmd = "git -C " .. REPO .. " rev-list --parents -1 " .. cid,
        -- $ git rev-list --parents -1 a1b2c3...
        -- a1b2c3... d4e5f6... 7890ab...  # merge: 2 parents
    }
    local ps = {}
    for h in out:gmatch("%x+") do
        ps[#ps+1] = h
    end
    table.remove(ps, 1)
    m[cid] = ps
    return ps
end

-- a commit's OWN author date, which says nothing about its
-- ancestors. Memoized: every child asks again through `peaks`

function M.time (cid)
    local m = memo(MEMO.time, cid)
    if m[cid] then
        return m[cid]
    end
    local t = assert(tonumber((exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%at " .. cid,
    })))
    m[cid] = t
    return t
end

return M
