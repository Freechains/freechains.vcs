local GIT = require "freechains.chain.git"

-- local state snapshots, one per commit:
--  - `.git/states/<cid>.lua`
--  - is_ref = true  : cid is a ref (HEAD), resolved first
--  - is_ref = false : cid is a commit hash

local M = {}

-- rev -> cid: resolves a ref (HEAD) to its commit hash

local function tocid (is_ref, rev)
    if is_ref then
        return exec {
            cmd = "git -C " .. REPO .. " rev-parse " .. rev,
        }
    end
    return rev
end

-- G saved with every new snapshot

function M.write (G, is_ref, cid)
    cid = tocid(is_ref, cid)
    -- `.git/states/` is created at repo creation (chains.lua)
    local f = io.open(REPO .. ".git/states/" .. cid .. ".lua", "w")
    f:write(serial(G))
    f:close()
end

-- whether `cid` has a snapshot

function M.has (cid)
    local f = io.open(REPO .. ".git/states/" .. cid .. ".lua")
    if f then
        f:close()
        return true
    end
    return false
end

-- the state RECORDED at `cid`

function M.read (is_ref, cid)
    cid = tocid(is_ref, cid)
    local f = assert(
        loadfile(REPO .. ".git/states/" .. cid .. ".lua"),
        "bug found : no snapshot : " .. cid
    )
    return f()
end

-- the peak RECORDED at `cid` (`now`): the newest time among all of
-- its ancestors. Derived, never trusted: `commit` in consensus.lua
-- checks every stored value against its parents' before using it.
-- Accepts refs (HEAD): the snapshot read resolves them.

function M.peak (cid)
    return M.read(true, cid).now
end

-- the peak COMPUTED over a set of commits: the peak each one
-- recorded, or its own time if newer (a commit's snapshot holds the
-- PREVIOUS peak, so its own stamp lives nowhere else). The only
-- place the fold happens: `peaks(GIT.parents(h))` is the newest time
-- causally preceding `h`, so writer and verifier share the formula.
-- Asserts on an empty set: only a root has no parents, and no path
-- takes a root this far.

function M.peaks (cids)
    local mx = nil
    for _, h in ipairs(cids) do
        local t = math.max(GIT.time(h), M.peak(h))
        mx = math.max(mx or t, t)
    end
    return assert(mx)
end

return M
