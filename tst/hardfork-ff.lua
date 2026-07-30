#!/usr/bin/env lua5.4

-- A FAST-FORWARD must still face rule 1: ff preserves ancestry, NOT
-- order. `order.lua` is a TOTAL order over commits that are CONCURRENT,
-- and consensus interleaves those by reps, so a remote that already
-- absorbed my branch hands me every commit I have -- a clean ff -- while
-- having inserted a foreign post INSIDE my settled prefix.
--
-- Entrenchment is per-peer, and that is what makes this reachable: the
-- middleman `X` clones EARLY, so its own order is seconds long and never
-- entrenched. X therefore merges happily, ordering ALICE first (K1 wins).
-- `B`, entrenched over 7 days, then fast-forwards to X and would adopt a
-- rewritten prefix -- unless `hardfork` is checked on the ff path too.
--
-- GEN_2: KEY1=15, KEY2=15. KEY2 likes seed before the fork so KEY1 > KEY2:
-- consensus is decided by REPS, not by the hash tiebreak (commit hashes
-- vary run to run, which would make the expected order non-deterministic).
--
-- Full DAG (top-down):
--
--                      seed[K1]
--                         |
--                      like[K2]          <- B and X both clone HERE
--                     /        \
--              ALICE[K1]        day 0[K2]      (concurrent)
--                  |                |
--                  |            day 7[K2]      (7 days: B is ENTRENCHED)
--                  |                |
--                  \               /
--                   X recvs both -- merges, K1 > K2 so ALICE is ordered
--                                   at 3, before B's settled posts
--
--   B order : seed  like  day 0  day 7     settled prefix = [seed,like,day 0]
--   X order : seed  like  ALICE  day 0  day 7          differs at j=3
--                          ^ inserted inside B's settled prefix
--
-- B's tip IS an ancestor of X's tip, so `B recv X` is a pure ff: the
-- receiver adds no commit of its own and loses none. Only the ORDER
-- changes, which is exactly what rule 1 protects.

require "tests"

local ROOT_A = ROOT .. "/hardfork-ff/A/"
local ROOT_B = ROOT .. "/hardfork-ff/B/"
local ROOT_X = ROOT .. "/hardfork-ff/X/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_X  = ENV .. " ../src/freechains.lua --root " .. ROOT_X

local WEEK = 7 * 24 * 60 * 60

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}
exec {
    cmd = "mkdir -p " .. ROOT_X,
}

do
    print("==> Test: a fast-forward must not rewrite a settled prefix")

    -- A: G -- seed[K1]
    TEST "A creates chain + seeds seed.txt"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#hff' init file " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1020 chain '#hff' post inline 'seed\n' --file s.txt --sign " .. KEY1,
    }

    -- K2 pays 1, 10% burned, half credited to K1 -> K1 > K2 (no hash tiebreak)
    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    exec {
        cmd = EXE_A .. " --now=1040 chain '#hff' like 1 post " .. seed .. " --sign " .. KEY2,
    }

    -- A / B / X all at the like: X's own order stays 20s long, so X is
    -- never entrenched and will merge whatever it is given
    TEST "B and X clone hff (at the like)"
    exec {
        cmd = EXE_B .. " chains add '#hff' clone " .. ROOT_A .. "/chains/#hff/",
    }
    exec {
        cmd = EXE_X .. " chains add '#hff' clone " .. ROOT_A .. "/chains/#hff/",
    }

    -- A: ... -- ALICE[K1]      B: ... -- day 0[K2]
    TEST "A posts ALICE, B posts day 0 (concurrent)"
    local alice = exec {
        cmd = EXE_A .. " --now=1100 chain '#hff' post inline 'ALICE\n' --file al.txt --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1100 chain '#hff' post inline 'day 0\n' --file d0.txt --sign " .. KEY2,
    }

    -- B: ... -- day 0 -- day 7        (span reaches fork.time: entrenched)
    TEST "B posts day 7 seven days later: B is entrenched"
    exec {
        cmd = EXE_B .. " --now=" .. (1100+WEEK) .. " chain '#hff' post inline 'day 7\n' --file d7.txt --sign " .. KEY2,
    }

    TEST "B's settled order is 4 entries"
    do
        local O = ORDER(EXE_B, "#hff")
        assert(#O == 4, "expected 4 entries, got " .. #O)
    end

    -- X: ... -- ALICE
    TEST "X recvs A (ff: X only adds ALICE)"
    exec {
        cmd = EXE_X .. " --now=1150 chain '#hff' sync recv " .. ROOT_A .. "/chains/#hff/",
    }

    -- X merges both branches. X is NOT entrenched (its order spans 80s),
    -- so rule 1 does not fire on X, and K1 > K2 puts ALICE at 3.
    TEST "X recvs B: merges, ordering ALICE before B's settled posts"
    exec {
        cmd = EXE_X .. " --now=" .. (1100+WEEK+10) .. " chain '#hff' sync recv " .. ROOT_B .. "/chains/#hff/",
    }

    TEST "X's order inserts ALICE at 3"
    do
        local O = ORDER(EXE_X, "#hff")
        assert(#O == 5, "expected 5 entries, got " .. #O)
        assert(O[3] == alice, "ALICE should be ordered at 3")
    end

    -- B's tip is now an ancestor of X's tip: nothing of B's is missing,
    -- so git alone would fast-forward. Rule 1 must still refuse, because
    -- position 3 of B's settled prefix would change from `day 0` to ALICE.
    TEST "B recvs X: pure ff, but must refuse (settled prefix would change)"
    FAIL {
        cmd = EXE_B .. " --now=" .. (1100+WEEK+20) .. " chain '#hff' sync recv " .. ROOT_X .. "/chains/#hff/",
        err = "ERROR : chain sync : hard fork",
    }

    TEST "B's settled history is untouched"
    do
        local O, S = ORDER(EXE_B, "#hff")
        assert(#O == 4, "expected 4 entries, got " .. #O)
        assert(not S[alice], "ALICE must not have been merged")
    end
end

print("<== ALL PASSED")
