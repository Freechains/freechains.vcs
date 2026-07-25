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
-- A posts to a1/a2.txt with KEY2 (lower), B posts to b.txt with KEY1
-- Distinct files: no content conflict, all posts survive the merge
-- Rule 1 measures the SPAN of A's exclusive commits, so A must post
-- ACROSS the window (a1 then a2, 7 days apart): idling after the fork
-- adds no independent history and must not buy entrenchment.
-- Without rule 1: B ordered first by prefix reps (consensus.lua 2)
-- With rule 1: A ordered first unconditionally, reps ignored
-- Finally B recvs A back: replaying a hard-forked merge must reproduce
-- the same order, so rule 1 has to be applied at the merge too, not only
-- at the outermost local-vs-remote check.
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

    -- A: G -- S[K1] -- L[K2] -- a1[K2]      (right after the fork)
    -- B: G -- S[K1] -- L[K2]
    TEST "A posts a1 to a1.txt with KEY2 (lower reps), right after the fork"
    local a1 = exec {
        cmd = EXE_A .. " --now=1300 chain '#fork-7d' post inline 'a1\n' --file a1.txt --sign " .. KEY2,
    }

    -- A: G -- S[K1] -- L[K2] -- a1[K2] -- a2[K2]   (a1..a2 spans 7d → rule 1)
    -- B: G -- S[K1] -- L[K2]
    TEST "A posts a2 7 days later: A's exclusive commits now span 7d"
    local a2 = exec {
        cmd = EXE_A .. " --now=" .. (1300+WEEK) .. " chain '#fork-7d' post inline 'a2\n' --file a2.txt --sign " .. KEY2,
    }

    -- A: G -- S[K1] -- L[K2] -- a1[K2] -- a2[K2]
    -- B: G -- S[K1] -- L[K2] -- beta[K1]           (single post: no span)
    TEST "B posts beta to b.txt with KEY1 (higher prefix reps)"
    local beta = exec {
        cmd = EXE_B .. " --now=" .. (1300+WEEK) .. " chain '#fork-7d' post inline 'beta\n' --file b.txt --sign " .. KEY1,
    }

    --                       a1[K2] -- a2[K2] --\
    --                      /                    M
    -- A: G -- S[K1] -- L[K2]                   /
    --                      \                  /
    --                       beta[K1] --------/  (all survive: distinct files)
    --
    -- B: G -- S[K1] -- L[K2] -- beta[K1]
    TEST "A recvs from B (A first by rule 1, despite lower reps)"
    exec {
        cmd = EXE_A .. " --now=" .. (1300+WEEK+100) .. " chain '#fork-7d' sync recv " .. ROOT_B .. "/chains/#fork-7d/",
    }

    TEST "A order: S, L, a1, a2, beta (local branch first)"
    do
        local O, S = order(EXE_A, "#fork-7d")
        assert(#O == 5, "expected 5 entries, got " .. #O)
        assert(O[1] == seed, "seed should be first")
        assert(O[2] == like, "like should be second")
        assert(O[3] == a1,   "a1 (local) should precede beta")
        assert(O[4] == a2,   "a2 (local) should precede beta")
        assert(O[5] == beta, "beta (remote) should be last")
    end

    -- B now REPLAYS A's merge. B's own rule-1 check never fires here (B is
    -- behind: this is a fast-forward), so the only way B can re-derive the
    -- order A committed is to re-apply rule 1 AT that merge. With plain
    -- reps-consensus B would put beta (higher reps) first and the strict
    -- state check would reject the recv.
    TEST "B recvs from A (replays the hard-forked merge)"
    exec {
        cmd = EXE_B .. " --now=" .. (1300+WEEK+200) .. " chain '#fork-7d' sync recv " .. ROOT_A .. "/chains/#fork-7d/",
    }

    TEST "B re-derives the same order as A"
    do
        local OA = order(EXE_A, "#fork-7d")
        local OB = order(EXE_B, "#fork-7d")
        assert(#OB == #OA, "order length differs: A=" .. #OA .. " B=" .. #OB)
        for i = 1, #OA do
            assert(OB[i] == OA[i], "order differs at " .. i .. ": A=" .. OA[i] .. " B=" .. OB[i])
        end
    end

    TEST "A keeps all payloads"
    for file, text in pairs { ["a1.txt"]="a1", ["a2.txt"]="a2", ["b.txt"]="beta" } do
        local h = io.open(ROOT_A .. "/chains/#fork-7d/" .. file)
        local content = h:read("a")
        h:close()
        assert(content:match(text), text .. " missing: " .. content)
    end
end

print("<== ALL PASSED")
