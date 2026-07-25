#!/usr/bin/env lua5.4

-- Same nested-merge shape as tst/climb-underflow.lua, but the community
-- advances across a LARGE time gap (day7 ~7 days after the fork), which
-- makes the SENDER take rule 1 (hard fork) at the outer merge.
--
-- The replay must mirror the sender's decision exactly, or the strict state
-- check rejects the recv:
--
--   ERROR : chain sync : remote state mismatch
--
-- That needs `meet` to (a) use the same ancestor definition as the
-- top-level `oct` (boundary octopus, not the pairwise merge-base) and
-- (b) apply `hardfork` before `consensus`.
--
-- GEN_2: KEY1=15, KEY2=15. KEY2 likes seed before the fork so KEY1 > KEY2:
-- consensus is decided by REPS, not by the hash tiebreak (commit hashes vary
-- run to run, which would make the expected order non-deterministic).
--
-- Full DAG (top-down). F1 = seed/like (deepest fork), F2 = AW:
--
--                      seed[K1]          (F1: deepest fork)
--                    /       \
--               AW[K1]        CW[K2]      (concurrent, fork at F1)
--                |   \        /
--                |    M1 = merge(AW, CW) (inner merge, forks at F1)
--                |         |
--                |      day1[K2]
--                |         |
--                |      day7[K2]          (~7 days later: crosses maturation)
--                |         |
--           takeover[K1]   |
--                 \        /
--                  M2 = merge(takeover, day7)   (outer merge, forks at F2)
--
-- M2's community side nests M1 (F1 < F2), and day7 makes the sender
-- entrench (rule 1). Asserts H's order == A's order after H recvs A.
-- See .claude/plans/260724-climb-underflow.md.

require "tests"

local ROOT_A = ROOT .. "/climb-gap/A/"
local ROOT_B = ROOT .. "/climb-gap/B/"
local ROOT_H = ROOT .. "/climb-gap/H/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_H  = ENV .. " ../src/freechains.lua --root " .. ROOT_H

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}
exec {
    cmd = "mkdir -p " .. ROOT_H,
}

local function order (exe, chain)
    local out = exec {
        cmd = exe .. " chain '" .. chain .. "' list order",
    }
    local T = {}
    for line in out:gmatch("[^\n]+") do
        T[#T+1] = line
    end
    return T
end

do
    print("==> Test: nested merge across a hard-fork time gap")

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

    -- B: ... M1 -- day1[K2] -- day7[K2]      (day7 ~7 days later)
    TEST "B posts day1, then day7 ~7 days later (crosses maturation)"
    exec {
        cmd = EXE_B .. " --now=1200 chain '#cg' post inline 'day1\n' --file d1.txt --sign " .. KEY2,
    }
    exec {
        cmd = EXE_B .. " --now=1780000000 chain '#cg' post inline 'day7\n' --file d7.txt --sign " .. KEY2,
    }

    -- H: ... M1 -- day1 -- day7      (community, no takeover)
    TEST "H recvs the community branch (day7)"
    exec {
        cmd = EXE_H .. " --now=1780000001 chain '#cg' sync recv " .. ROOT_B .. "/chains/#cg/",
    }

    -- A: G -- AW -- takeover[K1]     (AW = F2, A still has no M1)
    TEST "A posts takeover (child of AW = F2)"
    exec {
        cmd = EXE_A .. " --now=1780000002 chain '#cg' post inline 'takeover\n' --file to.txt --sign " .. KEY1,
    }

    -- A: ... -- M2 = merge(takeover, day7)   (outer merge, forks at AW = F2)
    TEST "A recvs community -> outer merge M2 (fork = AW), nesting M1"
    exec {
        cmd = EXE_A .. " --now=1780000003 chain '#cg' sync recv " .. ROOT_B .. "/chains/#cg/",
    }

    -- H holds the community (M1, day1, day7) but not takeover; replaying A's
    -- M2 must reach the same order the sender stored (rule 1 at the outer
    -- merge, reps-consensus at the inner one).
    TEST "H recvs A (nested merge across the gap) -- must not mismatch"
    exec {
        cmd = EXE_H .. " --now=1780000004 chain '#cg' sync recv " .. ROOT_A .. "/chains/#cg/",
    }

    TEST "H's order equals A's order"
    local a = order(EXE_A, "#cg")
    local h = order(EXE_H, "#cg")
    assert(#a == #h, "order length differs: A=" .. #a .. " H=" .. #h)
    for i = 1, #a do
        assert(a[i] == h[i], "order differs at " .. i .. ": A=" .. a[i] .. " H=" .. h[i])
    end
end
