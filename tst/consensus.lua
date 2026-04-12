#!/usr/bin/env lua5.4

require "tests"
local ssh = require "freechains.chain.ssh"

local ROOT_A = ROOT .. "/consensus/A/"
local ROOT_B = ROOT .. "/consensus/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

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

print("<== ALL PASSED")
