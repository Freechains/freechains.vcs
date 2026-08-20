#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/fork-100-posts/A/"
local ROOT_B = ROOT .. "/fork-100-posts/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local HOUR = 60 * 60
local WEEK = 7 * 24 * HOUR
local FORK = 1000
local N    = 100
local STEP = 5400               -- 1.5h between posts (see below)

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}

-- 1. local first by 100-post divergence (rule 1 overrides prefix reps)
-- GEN_3: KEY1=10, KEY2=10, KEY3=10
-- A: KEY3 alone posts 100 times → prefix reps 10
-- B: KEY1 and KEY2 post once each → prefix reps 20
-- Reps cap at 30, so the poster cannot stockpile 100 reps: it cycles
-- them instead. A broke poster holds a negligible rep share, so its
-- discount is the full 12h → sustainable rate is 10 posts per 12h,
-- i.e. one post per 1.2h. STEP is 1.5h to stay under that.
-- 100 posts at 1.5h steps = 150h < 7 days, so the time axis stays
-- below its threshold and only the post axis can fire.
-- Without rule 1: B ordered first by prefix reps (20 > 10)
-- With rule 1: A is entrenched (100 posts reached) and REFUSES the
-- merge, so it never reconciles with B and keeps its branch as is
do
    print("==> Test 1: local first by 100-post divergence")

    -- A: G
    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " --now=" .. FORK .. " chains add '#fork-100' init " .. GEN_3,
    }

    -- A: G
    -- B: G                        (fork point = G, at t=FORK)
    TEST "B clones fork-100"
    exec {
        cmd = EXE_B .. " chains add '#fork-100' clone " .. ROOT_A .. "/chains/#fork-100/",
    }

    -- A: G -- P1[K3] -- ... -- P100[K3]    (1.5h steps, tip at FORK+150h)
    -- B: G
    TEST "A posts 100 times with KEY3 (lowest prefix reps), 1.5h apart"
    local A = {}
    for i = 1, N do
        A[i] = exec {
            cmd = EXE_A .. " --now=" .. (FORK+i*STEP) .. " chain '#fork-100' post inline 'p" .. i .. "\n' --sign " .. KEY3,
        }
    end

    -- A: G -- P1[K3] -- ... -- P100[K3]
    -- B: G -- Q1[K1] -- Q2[K2]
    TEST "B posts twice with KEY1+KEY2 (higher prefix reps)"
    local Q1 = exec {
        cmd = EXE_B .. " --now=" .. (FORK+N*STEP) .. " chain '#fork-100' post inline 'q1\n' --sign " .. KEY1,
    }
    local Q2 = exec {
        cmd = EXE_B .. " --now=" .. (FORK+N*STEP) .. " chain '#fork-100' post inline 'q2\n' --sign " .. KEY2,
    }

    --      P1[K3] -- ... -- P100[K3] --\
    --     /                             M
    -- A: G                             /
    --     \                           /
    --      Q1[K1] -- Q2[K2] ---------/
    --
    -- B: G -- Q1[K1] -- Q2[K2]
    -- rule 1 REFUSES the merge: A is entrenched, so it does not reconcile
    -- with B at all (rather than merging and ordering itself first)
    TEST "A recvs from B: refused by rule 1"
    FAIL {
        cmd = EXE_A .. " --now=" .. (FORK+N*STEP+HOUR) .. " chain '#fork-100' sync recv " .. ROOT_B .. "/chains/#fork-100/",
        err = "ERROR : chain sync : hard fork",
    }

    TEST "A keeps its own branch untouched (no remote posts)"
    do
        local O, S = ORDER(EXE_A, "#fork-100")
        assert(#O == N, "expected " .. N .. " entries, got " .. #O)
        for i = 1, N do
            assert(O[i] == A[i], "local post " .. i .. " out of order")
        end
        assert(not S[Q1], "Q1 must not have been merged")
        assert(not S[Q2], "Q2 must not have been merged")
    end

    TEST "time axis stayed below the 7-day threshold"
    assert(N*STEP < WEEK, "setup bug: local branch also crossed 7 days")
end

print("<== ALL PASSED")
