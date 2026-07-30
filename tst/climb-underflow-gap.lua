#!/usr/bin/env lua5.4

-- Same nested-merge shape as tst/climb-underflow.lua, but the two sides
-- post HOURS apart, so the replay applies commits out of chronological
-- order: the winner's newer post lands before the loser's older one.
--
-- The gap is deliberately kept BELOW entrenchment (hours, not days). With
-- a 7-day gap BOTH peers become settled, and whichever one would have its
-- settled history reordered refuses the merge (rule 1) -- so nothing gets
-- replayed and this test would cover nothing. Rule 1 has its own tests
-- (fork-7-days.lua, fork-100-posts.lua).
--
-- GEN_2: KEY1=15, KEY2=15. KEY2 likes seed before the fork so KEY1 > KEY2:
-- consensus is decided by REPS, not by the hash tiebreak (commit hashes vary
-- run to run, which would make the expected order non-deterministic).
--
-- Full DAG (top-down). F1 = the like (deepest fork), F2 = AW:
--
--                      seed[K1]          (F1: deepest fork)
--                    /       \
--               AW[K1]        CW[K2]      (concurrent, fork at F1)
--                |   \        /
--                |    M1 = merge(AW, CW) (inner merge, forks at F1)
--                |         |
--                |        d1[K2]
--                |         |
--                |        d2[K2]          (3h later: crosses time.diff)
--                |         |
--           takeover[K1]   |
--                 \        /
--                  M2 = merge(takeover, d2)     (outer merge, forks at F2)
--
-- M2's side nests M1 (F1 < F2) and the posts span more than the 1h
-- freshness tolerance. Both merges must go through, and a third peer H
-- must re-derive exactly the same order.

require "tests"

local ROOT_A = ROOT .. "/climb-gap/A/"
local ROOT_B = ROOT .. "/climb-gap/B/"
local ROOT_H = ROOT .. "/climb-gap/H/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_H  = ENV .. " ../src/freechains.lua --root " .. ROOT_H

local HOUR = 60 * 60

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}
exec {
    cmd = "mkdir -p " .. ROOT_H,
}

do
    print("==> Test: nested merge across a time gap")

    -- A: G -- seed[K1]
    TEST "A creates chain + seeds seed.txt"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#cg' init file " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1020 chain '#cg' post inline 'seed\n' --file seed.txt --sign " .. KEY1,
    }

    -- K2 pays 1, 10% burned, half credited to K1 -> K1 > K2 (no hash tiebreak)
    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    exec {
        cmd = EXE_A .. " --now=1040 chain '#cg' like 1 post " .. seed .. " --sign " .. KEY2,
    }

    -- A / B / H all at the like (= F1)
    TEST "B and H clone cg (at the like = F1)"
    exec {
        cmd = EXE_B .. " chains add '#cg' clone " .. ROOT_A .. "/chains/#cg/",
    }
    exec {
        cmd = EXE_H .. " chains add '#cg' clone " .. ROOT_A .. "/chains/#cg/",
    }

    -- A: ... -- AW[K1]      B: ... -- CW[K2]     (both fork at F1)
    TEST "A posts AW (higher reps), B posts CW (fork at F1)"
    exec {
        cmd = EXE_A .. " --now=1100 chain '#cg' post inline 'AW\n' --file aw.txt --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1100 chain '#cg' post inline 'CW\n' --file cw.txt --sign " .. KEY2,
    }

    -- B: G -- {AW, CW} -- M1        (inner merge, forks at genesis = F1)
    TEST "B recvs A -> inner merge M1 = merge(AW, CW)"
    exec {
        cmd = EXE_B .. " --now=1150 chain '#cg' sync recv " .. ROOT_A .. "/chains/#cg/",
    }

    -- B: ... M1 -- d1[K2] -- d2[K2]        (3h apart: crosses time.diff)
    TEST "B posts d1, then d2 three hours later"
    exec {
        cmd = EXE_B .. " --now=1200 chain '#cg' post inline 'd1\n' --file d1.txt --sign " .. KEY2,
    }
    exec {
        cmd = EXE_B .. " --now=" .. (1200+3*HOUR) .. " chain '#cg' post inline 'd2\n' --file d2.txt --sign " .. KEY2,
    }

    -- H: ... M1 -- d1 -- d2      (no takeover)
    TEST "H recvs B"
    exec {
        cmd = EXE_H .. " --now=" .. (1200+3*HOUR+10) .. " chain '#cg' sync recv " .. ROOT_B .. "/chains/#cg/",
    }

    -- A: G -- AW -- takeover[K1]     (AW = F2, A still has no M1)
    TEST "A posts takeover (child of AW = F2)"
    exec {
        cmd = EXE_A .. " --now=" .. (1200+4*HOUR) .. " chain '#cg' post inline 'takeover\n' --file to.txt --sign " .. KEY1,
    }

    -- A: ... -- M2 = merge(takeover, d2)   (outer merge, forks at AW = F2)
    TEST "A recvs B -> outer merge M2 (fork = AW), nesting M1"
    exec {
        cmd = EXE_A .. " --now=" .. (1200+5*HOUR) .. " chain '#cg' sync recv " .. ROOT_B .. "/chains/#cg/",
    }

    -- H holds M1/d1/d2 but not takeover; replaying A's M2 walks the nested
    -- merge AND applies posts out of chronological order.
    TEST "H recvs A (nested merge, posts hours apart)"
    exec {
        cmd = EXE_H .. " --now=" .. (1200+6*HOUR) .. " chain '#cg' sync recv " .. ROOT_A .. "/chains/#cg/",
    }

    TEST "H's order equals A's order"
    local a = ORDER(EXE_A, "#cg")
    local h = ORDER(EXE_H, "#cg")
    assert(#a == #h, "order length differs: A=" .. #a .. " H=" .. #h)
    for i = 1, #a do
        assert(a[i] == h[i], "order differs at " .. i .. ": A=" .. a[i] .. " H=" .. h[i])
    end
end

print("<== ALL PASSED")
