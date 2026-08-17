-- immutable commit facts, straight from git, memoized:
--  - a commit's parents and date never change
--  - only derefed cids are accepted (`HEAD^1` moves): deref first

local M = {}

local MEMO = { parents={}, time={} }

-- ref (HEAD) -> derefed cid

function M.deref (rev)
    -- parenthesized: exec returns (out, code)
    return (exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. rev,
    })
end

-- the git parents of `cid`: one step back in the DAG, no time
-- involved. Returns an array (empty for a root).
-- NEVER mutate the result

function M.parents (cid)
    local m = MEMO.parents
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

-- a commit's OWN stamp: its action's signed time, which says
-- nothing about its ancestors. A merge or the genesis carries no
-- action, so it adds no time (0): commit dates are neutral, the
-- action file is the one source of truth.
-- Memoized: every child asks again through `peaks`

function M.time (cid)
    local m = MEMO.time
    if m[cid] then
        return m[cid]
    end
    local aid = ACTION.aid(cid)
    local t = aid and ACTION.read(true, aid).time or 0
    m[cid] = t
    return t
end

return M
