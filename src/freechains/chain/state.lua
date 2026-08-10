-- local state snapshots, one per state commit:
--  - `.git/states/<hash>.lua`
--  - is_ref = true  : rev is a ref (HEAD)
--  - is_ref = false : rev is a hash

local M = {}

-- G saved with every new state commit

function M.write (G, is_ref, rev)
    local hash = rev
    if is_ref then
        hash = exec {
            cmd = "git -C " .. REPO .. " rev-parse " .. rev,
        }
    end
    -- `.git/states/` is created at repo creation (chains.lua)
    local f = io.open(REPO .. ".git/states/" .. hash .. ".lua", "w")
    f:write(serial(G))
    f:close()
end

-- the state RECORDED at `rev`

function M.read (is_ref, rev)
    local hash = rev
    if is_ref then
        hash = exec {
            cmd = "git -C " .. REPO .. " rev-parse " .. rev,
        }
    end
    local f = assert(
        loadfile(REPO .. ".git/states/" .. hash .. ".lua"),
        "bug found : no snapshot : " .. hash
    )
    return f()
end

return M
