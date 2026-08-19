#!/usr/bin/env lua5.4

-- P2 (plan 260818-prune): sync must refuse a fork whose point sits
-- deeper than keep=500 actions back in my order. Real scale, SLOW
-- (~500 signed posts).
--
-- Single pioneer (GEN_1: KEY1) so KEY1 holds the majority and every
-- post refunds instantly -- 500+ posts never deplete reps.
-- KEY1 welcomes KEY2 in the common prefix; two clones fork one
-- low-rep KEY2 action each, at DIFFERENT depths, to pin the `>`
-- boundary exactly:
--
--         welcome[K1->K2]           <-- P501 forks here (depth 501)
--            |
--          a1[K1]                   <-- P500 forks here (depth 500)
--            |
--          ...
--          a501[K1]                 <-- A's tip
--
-- P500 forks at a1: depth 500, `500 > 500` false -> ACCEPTED (green
--   before AND after P2: the over-refusal guard at the boundary).
-- P501 forks at welcome: depth 501 -> REFUSED `pruned state` (RED
--   until P2 lands; today recv accepts, so it fails on purpose).

require "tests"

local CHAIN  = "#prune"
local ROOT_A = ROOT .. "/prune/A/"
local R500   = ROOT .. "/prune/P500/"
local R501   = ROOT .. "/prune/P501/"
local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE500 = ENV .. " ../src/freechains.lua --root " .. R500
local EXE501 = ENV .. " ../src/freechains.lua --root " .. R501
local DIR_A  = ROOT_A .. "chains/" .. CHAIN .. "/"
local D500   = R500 .. "chains/" .. CHAIN .. "/"
local D501   = R501 .. "chains/" .. CHAIN .. "/"

local N = 501                   -- A's exclusive actions

exec {
    cmd = "mkdir -p " .. ROOT_A .. " " .. R500 .. " " .. R501,
}

-- the P2 count mechanic, run directly: actions above the fork on A
local function depth (oct)
    return tonumber((exec {
        cmd = "git -C " .. DIR_A .. " log --diff-filter=A --format=%H " ..
            "HEAD ^" .. oct .. " -- actions/ | wc -l",
    }))
end

-- common prefix: seed, then KEY1 welcomes KEY2 (P501's fork point)
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

-- P501 clones here: its fork point will be `welcome` (depth 501)
TEST "P501 clones at the welcome"
exec {
    cmd = EXE501 .. " chains add '" .. CHAIN .. "' clone " .. DIR_A,
}

-- a1: P500's fork point (depth 500)
local a1 = exec {
    cmd = EXE_A .. " --now=1201 chain '" .. CHAIN .. "' post inline 'a1\n' --file a1.txt --sign " .. KEY1,
}

TEST "P500 clones at a1"
exec {
    cmd = EXE500 .. " chains add '" .. CHAIN .. "' clone " .. DIR_A,
}

-- A extends to N total exclusive actions (instant refund: majority)
TEST ("A posts up to " .. N .. " exclusive actions (slow)")
for i = 2, N do
    exec {
        cmd = EXE_A .. " --now=" .. (1200+i) ..
            " chain '" .. CHAIN .. "' post inline 'a" .. i .. "\n'" ..
            " --file a" .. i .. ".txt --sign " .. KEY1,
    }
end

-- each clone forks one low-rep KEY2 action (loses consensus)
TEST "P500 and P501 each fork one low-rep action"
exec {
    cmd = EXE500 .. " --now=1300 chain '" .. CHAIN .. "' post inline 'x\n' --file x.txt --sign " .. KEY2,
}
exec {
    cmd = EXE501 .. " --now=1300 chain '" .. CHAIN .. "' post inline 'y\n' --file y.txt --sign " .. KEY2,
}

TEST "fork depths straddle keep=500"
assert(depth(CID(DIR_A, a1)) == 500, "P500 fork depth should be 500")
assert(depth(CID(DIR_A, welcome)) == 501, "P501 fork depth should be 501")

-- boundary ACCEPT: depth 500 is not > keep, so recv succeeds.
-- green before AND after P2.
TEST "A recvs P500 (depth 500): accepted"
exec {
    cmd = EXE_A .. " --now=9000 chain '" .. CHAIN .. "' sync recv " .. D500,
}

-- boundary REFUSE: depth 501 > keep. RED until P2 lands (today recv
-- accepts, so this FAIL fails on purpose).
TEST "A recvs P501 (depth 501): REFUSED (pruned state)"
FAIL {
    cmd = EXE_A .. " --now=9001 chain '" .. CHAIN .. "' sync recv " .. D501,
    err = "ERROR : chain sync : pruned state",
}

print("<== ALL PASSED")
