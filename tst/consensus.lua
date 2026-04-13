#!/usr/bin/env lua5.4

require "tests"
local ssh = require "freechains.chain.ssh"

local ROOT_A = ROOT .. "/consensus/A/"
local ROOT_B = ROOT .. "/consensus/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

local function order (exe, chain)
    local out = exec(exe .. " chain " .. chain .. " order")
    local T = {}
    local S = {}
    for line in out:gmatch("[^\n]+") do
        T[#T+1] = line
        S[line] = true
    end
    return T, S
end

-- 1. local wins by prefix reps
-- GEN_2: KEY1=15, KEY2=15
-- Before fork: KEY2 likes seed → KEY2 loses reps → KEY1 > KEY2
-- A posts with KEY1 (higher), B posts with KEY2 (lower)
-- A recvs B → A wins
do
    print("==> Test 1: local wins by prefix reps")

    TEST "A creates chain + seeds shared.txt"
    exec(EXE_A .. " --now=1000 chains add cons-a init " .. GEN_2)
    local seed_a = exec (
        EXE_A .. " --now=1100 chain cons-a post inline 'seed\n' --file shared.txt --sign " .. KEY1
    )

    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    exec (
        EXE_A .. " --now=1200 chain cons-a like 1 post " .. seed_a .. " --sign " .. KEY2
    )

    TEST "B clones cons-a"
    exec(EXE_B .. " chains add cons-a clone " .. ROOT_A .. "/chains/cons-a/")

    TEST "A appends alpha with KEY1 (higher prefix reps)"
    exec (
        EXE_A .. " --now=2000 chain cons-a post inline 'alpha\n' --file shared.txt --sign " .. KEY1
    )

    TEST "B appends beta with KEY2 (lower prefix reps)"
    exec (
        EXE_B .. " --now=2000 chain cons-a post inline 'beta\n' --file shared.txt --sign " .. KEY2
    )

    TEST "A recvs from B (A wins by prefix reps)"
    exec (
        EXE_A .. " --now=3000 chain cons-a sync recv " .. ROOT_B .. "/chains/cons-a/"
    )

    TEST "A's shared.txt has alpha, not beta"
    local h = io.open(ROOT_A .. "/chains/cons-a/shared.txt")
    local content = h:read("a")
    h:close()
    assert(content:match("alpha"), "alpha missing: " .. content)
    assert(not content:match("beta"), "beta should be discarded: " .. content)

    TEST "A's posts.lua has only the winning post"
    local posts = dofile(ROOT_A .. "/chains/cons-a/.freechains/state/posts.lua")
    local n = 0
    for _ in pairs(posts) do n = n + 1 end
    assert(n == 2, "expected 2 posts (seed+alpha), got " .. n)
end

-- 2. remote wins by prefix reps
-- Same setup, but A posts with KEY2 (lower), B posts with KEY1 (higher)
-- A recvs B → B wins
do
    print("==> Test 2: remote wins by prefix reps")

    TEST "A creates chain + seeds shared.txt"
    exec(EXE_A .. " --now=1000 chains add cons-b init " .. GEN_2)
    local seed_b = exec (
        EXE_A .. " --now=1100 chain cons-b post inline 'seed\n' --file shared.txt --sign " .. KEY1
    )

    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    exec (
        EXE_A .. " --now=1200 chain cons-b like 1 post " .. seed_b .. " --sign " .. KEY2
    )

    TEST "B clones cons-b"
    exec(EXE_B .. " chains add cons-b clone " .. ROOT_A .. "/chains/cons-b/")

    TEST "A appends alpha with KEY2 (lower prefix reps)"
    exec (
        EXE_A .. " --now=2000 chain cons-b post inline 'alpha\n' --file shared.txt --sign " .. KEY2
    )

    TEST "B appends beta with KEY1 (higher prefix reps)"
    exec (
        EXE_B .. " --now=2000 chain cons-b post inline 'beta\n' --file shared.txt --sign " .. KEY1
    )

    TEST "A recvs from B (B wins by prefix reps)"
    local out = exec (
        EXE_A .. " --now=3000 chain cons-b sync recv " .. ROOT_B .. "/chains/cons-b/"
    )
    assert(out:match "ERROR : content conflict\nvoided : %S+\n")

    TEST "A's shared.txt has beta, not alpha"
    local h = io.open(ROOT_A .. "/chains/cons-b/shared.txt")
    local content = h:read("a")
    h:close()
    assert(content:match("beta"), "beta missing: " .. content)
    assert(not content:match("alpha"), "alpha should be discarded: " .. content)

    TEST "A's posts.lua has only the winning post"
    local posts = dofile(ROOT_A .. "/chains/cons-b/.freechains/state/posts.lua")
    local n = 0
    for _ in pairs(posts) do n = n + 1 end
    assert(n == 2, "expected 2 posts (seed+beta), got " .. n)
end

-- 3. loser invalidated by winner context
-- GEN_4: KEY1=7500, KEY2=7500, KEY3=7500, KEY4=7500
-- Remote: KEY1,KEY2,KEY3 each dislike KEY4 author by 3 → KEY4 ≤ 0
-- Local: KEY4 posts P1, KEY2 posts P2
-- Remote wins (22500 > 15000)
-- Loser replay: P1 by KEY4 fails → P2 by KEY2 also voided (cascade)
do
    print("==> Test 3: loser invalidated by winner context")

    TEST "A creates chain"
    exec(EXE_A .. " --now=1000 chains add cons-c init " .. GEN_4)

    TEST "B clones cons-c"
    exec(EXE_B .. " chains add cons-c clone " .. ROOT_A .. "/chains/cons-c/")

    TEST "B: KEY1 dislikes KEY4 author by 3"
    exec (
        EXE_B .. " --now=2000 chain cons-c dislike 3 author '" .. PUB4 .. "' --sign " .. KEY1
    )

    TEST "B: KEY2 dislikes KEY4 author by 3"
    exec (
        EXE_B .. " --now=2000 chain cons-c dislike 3 author '" .. PUB4 .. "' --sign " .. KEY2
    )

    TEST "B: KEY3 dislikes KEY4 author by 3"
    exec (
        EXE_B .. " --now=2000 chain cons-c dislike 3 author '" .. PUB4 .. "' --sign " .. KEY3
    )

    TEST "A: KEY2 posts P1 (survives)"
    local P1 = exec (
        EXE_A .. " --now=2000 chain cons-c post inline 'P1\n' --sign " .. KEY2
    )

    TEST "A: KEY4 posts P2 (fails in winner context)"
    local P2 = exec (
        EXE_A .. " --now=2100 chain cons-c post inline 'P2\n' --sign " .. KEY4
    )

    TEST "A: KEY2 posts P3 (valid but voided by cascade)"
    local P3 = exec (
        EXE_A .. " --now=2200 chain cons-c post inline 'P3\n' --sign " .. KEY2
    )

    TEST "order before merge: P1, P2, P3 present"
    do
        local O, S = order(EXE_A, "cons-c")
        assert(#O == 3, "expected 3 entries, got " .. #O)
        assert(S[P1], "P1 should be in order")
        assert(S[P2], "P2 should be in order")
        assert(S[P3], "P3 should be in order")
    end

    TEST "A recvs from B (B wins, P2+P3 voided, P1 survives)"
    local out = exec (
        EXE_A .. " --now=3000 chain cons-c sync recv " .. ROOT_B .. "/chains/cons-c/"
    )
    local voided = 0
    for _ in out:gmatch("voided") do voided = voided + 1 end
    assert(voided == 2, "expected 2 voided, got " .. voided)

    TEST "A's posts.lua has 1 post (P1 survived)"
    local posts = dofile(ROOT_A .. "/chains/cons-c/.freechains/state/posts.lua")
    local n = 0
    for _ in pairs(posts) do n = n + 1 end
    assert(n == 1, "expected 1 post (P1), got " .. n)

    TEST "order after merge: P2, P3 revoked"
    do
        local O, S = order(EXE_A, "cons-c")
        assert(S[P1], "P1 should survive in order")
        assert(not S[P2], "P2 should be revoked from order")
        assert(not S[P3], "P3 should be revoked from order")
    end
end

print("<== ALL PASSED")
