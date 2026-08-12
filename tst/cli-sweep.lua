#!/usr/bin/env lua5.4

require "tests"

-- `sweep` reclaims what removal already unreferenced:
--  * a revoked payload (`like` drops its `refs/payloads/` anchor)
--  * an abandoned commit and its payloads
-- A standing post keeps its anchor, so its bytes must survive.

exec {
    cmd = ENV_EXE .. " chains add '#cli-sweep' init file " .. GEN_3,
}

local DIR = ROOT .. "/chains/#cli-sweep/"

-- KEY1 posts two: one to revoke, one to keep
local GONE = exec {
    cmd = ENV_EXE .. " chain '#cli-sweep' post inline 'gone' --sign " .. KEY1,
}
local KEPT = exec {
    cmd = ENV_EXE .. " chain '#cli-sweep' post inline 'kept' --sign " .. KEY1,
}

-- the blobs, named before anything removes them
local B_GONE = exec {
    cmd = "git -C " .. DIR .. " rev-parse refs/payloads/" .. GONE,
}
local B_KEPT = exec {
    cmd = "git -C " .. DIR .. " rev-parse refs/payloads/" .. KEPT,
}

local function has (blob)
    local _, code = exec { err=false, stderr=false,
        cmd = "git -C " .. DIR .. " cat-file -e " .. blob,
    }
    return code == 0
end

do
    print("==> Sweep: revoked bytes go, standing bytes stay")

    do
        TEST "sweep-unreferenced-survives-until-sweep"
        -- KEY2 is not the author: one revoke -> net -1000 -> revoked
        exec {
            cmd = ENV_EXE .. " chain '#cli-sweep' revoke 1000 " .. GONE ..
                " --sign " .. KEY2,
        }
        -- the anchor is gone, but the bytes are still in the db
        local _, code = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR .. " rev-parse refs/payloads/" .. GONE,
        }
        assert(code ~= 0, "anchor should be gone")
        assert(has(B_GONE), "bytes should still be here")
    end

    do
        TEST "sweep-reclaims-revoked"
        exec {
            cmd = ENV_EXE .. " chain '#cli-sweep' sweep",
        }
        assert(not has(B_GONE), "revoked bytes should be gone")
        assert(has(B_KEPT), "standing bytes should stay")
    end

    do
        TEST "sweep-payload-still-readable"
        -- sweep touches no state: the standing post reads as before
        local out = exec {
            cmd = ENV_EXE .. " chain '#cli-sweep' get payload " .. KEPT,
        }
        assert(out == "kept", "payload: " .. out)
    end
end

do
    print("==> Sweep: abandoned bytes go")

    do
        TEST "sweep-reclaims-abandoned"
        exec {
            cmd = ENV_EXE .. " chain '#cli-sweep' abandon " .. KEPT,
        }
        exec {
            cmd = ENV_EXE .. " chain '#cli-sweep' sweep",
        }
        assert(not has(B_KEPT), "abandoned bytes should be gone")
    end
end

print("<== ALL PASSED")
