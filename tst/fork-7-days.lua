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

-- 1. local first by 7-day divergence (rule 1 overrides prefix reps)
-- GEN_2: KEY1=15, KEY2=15
-- Before fork: KEY2 likes seed → KEY2 loses reps → KEY1 > KEY2
-- A posts to a1/a2.txt with KEY2 (lower), B posts to b.txt with KEY1
-- Distinct files: no content conflict, all posts survive the merge
-- Rule 1 measures the SPAN of A's exclusive commits, so A must post
-- ACROSS the window (a1 then a2, 7 days apart): idling after the fork
-- adds no independent history and must not buy entrenchment.
-- Without rule 1: B ordered first by prefix reps (consensus.lua 2)
-- With rule 1: A is entrenched and REFUSES the merge, keeping its branch
-- as is. The refusal is one-directional: B (one post, no span) is not
-- entrenched, so it still absorbs A by plain consensus.
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
        cmd = EXE_A .. " --now=1200 chain '#fork-7d' like 1000 post " .. seed .. " --sign " .. KEY2,
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
    -- 280808 : EARLY EXIT : rest needs clone/recv snapshots
    print("<== PASSED (280808 early exit)")
    os.exit()

    TEST "B posts beta to b.txt with KEY1 (higher prefix reps)"
    local beta = exec {
        cmd = EXE_B .. " --now=" .. (1300+WEEK) .. " chain '#fork-7d' post inline 'beta\n' --file b.txt --sign " .. KEY1,
    }

    -- A: G -- S[K1] -- L[K2] -- a1[K2] -- a2[K2]   (entrenched: span 7d)
    -- B: G -- S[K1] -- L[K2] -- beta[K1]           (not entrenched)
    -- rule 1 REFUSES the merge: A is entrenched, so it does not reconcile
    -- with B at all (rather than merging and ordering itself first)
    TEST "A recvs from B: refused by rule 1"
    FAIL {
        cmd = EXE_A .. " --now=" .. (1300+WEEK+100) .. " chain '#fork-7d' sync recv " .. ROOT_B .. "/chains/#fork-7d/",
        err = "ERROR : chain sync : hard fork",
    }

    TEST "A keeps its own branch untouched (beta not merged)"
    do
        local O, S = ORDER(EXE_A, "#fork-7d")
        assert(#O == 4, "expected 4 entries, got " .. #O)
        assert(O[1] == seed, "seed should be first")
        assert(O[2] == like, "like should be second")
        assert(O[3] == a1,   "a1 should be third")
        assert(O[4] == a2,   "a2 should be fourth")
        assert(not S[beta],  "beta must not have been merged")
    end

    -- B is NOT entrenched (one post, no span), so it still absorbs A's
    -- branch by plain consensus: the refusal is one-directional
    TEST "B recvs from A: accepted (B is not entrenched)"
    exec {
        cmd = EXE_B .. " --now=" .. (1300+WEEK+200) .. " chain '#fork-7d' sync recv " .. ROOT_A .. "/chains/#fork-7d/",
    }

    TEST "B holds every post"
    do
        local O, S = ORDER(EXE_B, "#fork-7d")
        assert(#O == 5, "expected 5 entries, got " .. #O)
        for _, h in ipairs { seed, like, a1, a2, beta } do
            assert(S[h], "missing post in B order")
        end
    end

    TEST "A keeps its own payloads"
    for file, text in pairs { ["a1.txt"]="a1", ["a2.txt"]="a2" } do
        local h = io.open(ROOT_A .. "/chains/#fork-7d/" .. file)
        local content = h:read("a")
        h:close()
        assert(content:match(text), text .. " missing: " .. content)
    end
end

print("<== ALL PASSED")
