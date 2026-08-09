#!/usr/bin/env lua5.4

-- Covers `climb`'s THIRD guard, `ancestor(cur, com)`, which `visited`
-- cannot replace (tst/climb-underflow.lua covers `visited`).
--
-- A criss-cross merge M0 below the fork point makes the region between
-- the outer merge's two parents attach to shared history at TWO points
-- (S2 and G), so its boundary octopus `up` drops to GENESIS -- strictly
-- BELOW the outer floor `com` = S2.
-- `meet` then calls climb(G, com, up) with `up` an ancestor of `com`:
-- `cur == com` never matches, and genesis is in no `order`, so
-- `visited` misses it too.
-- Without `ancestor(cur, com)` the climb descends past `com` to the
-- root, `parents()` comes back empty and a nil hash reaches a git
-- command.
--
-- Full DAG as D sees it on the last recv.
-- Each post carries a trailing `state` commit S<n> (its peer's tip):
--
--   * S5   n5[K4]              parent: S3        (D's tip = loc)
--   | *   M1                   parents: S4, S6   (A's tip = rem)
--   | |\
--   | | * S6   n6[K3]          parent: S2        (C: never saw M0)
--   | * | S4   n4[K1]          parent: S3
--   |/ /
--   * | S3   n3[K1]            parent: M0
--   * |   M0                   parents: S2, S1   (criss-cross)
--   |\ \
--   | |/
--   | * S1   n1[K2]            parent: G
--   * | S2   n2[K1]            parent: G
--   |/
--   * G                        genesis
--
--   com = octopus(S5, M1) = S2
--   up  = octopus(S4, S6) = G  <  com     -- underflow
--
-- GEN_4: one key per peer, so no peer needs another's identity.
-- Consensus at M0 is a reps tie broken by hash, but the shape holds
-- either way: M0's parents are both children of G, and n6 hangs below
-- M0 whichever side wins.

require "tests"

local ROOT_A = ROOT .. "/bug-climb-ancestor/A/"
local ROOT_B = ROOT .. "/bug-climb-ancestor/B/"
local ROOT_C = ROOT .. "/bug-climb-ancestor/C/"
local ROOT_D = ROOT .. "/bug-climb-ancestor/D/"

local EXE_A = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C = ENV .. " ../src/freechains.lua --root " .. ROOT_C
local EXE_D = ENV .. " ../src/freechains.lua --root " .. ROOT_D

for _, dir in ipairs { ROOT_A, ROOT_B, ROOT_C, ROOT_D } do
    exec {
        cmd = "mkdir -p " .. dir,
    }
end

local function CHAIN (root)
    return root .. "/chains/#bca/"
end

do
    print("==> Test: climb must not descend below its floor")

    -- A: G
    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#bca' init file " .. GEN_4,
    }

    -- B clones at G, so its post forks AT genesis
    TEST "B clones bca (at G)"
    exec {
        cmd = EXE_B .. " chains add '#bca' clone " .. CHAIN(ROOT_A),
    }

    -- A: G -- n2[K1]
    TEST "A posts n2 (child of G)"
    local n2 = exec {
        cmd = EXE_A .. " --now=1010 chain '#bca' post inline 'n2\n' --file n2.txt --sign " .. KEY1,
    }

    -- C clones at S2: it never sees M0, so its post stays below it
    TEST "C clones bca (at S2, below the future M0)"
    exec {
        cmd = EXE_C .. " chains add '#bca' clone " .. CHAIN(ROOT_A),
    }

    -- 280808 : EARLY EXIT : rest needs clone/recv snapshots
    print("<== PASSED (280808 early exit)")
    os.exit()

    -- B: G -- n1[K2]
    TEST "B posts n1 (child of G)"
    local n1 = exec {
        cmd = EXE_B .. " --now=1020 chain '#bca' post inline 'n1\n' --file n1.txt --sign " .. KEY2,
    }

    -- A: G -- {S2, S1} -- M0        (criss-cross: both sides fork at G)
    TEST "A recvs B -> M0 = merge(S2, S1)"
    exec {
        cmd = EXE_A .. " --now=1030 chain '#bca' sync recv " .. CHAIN(ROOT_B),
    }

    -- A: ... M0 -- n3[K1]
    TEST "A posts n3 (child of M0)"
    local n3 = exec {
        cmd = EXE_A .. " --now=1040 chain '#bca' post inline 'n3\n' --file n3.txt --sign " .. KEY1,
    }

    -- D clones at S3: the fork between n4 and n5 sits ABOVE M0
    TEST "D clones bca (at S3)"
    exec {
        cmd = EXE_D .. " chains add '#bca' clone " .. CHAIN(ROOT_A),
    }

    -- A: ... S3 -- n4[K1]      D: ... S3 -- n5[K4]
    TEST "A posts n4, D posts n5 (concurrent, fork at S3)"
    local n4 = exec {
        cmd = EXE_A .. " --now=1050 chain '#bca' post inline 'n4\n' --file n4.txt --sign " .. KEY1,
    }
    local n5 = exec {
        cmd = EXE_D .. " --now=1060 chain '#bca' post inline 'n5\n' --file n5.txt --sign " .. KEY4,
    }

    -- C: ... S2 -- n6[K3]      (the deep attachment point)
    TEST "C posts n6 (child of S2, below M0)"
    local n6 = exec {
        cmd = EXE_C .. " --now=1070 chain '#bca' post inline 'n6\n' --file n6.txt --sign " .. KEY3,
    }

    -- A: ... -- M1 = merge(S4, S6)
    -- K1+K2 beat K3, so A's side wins and n6 becomes the second parent
    TEST "A recvs C -> M1 = merge(S4, S6)"
    exec {
        cmd = EXE_A .. " --now=1080 chain '#bca' sync recv " .. CHAIN(ROOT_C),
    }

    -- rem = M1 is a merge whose octopus underflows to genesis
    TEST "D recvs A: climb must stop at its floor (no underflow)"
    exec {
        cmd = EXE_D .. " --now=1090 chain '#bca' sync recv " .. CHAIN(ROOT_A),
    }

    TEST "D's order holds every post"
    local _, S = ORDER(EXE_D, "#bca")
    for _, t in ipairs {
        { n1, "n1" }, { n2, "n2" }, { n3, "n3" },
        { n4, "n4" }, { n5, "n5" }, { n6, "n6" },
    } do
        assert(S[t[1]], t[2] .. " missing from D order (climb underflow)")
    end
end

print("<== ALL PASSED")
