#!/usr/bin/env lua5.4

-- A consensus merge whose WINNER posted more than `time.diff` (1h) after
-- the loser must still be validatable by every other peer.
--
-- GEN_2: KEY1=15, KEY2=15. KEY2 likes seed before the fork so KEY1 > KEY2
-- and consensus is decided by REPS, not by the hash tiebreak.
--
--              seed[K1]
--                 |
--              like[K2]              (K2 pays: KEY1 > KEY2)
--               /    \
--      low[K2] @t     high[K1] @t+2h
--               \    /
--                 M                  A merges: KEY1 wins, so the NEWER
--                                    post is ordered FIRST
--
-- A's order becomes: seed, like, high, low
--
-- C (a third peer that has neither post) then replays A's merge, applying
-- `high` (t+2h) before `low` (t).
--
-- Freshness must therefore be a property of the DAG, not of the order a
-- replay happens to apply commits in: `apply` compares each commit
-- against `peak`, tolerating `time.diff`. Guarding against
-- the running state instead (the old `time < G.now - time.diff`)
-- rejected `low` here, because `high` had already advanced it.
--
-- No hard fork is involved: everything here is minutes/hours old, far
-- below both entrenchment thresholds.

require "tests"

local ROOT_A = ROOT .. "/consensus-gap/A/"
local ROOT_B = ROOT .. "/consensus-gap/B/"
local ROOT_C = ROOT .. "/consensus-gap/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C

local HOUR = 60 * 60

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}
exec {
    cmd = "mkdir -p " .. ROOT_C,
}

do
    print("==> Test: consensus merge across a >1h gap")

    -- A: G -- S[K1]
    TEST "A creates chain + seeds seed.txt"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#cg2' init file " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1100 chain '#cg2' post inline 'seed\n' --file seed.txt --sign " .. KEY1,
    }

    -- K2 pays 1, 10% burned, half credited to K1 -> K1 > K2
    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    local like = exec {
        cmd = EXE_A .. " --now=1200 chain '#cg2' like 1000 action " .. seed .. " --sign " .. KEY2,
    }

    -- A: G -- S -- L      B: G -- S -- L      C: G -- S -- L
    TEST "B and C clone cg2"
    exec {
        cmd = EXE_B .. " chains add '#cg2' clone " .. ROOT_A .. "/chains/#cg2/",
    }
    exec {
        cmd = EXE_C .. " chains add '#cg2' clone " .. ROOT_A .. "/chains/#cg2/",
    }

    -- B: ... L -- low[K2]        (lower reps, EARLIER)
    TEST "B posts low with KEY2"
    local low = exec {
        cmd = EXE_B .. " --now=1300 chain '#cg2' post inline 'low\n' --file lo.txt --sign " .. KEY2,
    }

    -- A: ... L -- high[K1]       (higher reps, 2 HOURS LATER)
    TEST "A posts high with KEY1, 2 hours after low"
    local high = exec {
        cmd = EXE_A .. " --now=" .. (1300+2*HOUR) .. " chain '#cg2' post inline 'high\n' --file hi.txt --sign " .. KEY1,
    }

    -- A: ... L -- {high, low} -- M     KEY1 wins: high is ordered FIRST
    TEST "A recvs B: KEY1 wins, so the newer post is ordered first"
    exec {
        cmd = EXE_A .. " --now=" .. (1300+3*HOUR) .. " chain '#cg2' sync recv " .. ROOT_B .. "/chains/#cg2/",
    }

    TEST "A order: seed, like, high, low"
    do
        local O = ORDER(EXE_A, "#cg2")
        assert(#O == 4, "expected 4 entries, got " .. #O)
        assert(O[3] == high, "high should precede low")
        assert(O[4] == low,  "low should be last")
    end

    TEST "C recvs A: replaying that order must not be rejected"
    exec {
        cmd = EXE_C .. " --now=" .. (1300+4*HOUR) .. " chain '#cg2' sync recv " .. ROOT_A .. "/chains/#cg2/",
    }

    TEST "C holds the same order as A"
    do
        local OA = ORDER(EXE_A, "#cg2")
        local OC = ORDER(EXE_C, "#cg2")
        assert(#OC == #OA, "order length differs: A=" .. #OA .. " C=" .. #OC)
        for i = 1, #OA do
            assert(OC[i] == OA[i], "order differs at " .. i .. ": A=" .. OA[i] .. " C=" .. OC[i])
        end
    end
end

print("<== ALL PASSED")
