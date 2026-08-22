local GIT = require "freechains.chain.git"

-- per-commit state, stored as a git BLOB pinned by a local ref:
--  - `refs/states/<cid>` -> blob(serial(G))
--  - keyed by the derefed cid (callers resolve refs via GIT.deref)
-- git packs the near-identical blobs (delta + zlib) and `gc.auto`
-- keeps the loose->packed cadence. `refs/states/*` are LOCAL: sync
-- never pushes or fetches them, so they carry no wire cost.

local M = {}

--[[
-- The state ref name of `cid`.
-- Inputs:
--  - cid [string]: 40-hex commit hash
-- Outputs:
--  - [string]: "refs/states/<cid>"
-- Errors:
--  - none
-- Callers:
--  - write/has/read (state.lua): the one naming point
--]]
local function ref (cid)
    return "refs/states/" .. cid
end

--[[
-- Snapshot `G` at `cid`: serial(G) as a blob pinned by its ref.
-- Inputs:
--  - G   [table]: chain state (authors/actions/order/now)
--  - cid [string]: 40-hex commit hash, derefed
-- Outputs:
--  - none
-- Errors:
--  - via exec: "bug found" if hash-object/update-ref fail
-- Callers:
--  - apply (action.lua): snapshot at every accepted commit
--  - recv (sync.lua): snapshot at the loser sync merge
--]]
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

--[[
-- Whether `cid` has a snapshot.
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed
-- Outputs:
--  - [boolean]: refs/states/<cid> exists
-- Errors:
--  - none
-- Callers:
--  - apply (action.lua): NEVER overwrite the first snapshot
--  - recv (sync.lua): unsnapshotted incoming begs
--]]
function M.has (cid)
    local _, code = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " show-ref --verify --quiet " .. ref(cid),
    }
    return code == 0
end

--[[
-- The state RECORDED at `cid` (trusted local bytes: load()-ed).
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed and snapshotted
-- Outputs:
--  - [table]: the G written at `cid`
-- Errors:
--  - assert "bug found : no snapshot : <cid>" : missing ref
-- Callers:
--  - init (chain/init.lua): G = state at HEAD
--  - like (like.lua): beg-branch state preload
--  - recv (sync.lua): octopus/HEAD/beg-parent states
--]]
function M.read (cid)
    local src = exec { trim=false, err=false,
        cmd = "git -C " .. REPO .. " cat-file blob " .. ref(cid),
    }
    assert(src, "bug found : no snapshot : " .. cid)
    return load(src)()
end

return M
