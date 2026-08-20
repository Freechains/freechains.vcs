local GIT = require "freechains.chain.git"

-- per-commit state, stored as a git BLOB pinned by a local ref:
--  - `refs/states/<cid>` -> blob(serial(G))
--  - keyed by the derefed cid (callers resolve refs via GIT.deref)
-- git packs the near-identical blobs (delta + zlib) and `gc.auto`
-- keeps the loose->packed cadence. `refs/states/*` are LOCAL: sync
-- never pushes or fetches them, so they carry no wire cost.

local M = {}

local function ref (cid)
    return "refs/states/" .. cid
end

-- G saved with every new snapshot

function M.write (G, cid)
    local tmp = REPO .. "state-tmp"
    local f = io.open(tmp, "w")
    f:write(serial(G))
    f:close()
    local blob = exec {
        cmd = "git -C " .. REPO .. " hash-object -w " .. tmp,
    }
    exec {
        cmd = "git -C " .. REPO .. " update-ref " .. ref(cid) .. " " .. blob,
    }
end

-- whether `cid` has a snapshot

function M.has (cid)
    local _, code = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " show-ref --verify --quiet " .. ref(cid),
    }
    return code == 0
end

-- the state RECORDED at `cid`

function M.read (cid)
    local src = exec { trim=false, err=false,
        cmd = "git -C " .. REPO .. " cat-file blob " .. ref(cid),
    }
    assert(src, "bug found : no snapshot : " .. cid)
    return load(src)()
end

return M
