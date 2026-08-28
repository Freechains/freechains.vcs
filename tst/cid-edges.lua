#!/usr/bin/env lua5.4

-- Identity edges for plan 260821-cid-aid-tree: pins TODAY's behavior
-- so the aid==cid redesign can prove it changes nothing observable.
--
-- 1. identical CONSECUTIVE posts (same author/text/--now): ancestry
--    distinguishes them -- post2's backs = [aid1] -> different aid.
--    Under B: parents = [cid1] -> different cid. Same shape.
--
-- 2. identical CONCURRENT posts on the SAME tip (two clones): same
--    file -> same aid, and neutral dates make the COMMITS collide
--    too (same tree+parents+message) -> literally one commit; sync
--    sees nothing new. Under B: same message+parents -> same cid.
--    Identical semantics, so B's "idempotent collision" is today's
--    behavior already.

require "tests"

local CHAIN  = "/cid-edges"
local ROOT_A = ROOT .. "/cid-edges/A/"
local ROOT_B = ROOT .. "/cid-edges/B/"
local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local DIR_A  = ROOT_A .. "chains/" .. CHAIN .. "/"
local DIR_B  = ROOT_B .. "chains/" .. CHAIN .. "/"

exec {
    cmd = "mkdir -p " .. ROOT_A .. " " .. ROOT_B,
}

TEST "A creates chain + seed"
exec {
    cmd = EXE_A .. " --now=1000 chains add '" .. CHAIN .. "' init --pioneer=" .. KEY1,
}
exec {
    cmd = EXE_A .. " --now=1100 chain '" .. CHAIN .. "' post --sign " .. KEY1 .. " inline -- seed",
}

-- 1. consecutive identical posts
do
    TEST "identical consecutive posts get DIFFERENT ids"
    local p1 = exec {
        cmd = EXE_A .. " --now=1200 chain '" .. CHAIN .. "' post --sign " .. KEY1 .. " inline -- same",
    }
    local p2 = exec {
        cmd = EXE_A .. " --now=1200 chain '" .. CHAIN .. "' post --sign " .. KEY1 .. " inline -- same",
    }
    assert(p1 ~= p2, "ancestry must distinguish identical content")

    TEST "both are in the order"
    local _, S = ORDER(EXE_A, CHAIN)
    assert(S[p1] and S[p2], "both posts ordered")
end

-- 2. concurrent identical posts on the same tip
do
    TEST "B clones; A and B post the same text at the same --now"
    exec {
        cmd = EXE_B .. " --now=1300 chains add '" .. CHAIN .. "' clone " .. DIR_A,
    }
    local pa = exec {
        cmd = EXE_A .. " --now=1400 chain '" .. CHAIN .. "' post --sign " .. KEY1 .. " inline -- twin",
    }
    local pb = exec {
        cmd = EXE_B .. " --now=1400 chain '" .. CHAIN .. "' post --sign " .. KEY1 .. " inline -- twin",
    }
    assert(pa == pb, "same content + same tip -> same aid")

    TEST "the COMMITS collide too (neutral dates): one commit"
    local ca = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    local cb = exec {
        cmd = "git -C " .. DIR_B .. " rev-parse HEAD",
    }
    assert(ca == cb, "same tree+parents+message -> same cid")

    TEST "sync sees nothing new; the twin is ONE action"
    exec {
        cmd = EXE_B .. " --now=1500 chain '" .. CHAIN .. "' sync recv " .. DIR_A,
    }
    local O, S = ORDER(EXE_B, CHAIN)
    assert(S[pa], "twin present")
    local n = 0
    for _, a in ipairs(O) do
        if a == pa then
            n = n + 1
        end
    end
    assert(n == 1, "twin ordered exactly once")
end

print("<== ALL PASSED")
