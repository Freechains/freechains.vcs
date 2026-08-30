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
    print("==> Anonymous: an unsigned post is charged to `anonymous`")

    -- its OWN chain: in `/cli-anon` KEY1 holds every positive
    -- rep, so `ratio` is 1, the discount collapses to zero and
    -- the like below would ALSO refund the post (+500)
    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-anon init " .. GEN_0,
    }

    local ANON
    do
        TEST "an unsigned post lands in the chain"
        -- no --sign and no --beg: only an open chain accepts it
        local out, code = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-anon post inline 'anon post'",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash: " .. out)
        ANON = out

        TEST "it is NOT parked as a beg"
        local begs = exec {
            cmd = ENV_EXE .. " chain /cli-anon list begs",
        }
        assert(begs == "", "begs should be empty: " .. begs)
        local ord = exec { trim=false,
            cmd = ENV_EXE .. " chain /cli-anon list order",
        }
        assert(ord:find(ANON, 1, true), "must be in the order")
    end

    do
        TEST "the shared account paid for it"
        local r = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-anon reps author anonymous",
        }
        assert(r == "-500", "anon reps: " .. r)
    end

    do
        TEST "a like to an anon post credits the account back"
        -- 1000 taxed 10%, split half: -500 + 450
        exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-anon like 1000 action " ..
                ANON .. " --sign " .. KEY1,
        }
        local r = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-anon reps author anonymous",
        }
        assert(r == "-50", "anon reps: " .. r)
    end

    do
        TEST "begging is refused in an open chain"
        -- nothing to be admitted INTO: a post just lands
        FAIL {
            cmd = ENV_EXE .. " --now=0 chain /cli-anon post inline 'x' --beg",
            err = "ERROR : chain post : --beg error : open chain",
        }
    end

    do
        TEST "the commit itself is unsigned"
        local T = META(exec {
            cmd = ENV_EXE .. " chain /cli-anon get metadata " .. ANON,
        })
        assert(T.sign == nil, "sign: " .. tostring(T.sign))
        assert(T.action == "post", "action: " .. tostring(T.action))
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

    TEST "an unsigned post is still refused"
    -- no `anonymous` outside an open chain: admission is the point
    FAIL {
        cmd = ENV_EXE .. " --now=0 chain /cli-gated post inline 'x'",
        err = "ERROR : chain post : requires --sign or --beg",
    }
end

-- The reason `collect_keys` counts an unsigned action as `anonymous`:
-- consensus weighs the FLOOR reps of each side's authors, so an
-- uncounted anon branch would weigh 0 and BEAT a signed author
-- in debt. Two peers, one fork, deterministic outcome.
do
    print("==> Consensus: anon debt weighs on its branch")

    local A = ROOT .. "/cli-open-A/"
    local B = ROOT .. "/cli-open-B/"
    local EXE_A = ENV .. " ../src/freechains.lua --root " .. A
    local EXE_B = ENV .. " ../src/freechains.lua --root " .. B

    -- floor: anon owes 1000 (two posts), KEY1 owes 500 (one post)
    exec { cmd = EXE_A .. " --now=0  chains add /fork init " .. GEN_0 }
    exec { cmd = EXE_A .. " --now=0  chain /fork post inline 'a1'" }
    exec { cmd = EXE_A .. " --now=10 chain /fork post inline 'a2'" }
    exec { cmd = EXE_A .. " --now=20 chain /fork post inline 's1' --sign " .. KEY1 }
    exec { cmd = EXE_B .. " chains add /fork clone " .. A .. "/chains/fork" }

    do
        TEST "the floor: anon deeper in debt than the signer"
        local an = exec {
            cmd = EXE_B .. " --now=20 chain /fork reps author anonymous",
        }
        local k1 = exec {
            cmd = EXE_B .. " --now=20 chain /fork reps author '" .. PUB1 .. "'",
        }
        assert(an == "-1000", "anon at floor: " .. an)
        assert(k1 == "-500", "KEY1 at floor: " .. k1)
    end

    -- each side adds one action, then B resolves the fork
    local PA = exec { cmd = EXE_A .. " --now=100 chain /fork post inline 'anon side'" }
    local PB = exec {
        cmd = EXE_B .. " --now=100 chain /fork post inline 'signed side' --sign " .. KEY1,
    }
    exec { cmd = EXE_B .. " --now=200 chain /fork sync recv " .. A .. "/chains/fork" }

    do
        TEST "the signed side wins: anon carries more debt"
        local O = ORDER(EXE_B, "/fork")
        assert(O[#O-1] == PB, "signed side should win: " .. tostring(O[#O-1]))
        assert(O[#O]   == PA, "anon side should lose: " .. tostring(O[#O]))
    end
end

print("<== ALL PASSED")
