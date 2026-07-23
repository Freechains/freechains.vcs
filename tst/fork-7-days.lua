#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/fork-7-days/A/"
local ROOT_B = ROOT .. "/fork-7-days/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local WEEK = 7 * 24 * 60 * 60

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
    local T = {}
    local S = {}
    for line in out:gmatch("[^\n]+") do
        T[#T+1] = line
        S[line] = true
    end
    return T, S
end

-- 1. local first by 7-day divergence (rule 1 overrides prefix reps)
-- GEN_2: KEY1=15, KEY2=15
-- Before fork: KEY2 likes seed → KEY2 loses reps → KEY1 > KEY2
-- A posts to a.txt with KEY2 (lower), B posts to b.txt with KEY1
-- Distinct files: no content conflict, both posts survive the merge
-- A's branch diverged >= 7 days from the fork point
-- Without rule 1: B ordered first by prefix reps (consensus.lua 2)
-- With rule 1: A ordered first unconditionally, reps ignored
do
    print("==> Test 1: local first by 7-day divergence")

    -- A: G
    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#fork-7d' init file " .. GEN_2,
    }

    -- A: G -- S[K1]
    TEST "A seeds seed.txt with KEY1"
    local seed = exec {
        cmd = EXE_A .. " --now=1100 chain '#fork-7d' post inline 'seed\n' --file seed.txt --sign " .. KEY1,
    }

    -- A: G -- S[K1] -- L[K2]
    -- K2 pays 1, 10% burned, half credited to K1 → K1 > K2
    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    local like = exec {
        cmd = EXE_A .. " --now=1200 chain '#fork-7d' like 1 post " .. seed .. " --sign " .. KEY2,
    }

    -- A: G -- S[K1] -- L[K2]
    -- B: G -- S[K1] -- L[K2]      (fork point = L, at t=1200)
    TEST "B clones fork-7d"
    exec {
        cmd = EXE_B .. " chains add '#fork-7d' clone " .. ROOT_A .. "/chains/#fork-7d/",
    }

    -- A: G -- S[K1] -- L[K2] -- alpha[K2]   (t = L + 7d → crosses)
    -- B: G -- S[K1] -- L[K2]
    TEST "A posts alpha to a.txt with KEY2 (lower reps), 7 days after fork"
    local alpha = exec {
        cmd = EXE_A .. " --now=" .. (1200+WEEK+100) .. " chain '#fork-7d' post inline 'alpha\n' --file a.txt --sign " .. KEY2,
    }

    -- A: G -- S[K1] -- L[K2] -- alpha[K2]
    -- B: G -- S[K1] -- L[K2] -- beta[K1]
    TEST "B posts beta to b.txt with KEY1 (higher prefix reps)"
    local beta = exec {
        cmd = EXE_B .. " --now=" .. (1200+WEEK+100) .. " chain '#fork-7d' post inline 'beta\n' --file b.txt --sign " .. KEY1,
    }

    --                       alpha[K2] --\
    --                      /             M
    -- A: G -- S[K1] -- L[K2]            /
    --                      \           /
    --                       beta[K1] -/    (both survive: distinct files)
    --
    -- B: G -- S[K1] -- L[K2] -- beta[K1]
    TEST "A recvs from B (A first by rule 1, despite lower reps)"
    exec {
        cmd = EXE_A .. " --now=" .. (1200+WEEK+200) .. " chain '#fork-7d' sync recv " .. ROOT_B .. "/chains/#fork-7d/",
    }

    TEST "A order: S, L, alpha, beta (local branch first)"
    do
        local O, S = order(EXE_A, "#fork-7d")
        assert(#O == 4, "expected 4 entries, got " .. #O)
        assert(O[1] == seed,  "seed should be first")
        assert(O[2] == like,  "like should be second")
        assert(O[3] == alpha, "alpha (local) should precede beta")
        assert(O[4] == beta,  "beta (remote) should be last")
    end

    TEST "A keeps both payloads"
    for file, text in pairs { ["a.txt"]="alpha", ["b.txt"]="beta" } do
        local h = io.open(ROOT_A .. "/chains/#fork-7d/" .. file)
        local content = h:read("a")
        h:close()
        assert(content:match(text), text .. " missing: " .. content)
    end
end

print("<== ALL PASSED")
