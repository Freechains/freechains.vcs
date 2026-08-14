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

return M
