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

local function order (exe, chain)
    local out = exec {
        cmd = exe .. " chain '" .. chain .. "' list order",
    }
    local S = {}
    for line in out:gmatch("[^\n]+") do
        S[line] = true
    end
    return S
end

-- Nested merges underflow `climb`. An INNER merge M1 forks DEEPER (at
-- genesis, F1) than the OUTER merge M2 (at AW, F2). Climbing M2 from F2
-- re-enters M1 and calls meet with com=F2; M1's own fork F1 is below
-- F2, so climb descends past com to a root -> parents(nil) crash
-- (sync.lua: concatenate a nil value 'tip').
--
--              genesis            (F1: deepest fork)
--             /       \
--        AW[K1]        CW[K2]
--         |   \        /
--         |    M1 = merge(CW, AW)      (M1 forks at genesis = F1)
--         |         |
--     takeover[K1]  |
--          \        /
--           M2 = merge(takeover, M1)  (M2 forks at AW = F2)
--
--   F1 (genesis) < F2 (AW): climbing M2 re-enters M1 below M2's floor.
do
    print("==> Test: nested merges do not underflow climb")

    -- A: G          B: G
    TEST "A creates chain, B clones"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#cu' init file " .. GEN_2,
    }
    exec {
        cmd = EXE_B .. " chains add '#cu' clone " .. ROOT_A .. "/chains/#cu/",
    }

    -- A: G -- AW[K1]      B: G -- CW[K2]     (both fork at genesis = F1)
    TEST "A posts AW, B posts CW (concurrent, fork at genesis)"
    exec {
        cmd = EXE_A .. " --now=1100 chain '#cu' post inline 'AW\n' --file aw.txt --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1100 chain '#cu' post inline 'CW\n' --file cw.txt --sign " .. KEY2,
    }

    -- B: G -- {CW, AW} -- M1        (inner merge, fork = genesis = F1)
    TEST "B recvs A -> inner merge M1 = merge(CW, AW)"
    exec {
        cmd = EXE_B .. " --now=1200 chain '#cu' sync recv " .. ROOT_A .. "/chains/#cu/",
    }

    -- A: G -- AW -- takeover[K1]    (AW = F2, still no M1 on A)
    TEST "A posts takeover (child of AW = F2)"
    local takeover = exec {
        cmd = EXE_A .. " --now=1300 chain '#cu' post inline 'takeover\n' --file to.txt --sign " .. KEY1,
    }

    -- A: ... -- M2 = merge(takeover, M1)   (outer merge, fork = AW = F2)
    TEST "A recvs B -> outer merge M2 (fork = AW), nesting M1"
    exec {
        cmd = EXE_A .. " --now=1400 chain '#cu' sync recv " .. ROOT_B .. "/chains/#cu/",
    }

    -- B has M1 but not takeover; climbing A's M2 re-enters M1 at F1 < F2.
    TEST "B recvs A: must not underflow climb (nested merges)"
    exec {
        cmd = EXE_B .. " --now=1500 chain '#cu' sync recv " .. ROOT_A .. "/chains/#cu/",
    }

    TEST "B's order contains takeover"
    local S = order(EXE_B, "#cu")
    assert(S[takeover], "takeover missing from B order (climb underflow)")
end
