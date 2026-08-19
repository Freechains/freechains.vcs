#!/usr/bin/env lua5.4

-- P2 (plan 260818-prune), the DEEP case at real scale (SLOW: ~500
-- posts). A fork sitting deeper than keep=500 actions.
--
-- Single pioneer (GEN_1: KEY1) so KEY1 holds the majority and every
-- post refunds instantly -- 500+ posts never deplete reps.
-- KEY1 welcomes KEY2 in the common prefix, then B forks a single
-- low-rep KEY2 action: it LOSES consensus and appends after A's
-- entrenched prefix, so today the sync is ACCEPTED.
--
--         welcome[K1->K2]           <-- fork point (oct)
--          /          \
--   a1..a501[K1]        b1[K2]       A wins; B loses -> appends
--
-- TODAY: accepted (documents the vulnerability P2 closes).
-- WITH P2 + keep=500: depth 501 > 500 -> `chain sync : settled fork`.

require "tests"

local CHAIN  = "#prune-fork-deep"
local ROOT_A = ROOT .. "/prune-fork-deep/A/"
local ROOT_B = ROOT .. "/prune-fork-deep/B/"
local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local DIR_A  = ROOT_A .. "chains/" .. CHAIN .. "/"
local DIR_B  = ROOT_B .. "chains/" .. CHAIN .. "/"

local N = 501                   -- A's exclusive actions (> keep)

exec {
    cmd = "mkdir -p " .. ROOT_A .. " " .. ROOT_B,
}

local function depth (oct)
    return tonumber((exec {
        cmd = "git -C " .. DIR_A .. " log --diff-filter=A --format=%H " ..
            "HEAD ^" .. oct .. " -- actions/ | wc -l",
    }))
end

-- common prefix: seed, then KEY1 welcomes KEY2 (the fork point)
TEST "A creates chain; KEY1 welcomes KEY2"
exec {
    cmd = EXE_A .. " --now=1000 chains add '" .. CHAIN .. "' init file " .. GEN_1,
}
exec {
    cmd = EXE_A .. " --now=1100 chain '" .. CHAIN .. "' post inline 'seed\n' --file s.txt --sign " .. KEY1,
}
local welcome = exec {
    cmd = EXE_A .. " --now=1200 chain '" .. CHAIN .. "' like 10000 author '" .. PUB2 .. "' --sign " .. KEY1,
}
local oct = CID(DIR_A, welcome)

TEST "B clones the common prefix"
exec {
    cmd = EXE_B .. " chains add '" .. CHAIN .. "' clone " .. DIR_A,
}

-- A extends with N KEY1 posts (instant refund: KEY1 holds majority)
TEST ("A posts " .. N .. " exclusive actions (slow)")
for i = 1, N do
    exec {
        cmd = EXE_A .. " --now=" .. (1200+i) ..
            " chain '" .. CHAIN .. "' post inline 'a" .. i .. "\n'" ..
            " --file a" .. i .. ".txt --sign " .. KEY1,
    }
end

TEST "B forks one low-rep action off the welcome"
local b1 = exec {
    cmd = EXE_B .. " --now=1300 chain '" .. CHAIN .. "' post inline 'b1\n' --file b1.txt --sign " .. KEY2,
}

TEST ("the fork sits " .. N .. " actions deep (> keep=500)")
assert(depth(oct) == N, "expected depth " .. N .. ", got " .. depth(oct))

-- TODAY: accepted. WITH P2: replace with FAIL "settled fork".
TEST "A recvs B's deep fork: ACCEPTED today (P2 will refuse)"
exec {
    cmd = EXE_A .. " --now=9000 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
}

TEST "A's prefix intact, b1 appended last"
do
    local O = ORDER(EXE_A, CHAIN)
    assert(O[#O] == b1, "b1 ordered last (loser)")
end

print("<== ALL PASSED")
