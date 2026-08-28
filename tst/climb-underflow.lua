#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/climb-underflow/A/"
local ROOT_B = ROOT .. "/climb-underflow/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}

-- Nested merges underflow `climb`. An INNER merge M1 forks DEEPER (at
-- genesis, F1) than the OUTER merge M2 (at AW, F2). Climbing M2 from F2
-- re-enters M1 and calls meet with com=F2; M1's own fork F1 is below
-- F2, so climb descends past com to a root -> parents(nil) crash
-- (sync.lua: concatenate a nil value 'tip').
--
-- GEN_2: KEY1=15, KEY2=15. KEY2 likes seed before the fork so KEY1 > KEY2:
-- consensus is then decided by REPS, not by the hash tiebreak (commit hashes
-- vary run to run, which would make the expected order non-deterministic).
--
--               seed[K1]           (F1: deepest fork)
--              /       \
--        AW[K1]        CW[K2]
--         |   \        /
--         |    M1 = merge(CW, AW)      (M1 forks at seed = F1)
--         |         |
--     takeover[K1]  |
--          \        /
--           M2 = merge(takeover, M1)  (M2 forks at AW = F2)
--
--   F1 (seed) < F2 (AW): climbing M2 re-enters M1 below M2's floor.
do
    print("==> Test: nested merges do not underflow climb")

    -- A: G -- seed[K1]
    TEST "A creates chain + seeds seed.txt"
    exec {
        cmd = EXE_A .. " --now=1000 chains add /cu init " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1020 chain /cu post inline 'seed\n' --sign " .. KEY1,
    }

    -- K2 pays 1, 10% burned, half credited to K1 -> K1 > K2 (no hash tiebreak)
    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    exec {
        cmd = EXE_A .. " --now=1040 chain /cu like 1000 action " .. seed .. " --sign " .. KEY2,
    }

    -- A: G -- seed -- L      B: G -- seed -- L
    TEST "B clones cu (at the like = F1)"
    exec {
        cmd = EXE_B .. " chains add /cu clone " .. ROOT_A .. "/chains/cu/",
    }

    -- A: ... -- AW[K1]      B: ... -- CW[K2]     (both fork at F1)
    TEST "A posts AW (higher reps), B posts CW (concurrent, fork at F1)"
    exec {
        cmd = EXE_A .. " --now=1100 chain /cu post inline 'AW\n' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1100 chain /cu post inline 'CW\n' --sign " .. KEY2,
    }

    -- B: G -- {CW, AW} -- M1        (inner merge, fork = genesis = F1)
    TEST "B recvs A -> inner merge M1 = merge(CW, AW)"
    exec {
        cmd = EXE_B .. " --now=1200 chain /cu sync recv " .. ROOT_A .. "/chains/cu/",
    }

    -- A: G -- AW -- takeover[K1]    (AW = F2, still no M1 on A)
    TEST "A posts takeover (child of AW = F2)"
    local takeover = exec {
        cmd = EXE_A .. " --now=1300 chain /cu post inline 'takeover\n' --sign " .. KEY1,
    }

    -- A: ... -- M2 = merge(takeover, M1)   (outer merge, fork = AW = F2)
    TEST "A recvs B -> outer merge M2 (fork = AW), nesting M1"
    exec {
        cmd = EXE_A .. " --now=1400 chain /cu sync recv " .. ROOT_B .. "/chains/cu/",
    }

    -- B has M1 but not takeover; climbing A's M2 re-enters M1 at F1 < F2.
    TEST "B recvs A: must not underflow climb (nested merges)"
    exec {
        cmd = EXE_B .. " --now=1500 chain /cu sync recv " .. ROOT_A .. "/chains/cu/",
    }

    TEST "B's order contains takeover"
    local _, S = ORDER(EXE_B, "/cu")
    assert(S[takeover], "takeover missing from B order (climb underflow)")
end

print("<== ALL PASSED")
