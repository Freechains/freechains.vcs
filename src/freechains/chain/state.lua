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

return M
