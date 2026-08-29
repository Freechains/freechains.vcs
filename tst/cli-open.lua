#!/usr/bin/env lua5.4

require "tests"

-- UNRESTRICTED chain: a genesis with no pioneers gates NOBODY.
-- The whole economy still applies, so balances go NEGATIVE:
-- reps become a score, not a permission.

exec {
    cmd = ENV_EXE .. " --now=0 chains add /cli-open init " .. GEN_0,
}

do
    print("==> Unrestricted: the gates are skipped")

    local POST
    do
        TEST "an unknown key may post"
        -- in a pioneered chain this is `insufficient reputation`
        local out, code = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-open post inline 'hello' --sign " .. KEY1,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash: " .. out)
        POST = out
    end

    do
        TEST "the author goes into debt"
        -- the cost applies as always: 0 - 500
        local r = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-open reps author '" .. PUB1 .. "'",
        }
        assert(r == "-500", "reps: " .. r)
    end

    do
        TEST "the debt refunds at 12h"
        -- nobody else posted, so the discount runs the full 12h
        local r = exec {
            cmd = ENV_EXE .. " --now=43200 chain /cli-open reps author '" .. PUB1 .. "'",
        }
        assert(r == "0", "reps: " .. r)
    end

    do
        TEST "a vote from zero reps is allowed"
        local _, code = exec {
            cmd = ENV_EXE .. " --now=43200 chain /cli-open like 1000 action " ..
                POST .. " --sign " .. KEY2,
        }
        assert(code == 0, "exit code: " .. tostring(code))

        TEST "the voter goes into debt, the target is paid"
        -- KEY2: 0 - 1000 ; KEY1: 0 (refunded) + 1000*90%/2
        local k2 = exec {
            cmd = ENV_EXE .. " --now=43200 chain /cli-open reps author '" .. PUB2 .. "'",
        }
        assert(k2 == "-1000", "voter reps: " .. k2)
        local k1 = exec {
            cmd = ENV_EXE .. " --now=43200 chain /cli-open reps author '" .. PUB1 .. "'",
        }
        assert(k1 == "450", "target reps: " .. k1)
    end

    do
        TEST "a vote from DEBT is allowed too"
        local _, code = exec {
            cmd = ENV_EXE .. " --now=43200 chain /cli-open like 1000 author '" ..
                PUB1 .. "' --sign " .. KEY2,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local k2 = exec {
            cmd = ENV_EXE .. " --now=43200 chain /cli-open reps author '" .. PUB2 .. "'",
        }
        assert(k2 == "-2000", "voter reps: " .. k2)
    end
end

do
    print("==> Restricted: a pioneered chain still gates")

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-gated init " .. GEN_1,
    }

    TEST "an unknown key is still refused"
    FAIL {
        cmd = ENV_EXE .. " --now=0 chain /cli-gated post inline 'x' --sign " .. KEY2,
        err = "ERROR : chain post : insufficient reputation",
    }
end

print("<== ALL PASSED")
