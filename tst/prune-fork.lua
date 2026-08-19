#!/usr/bin/env lua5.4

-- P2 (plan 260818-prune): sync must refuse a fork whose point sits
-- deeper than `keep` actions back in my order.
--
-- This test documents TODAY's behavior: a deep LOSER fork is ACCEPTED
-- (it appends after the settled prefix, no reorder, so no hard fork).
-- That acceptance is exactly what P2 will refuse, and it is why the
-- octopus snapshot at the old fork point must survive prune.
--
--            seed[K1]                <-- fork point (oct)
--            /      \
--     a1..aN[K1,K2]   b1[K3]         A wins (more prefix reps)
--                                    B loses -> appends after aN
--
-- Once P2 lands (with a chain deeper than keep=500), the same deep
-- fork must instead FAIL with `chain sync : settled fork`.

require "tests"

local CHAIN  = "#prune-fork"
local ROOT_A = ROOT .. "/prune-fork/A/"
local ROOT_B = ROOT .. "/prune-fork/B/"
local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local DIR_A  = ROOT_A .. "chains/" .. CHAIN .. "/"
local DIR_B  = ROOT_B .. "chains/" .. CHAIN .. "/"

local N = 6                     -- A's exclusive actions (the fork depth)

exec {
    cmd = "mkdir -p " .. ROOT_A .. " " .. ROOT_B,
}

-- the P2 count mechanic, run directly: actions above the fork on A
local function depth (oct)
    return tonumber((exec {
        cmd = "git -C " .. DIR_A .. " log --diff-filter=A --format=%H " ..
            "HEAD ^" .. oct .. " -- actions/ | wc -l",
    }))
end

-- common base: seed, cloned by B (GEN_3: KEY1 KEY2 KEY3, equal reps)
TEST "A creates chain + seed; B clones"
exec {
    cmd = EXE_A .. " --now=1000 chains add '" .. CHAIN .. "' init file " .. GEN_3,
}
local seed = exec {
    cmd = EXE_A .. " --now=1100 chain '" .. CHAIN .. "' post inline 'seed\n' --file s.txt --sign " .. KEY1,
}
exec {
    cmd = EXE_B .. " chains add '" .. CHAIN .. "' clone " .. DIR_A,
}
local oct = CID(DIR_A, seed)

-- A extends with KEY1 and KEY2 (exclusive reps 2/3 of the chain)
TEST "A posts N exclusive actions"
for i = 1, N do
    local k = (i % 2 == 0) and KEY1 or KEY2
    exec {
        cmd = EXE_A .. " --now=" .. (1100+i) ..
            " chain '" .. CHAIN .. "' post inline 'a" .. i .. "\n'" ..
            " --file a" .. i .. ".txt --sign " .. k,
    }
end

-- B forks at the seed with a single low-rep action (KEY3)
TEST "B posts one exclusive action (the loser branch)"
local b1 = exec {
    cmd = EXE_B .. " --now=1200 chain '" .. CHAIN .. "' post inline 'b1\n' --file b1.txt --sign " .. KEY3,
}

TEST "the fork sits N actions deep in A's order"
assert(depth(oct) == N, "expected depth " .. N .. ", got " .. depth(oct))

-- TODAY: A receives B's deep fork; B loses, appends after A's prefix,
-- no reorder -> accepted. (Post-P2 with depth > keep: settled fork.)
TEST "A recvs B's deep fork: ACCEPTED today"
exec {
    cmd = EXE_A .. " --now=2000 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
}

TEST "A's prefix is intact and b1 appended after it"
do
    local O = ORDER(EXE_A, CHAIN)
    assert(O[1] == seed, "seed still first")
    assert(O[#O] == b1, "b1 ordered last (loser)")
    assert(#O == N + 2, "seed + N + b1, got " .. #O)
end

print("<== ALL PASSED")
