#!/usr/bin/env lua5.4
require "tests"

-- Emission vs revocation (rule 1.b): a consolidated post holds its
-- +1K for the author only while NOT revoked.
--  * revoke before 24h: consolidates with no credit (the slot is
--    consumed anyway); unrevoke grants it then
--  * revoke after 24h: -1K clawback; unrevoke restores
--  * no extra state: the credit follows the revoke sums
--  * a lifting `like` walks the same path as `unrevoke`
--  * self-revoke (free) follows the same accounting
-- Numbers (GEN_2: 25000 each): a 1000 revoke drains the author 450
-- (10% tax, 50/50 split); a 1000 like credits 450.

local function REPS (now, pub)
    return (exec {
        cmd = ENV_EXE .. " --now=" .. now .. " chain /cli-revoke-earn reps member '" .. pub .. "'",
    })
end

-- REVOKE BEFORE 24H
do
    print("==> Revoke before 24h")

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-revoke-earn init " .. GEN_2,
    }
    local P = exec {
        cmd = ENV_EXE .. " --now=0 chain /cli-revoke-earn post inline 'p' --sign " .. KEY1,
    }

    do
        TEST "revoke-earn-before-no-credit"
        exec { -- KEY1 24500 -> 24050 ; KEY2 25000 -> 24000
            cmd = ENV_EXE .. " --now=0 chain /cli-revoke-earn revoke 1000 " .. P .. " --sign " .. KEY2,
        }
        -- refund +500, consolidation without credit
        assert(REPS(86400, PUB1) == "24550", "reps: " .. REPS(86400, PUB1))
    end

    do
        TEST "revoke-earn-before-unrevoke-grants"
        exec { -- crossing out of REVOKED: +1000 ; KEY2 24000 -> 23000
            cmd = ENV_EXE .. " --now=86400 chain /cli-revoke-earn unrevoke 1000 " .. P .. " --sign " .. KEY2,
        }
        assert(REPS(86400, PUB1) == "25550", "reps: " .. REPS(86400, PUB1))
        assert(REPS(86400, PUB2) == "23000", "reps: " .. REPS(86400, PUB2))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-revoke-earn",
    }
end

-- REVOKE AFTER 24H
do
    print("==> Revoke after 24h")

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-revoke-earn init " .. GEN_2,
    }
    local P = exec {
        cmd = ENV_EXE .. " --now=0 chain /cli-revoke-earn post inline 'p' --sign " .. KEY1,
    }
    assert(REPS(86400, PUB1) == "26000", "reps: " .. REPS(86400, PUB1))

    do
        TEST "revoke-earn-after-clawback"
        exec { -- consolidate +1000, dislike -450, clawback -1000
            cmd = ENV_EXE .. " --now=86400 chain /cli-revoke-earn revoke 1000 " .. P .. " --sign " .. KEY2,
        }
        assert(REPS(86400, PUB1) == "24550", "reps: " .. REPS(86400, PUB1))
    end

    do
        TEST "revoke-earn-after-unrevoke-restores"
        exec { -- crossing out of REVOKED: +1000 (1h later, no slot)
            cmd = ENV_EXE .. " --now=90000 chain /cli-revoke-earn unrevoke 1000 " .. P .. " --sign " .. KEY2,
        }
        assert(REPS(90000, PUB1) == "25550", "reps: " .. REPS(90000, PUB1))
        assert(REPS(90000, PUB2) == "23000", "reps: " .. REPS(90000, PUB2))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-revoke-earn",
    }
end

-- LIKE LIFTS
do
    print("==> Like lifts")

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-revoke-earn init " .. GEN_2,
    }
    local P = exec {
        cmd = ENV_EXE .. " --now=0 chain /cli-revoke-earn post inline 'p' --sign " .. KEY1,
    }
    exec {
        cmd = ENV_EXE .. " --now=86400 chain /cli-revoke-earn revoke 1000 " .. P .. " --sign " .. KEY2,
    }
    assert(REPS(86400, PUB1) == "24550", "reps: " .. REPS(86400, PUB1))

    do
        TEST "revoke-earn-like-restores"
        exec { -- like +450, restore +1000
            cmd = ENV_EXE .. " --now=90000 chain /cli-revoke-earn like 1000 action " .. P .. " --sign " .. KEY2,
        }
        assert(REPS(90000, PUB1) == "26000", "reps: " .. REPS(90000, PUB1))
        local out = exec {
            cmd = ENV_EXE .. " --now=90000 chain /cli-revoke-earn get payload " .. P,
        }
        assert(out == "p", "payload: " .. out)
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-revoke-earn",
    }
end

-- SELF-REVOKE
do
    print("==> Self-revoke")

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-revoke-earn init " .. GEN_2,
    }
    local P = exec {
        cmd = ENV_EXE .. " --now=0 chain /cli-revoke-earn post inline 'p' --sign " .. KEY1,
    }

    do
        TEST "revoke-earn-self-clawback"
        exec { -- consolidate +1000, free revoke, clawback -1000
            cmd = ENV_EXE .. " --now=86400 chain /cli-revoke-earn revoke 1000 " .. P .. " --sign " .. KEY1,
        }
        assert(REPS(86400, PUB1) == "25000", "reps: " .. REPS(86400, PUB1))
    end

    do
        TEST "revoke-earn-self-unrevoke-restores"
        exec { -- unrevoke costs 1000, restore +1000
            cmd = ENV_EXE .. " --now=90000 chain /cli-revoke-earn unrevoke 1000 " .. P .. " --sign " .. KEY1,
        }
        assert(REPS(90000, PUB1) == "25000", "reps: " .. REPS(90000, PUB1))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-revoke-earn",
    }
end

-- REPLAY
do
    print("==> Replay")

    local ROOT_A = ROOT .. "/cli-revoke-earn/A/"
    local ROOT_B = ROOT .. "/cli-revoke-earn/B/"
    local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
    local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
    local REPO_A = ROOT_A .. "/chains/x/"

    exec {
        cmd = "mkdir -p " .. ROOT_A .. " " .. ROOT_B,
    }
    exec {
        cmd = EXE_A .. " --now=0 chains add /x init " .. GEN_2,
    }
    local P = exec {
        cmd = EXE_A .. " --now=0 chain /x post inline 'p' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_A .. " --now=86400 chain /x revoke 1000 " .. P .. " --sign " .. KEY2,
    }
    exec {
        cmd = EXE_A .. " --now=90000 chain /x unrevoke 1000 " .. P .. " --sign " .. KEY2,
    }

    do
        TEST "revoke-earn-replay-same-reps"
        exec {
            cmd = EXE_B .. " --now=90000 chains add /x clone " .. REPO_A,
        }
        for _, pub in ipairs { PUB1, PUB2 } do
            local a = exec {
                cmd = EXE_A .. " --now=90000 chain /x reps member '" .. pub .. "'",
            }
            local b = exec {
                cmd = EXE_B .. " --now=90000 chain /x reps member '" .. pub .. "'",
            }
            assert(a == b, "replay: " .. a .. " vs " .. b)
        end
        local out = exec {
            cmd = EXE_B .. " --now=90000 chain /x reps member '" .. PUB1 .. "'",
        }
        assert(out == "25550", "reps: " .. out)
    end
end

print("<== ALL PASSED")
