#!/usr/bin/env lua5.4

-- A commit BOTH peers already agree on must never decide the consensus
-- between them: an entrenched peer would otherwise ACCEPT a merge that
-- reorders its settled history.
--
-- `consensus(G, com, a, b)` must take `com` from the PAIRWISE merge-base,
-- so `com..a` and `com..b` are disjoint. Comparing from the boundary
-- octopus `oct` instead -- which sits deeper whenever an unrelated EARLIER
-- fork exists -- puts commits both branches hold inside BOTH ranges, and
-- since reps are summed over the SET of members, such a shared commit
-- hands its member's full reps to whichever side lacked them.
--
-- `AW` (by KEY1) is that commit here: X absorbed it. Counted from `oct`,
-- KEY1's reps land on X's side too, X wins, KEY1's late post is ordered
-- LAST, X's settled prefix survives untouched -- and X wrongly ACCEPTS.
-- Counted from the true fork, KEY1 wins, its post belongs BEFORE X's
-- settled posts, and X refuses (`ERROR : chain sync : hard fork`).
--
-- GEN_2: KEY1=15, KEY2=15. KEY2 likes seed so KEY1 > KEY2 (no hash
-- tiebreak). Two peers, two keys, four posts.
--
--                     seed[K1]
--                        |
--                     like[K2]          <- oct lands HERE (one fork deeper)
--                    /        \
--               AW[K1]         cw[K2]      concurrent: the unrelated fork
--                   \         /
--                    \       /
--                     MERGE               X absorbs AW
--                        |
--                      d2[K2]             7 days later: X is entrenched
--                        |
--     ALICE[K1]       (X tip)
--        |
--    (A tip)
--
-- from `oct` (wrong):  X: AW[K1] cw[K2] d2[K2] -> {K1,K2}  <- AW counted
--                      A: AW[K1] ALICE[K1]     -> {K1}     <- on both
--
-- from AW (correct):   X: cw[K2] d2[K2]        -> {K2}
--                      A: ALICE[K1]            -> {K1} wins -> X refuses

require "tests"

local ROOT_A = ROOT .. "/hardfork-shared/A/"
local ROOT_X = ROOT .. "/hardfork-shared/X/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_X  = ENV .. " ../src/freechains.lua --root " .. ROOT_X

local WEEK = 7 * 24 * 60 * 60

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_X,
}

do
    print("==> Test: shared commit must not decide consensus")

    -- A: G -- seed[K1]
    TEST "A creates chain + seeds seed.txt"
    exec {
        cmd = EXE_A .. " --now=1000 chains add /hs init " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1100 chain /hs post inline 'seed\n' --sign " .. KEY1,
    }

    -- K2 pays 1, 10% burned, half credited to K1 -> K1 > K2
    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2)"
    exec {
        cmd = EXE_A .. " --now=1200 chain /hs like 1000 action " .. seed .. " --sign " .. KEY2,
    }

    TEST "X clones hs"
    exec {
        cmd = EXE_X .. " chains add /hs clone " .. ROOT_A .. "/chains/hs/",
    }

    -- the unrelated earlier fork: it is what drags `oct` below AW
    TEST "A posts AW, X posts cw at the same time (unrelated fork)"
    local aw = exec {
        cmd = EXE_A .. " --now=2000 chain /hs post inline 'AW\n' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_X .. " --now=2000 chain /hs post inline 'cw\n' --sign " .. KEY2,
    }

    -- X now holds AW too: it is shared, and nobody disputes it
    TEST "X recvs A: absorbs AW"
    exec {
        cmd = EXE_X .. " --now=2100 chain /hs sync recv " .. ROOT_A .. "/chains/hs/",
    }

    -- X's own order spans 7 days -> everything before d2 is settled
    TEST "X posts d2 seven days later: X is entrenched"
    exec {
        cmd = EXE_X .. " --now=" .. (2000+WEEK) .. " chain /hs post inline 'd2\n' --sign " .. KEY2,
    }

    -- A never saw cw/d2; it posts on its own branch
    TEST "A posts ALICE on its own branch"
    local alice = exec {
        cmd = EXE_A .. " --now=" .. (2000+WEEK+100) .. " chain /hs post inline 'ALICE\n' --sign " .. KEY1,
    }

    -- KEY1 outranks KEY2 across the true fork, so ALICE belongs BEFORE
    -- X's settled posts -- which X must refuse.
    TEST "X recvs A: must refuse (KEY1 outranks KEY2 across the true fork)"
    FAIL {
        cmd = EXE_X .. " --now=" .. (2000+WEEK+200) .. " chain /hs sync recv " .. ROOT_A .. "/chains/hs/",
        err = "ERROR : chain sync : hard fork",
    }

    TEST "X's settled history is untouched"
    do
        local O, S = ORDER(EXE_X, "/hs")
        assert(#O == 5, "expected 5 entries, got " .. #O)
        assert(not S[alice], "ALICE must not have been merged")
        assert(S[aw], "AW must still be there")
    end
end

print("<== ALL PASSED")
