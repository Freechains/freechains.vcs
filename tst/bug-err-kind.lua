#!/usr/bin/env lua5.4

-- A commit that cannot be classified must be refused with the
-- project's `ERROR : <command> : <detail>` format, never a raw Lua
-- traceback. Classification is structural (B5): an action IS a
-- commit adding its own action file; anything else with one parent
-- is refused ("expected 2-parent merge"), and an action file whose
-- `action` field is unknown is refused ("invalid action kind").

require "tests"

local ROOT_A = ROOT .. "/bug-err-kind/A/"
local ROOT_X = ROOT .. "/bug-err-kind/X/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_X  = ENV .. " ../src/freechains.lua --root " .. ROOT_X

local REPO_A = ROOT_A .. "chains/#ek/"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_X,
}

do
    print("==> Test: unclassifiable commit is refused cleanly")

    -- A: G -- seed[K1] -- like[K2]
    TEST "A creates chain + seeds"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#ek' init file " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1020 chain '#ek' post inline 'seed\n' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_A .. " --now=1040 chain '#ek' like 1000 action " .. seed .. " --sign " .. KEY2,
    }

    TEST "X clones ek"
    exec {
        cmd = EXE_X .. " chains add '#ek' clone " .. REPO_A,
    }

    -- A: ... -- p[K1]        (X must have something to fetch)
    TEST "A posts p"
    exec {
        cmd = EXE_A .. " --now=1100 chain '#ek' post inline 'p\n' --sign " .. KEY1,
    }

    local good = exec {
        cmd = "git -C " .. REPO_A .. " rev-parse HEAD",
    }

    -- A: ... -- p -- FORGED    (no action file at all)
    TEST "A hand-forges a commit that is not an action"
    exec {
        cmd = "echo junk > " .. REPO_A .. "junk.txt",
    }
    exec {
        cmd = "git -C " .. REPO_A .. " add junk.txt",
    }
    exec {
        cmd = "git -C " .. REPO_A .. " commit -q -m 'x' --no-gpg-sign",
    }

    TEST "X recvs A: must name the problem, not leak a traceback"
    FAIL {
        cmd = EXE_X .. " --now=1200 chain '#ek' sync recv " .. REPO_A,
        err = "ERROR : chain sync : malformed commit : expected 2-parent merge",
    }

    TEST "X is untouched (2 entries: seed + like)"
    do
        local out = exec {
            cmd = EXE_X .. " chain '#ek' list order",
        }
        local n = 0
        for _ in out:gmatch("[^\n]+") do n = n + 1 end
        assert(n == 2, "expected 2 entries, got " .. n)
    end

    -- A: ... -- p -- FORGED    (action file with an unknown kind)
    TEST "A hand-forges an action file with an unknown kind"
    exec {
        cmd = "git -C " .. REPO_A .. " reset --hard " .. good,
    }
    local f = io.open(REPO_A .. "bad-kind.lua", "w")
    f:write("return { action='xyz' }\n")
    f:close()
    local aid = exec {
        cmd = "git -C " .. REPO_A .. " hash-object bad-kind.lua",
    }
    exec {
        cmd = "mkdir -p " .. REPO_A .. "actions/" .. aid:sub(1,2),
    }
    exec {
        cmd = "mv " .. REPO_A .. "bad-kind.lua " ..
            REPO_A .. "actions/" .. aid:sub(1,2) .. "/" .. aid .. ".lua",
    }
    exec {
        cmd = "git -C " .. REPO_A .. " add actions/",
    }
    exec {
        cmd = "git -C " .. REPO_A .. " commit -q -m 'x' --no-gpg-sign",
    }

    TEST "X recvs A: invalid kind, named"
    FAIL {
        cmd = EXE_X .. " --now=1200 chain '#ek' sync recv " .. REPO_A,
        err = "ERROR : chain sync : malformed commit : invalid action kind",
    }

    TEST "X is still untouched"
    do
        local out = exec {
            cmd = EXE_X .. " chain '#ek' list order",
        }
        local n = 0
        for _ in out:gmatch("[^\n]+") do n = n + 1 end
        assert(n == 2, "expected 2 entries, got " .. n)
    end
end

print("<== ALL PASSED")
