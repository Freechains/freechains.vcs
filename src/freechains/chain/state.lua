local GIT = require "freechains.chain.git"

-- local state snapshots, one per commit:
--  - `.git/states/<cid>.lua`
--  - keyed by derefed cid: callers resolve refs via GIT.deref

local M = {}

-- G saved with every new snapshot

function M.write (G, cid)
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

function M.read (cid)
    local f = assert(
        loadfile(REPO .. ".git/states/" .. cid .. ".lua"),
        "bug found : no snapshot : " .. cid
    )
    return f()
end

-- the peak COMPUTED over a set of commits: the peak each one
-- recorded (its snapshot `now`, the newest time among its
-- ancestors), or its own time if newer (a commit's snapshot holds
-- the PREVIOUS peak, so its own stamp lives nowhere else). The only
-- place the fold happens: `peaks(GIT.parents(h))` is the newest time
-- causally preceding `h`, so writer and verifier share the formula.
-- Asserts on an empty set: only a root has no parents, and no path
-- takes a root this far.

function M.peaks (cids)
    local mx = nil
    for _, h in ipairs(cids) do
        local t = math.max(GIT.time(h), M.read(h).now)
        mx = math.max(mx or t, t)
    end
    return assert(mx)
end

return M
