#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/reorder-ancient/A/"
local ROOT_B = ROOT .. "/reorder-ancient/B/"

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

-- Reorder replay must not reject ancient loser commits.
-- GEN_2: KEY1=15, KEY2=15; KEY2 likes seed → KEY1 > KEY2.
-- A wins by prefix reps (consensus, NOT hard fork: gamma < 7 days after
-- fork) and its tip (gamma) is >1h ahead of B's ancient beta.
-- The reorder replay grafts beta onto A's advanced clock; the "too old"
-- monotonic guard (common.lua) must NOT fire, since beta was already
-- validated on first receipt (sync.lua climb pass).
do
    print("==> Test: ancient loser commit survives reorder replay")

    -- A: G
    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#anc' init file " .. GEN_2,
    }

    -- A: G -- S[K1]
    TEST "A seeds seed.txt with KEY1"
    local seed = exec {
        cmd = EXE_A .. " --now=1100 chain '#anc' post inline 'seed\n' --file seed.txt --sign " .. KEY1,
    }

    -- A: G -- S[K1] -- L[K2]
    -- K2 pays 1, 10% burned, half credited to K1 → K1 > K2
    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    exec {
        cmd = EXE_A .. " --now=1200 chain '#anc' like 1 post " .. seed .. " --sign " .. KEY2,
    }

    -- A: G -- S[K1] -- L[K2]
    -- B: G -- S[K1] -- L[K2]      (fork point = L, at t=1200)
    TEST "B clones anc"
    exec {
        cmd = EXE_B .. " chains add '#anc' clone " .. ROOT_A .. "/chains/#anc/",
    }

    -- A: G -- S[K1] -- L[K2] -- alpha[K1]
    -- B: G -- S[K1] -- L[K2]
    TEST "A posts alpha with KEY1 (winner side)"
    local alpha = exec {
        cmd = EXE_A .. " --now=2000 chain '#anc' post inline 'alpha\n' --file a.txt --sign " .. KEY1,
    }

    -- A: G -- S[K1] -- L[K2] -- alpha[K1] -- gamma[K1]   (gamma >1h ahead)
    -- B: G -- S[K1] -- L[K2]
    TEST "A posts gamma far ahead (advances A tip.now past +1h)"
    local gamma = exec {
        cmd = EXE_A .. " --now=10000 chain '#anc' post inline 'gamma\n' --file g.txt --sign " .. KEY1,
    }

    -- A: G -- S[K1] -- L[K2] -- alpha[K1] -- gamma[K1]
    -- B: G -- S[K1] -- L[K2] -- beta[K2]        (ancient, own file)
    TEST "B posts ancient beta with KEY2 (loser, own file)"
    local beta = exec {
        cmd = EXE_B .. " --now=2000 chain '#anc' post inline 'beta\n' --file b.txt --sign " .. KEY2,
    }

    --                       alpha[K1] -- gamma[K1] --\
    --                      /                          M
    -- A: G -- S[K1] -- L[K2]                         /
    --                      \                        /
    --                       beta[K2] --------------/   (ancient, reordered)
    --
    -- B: G -- S[K1] -- L[K2] -- beta[K2]
    TEST "B sends to A, non-ff (A wins; reorder replays ancient beta)"
    exec {
        cmd = EXE_B .. " --now=20000 chain '#anc' sync send " .. ROOT_A .. "/chains/#anc/",
    }

    TEST "A's order still contains the ancient loser beta"
    local S = order(EXE_A, "#anc")
    assert(S[seed],  "seed missing from A order")
    assert(S[alpha], "alpha missing from A order")
    assert(S[gamma], "gamma missing from A order")
    assert(S[beta],  "ancient beta dropped by reorder replay (too old)")
end
