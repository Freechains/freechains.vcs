#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/sync/A/"
local ROOT_B = ROOT .. "/sync/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

-- shared setup: A creates chain, B clones
exec(EXE_A .. " --now=1000 chains add test init " .. GEN_1)
exec(EXE_B .. " chains add test clone " .. REPO_A)
-- A:  [state] G
-- B:  [state] G

local function head (repo)
    return exec("git -C " .. repo .. " rev-parse HEAD")
end

local function begs (repo)
    return exec (
        "git -C " .. repo .. " for-each-ref refs/begs/ --format=%(refname)"
    )
end

-- 1. recv basic
do
    print("==> Step 1: recv basic")

    TEST "A posts"
    exec(EXE_A .. " --now=2000 chain test post inline 'p1' --sign " .. KEY1)
    -- A:  G ── [post] P1 ── [state] S1
    -- B:  G

    TEST "B recvs from A"
    exec(EXE_B .. " chain test sync recv " .. REPO_A)
    -- A:  G ── P1 ── S1
    -- B:  G ── P1 ── S1

    TEST "heads equal"
    assert(head(REPO_A) == head(REPO_B))
end

-- 2. send basic
do
    print("==> Step 2: send basic")

    TEST "A posts"
    exec(EXE_A .. " --now=3000 chain test post inline 'p2' --sign " .. KEY1)
    -- A:  G ── P1 ── S1 ── [post] P2 ── [state] S2
    -- B:  G ── P1 ── S1

    TEST "A sends to B"
    exec(EXE_A .. " chain test sync send " .. REPO_B)
    -- A:  G ── P1 ── S1 ── P2 ── S2
    -- B:  G ── P1 ── S1 ── P2 ── S2

    TEST "heads equal"
    assert(head(REPO_A) == head(REPO_B))
end

-- 3. recv begs
do
    print("==> Step 3: recv begs")

    TEST "A creates a beg"
    local BEG = exec (
        EXE_A .. " --now=4000 chain test post inline 'please' --beg --sign " .. KEY2
    )
    assert(#BEG == 40)
    assert(begs(REPO_A):match("beg%-" .. BEG))
    -- A:  G ── P1 ── S1 ── P2 ── S2        refs/begs/beg-BEG -> BEG
    --                           └── [beg] BEG
    -- B:  G ── P1 ── S1 ── P2 ── S2

    TEST "B recvs from A"
    exec(EXE_B .. " chain test sync recv " .. REPO_A)
    -- A:  G ── P1 ── S1 ── P2 ── S2        refs/begs/beg-BEG -> BEG
    --                           └── [beg] BEG
    -- B:  G ── P1 ── S1 ── P2 ── S2        refs/begs/beg-BEG -> BEG
    --                           └── [beg] BEG

    TEST "B has the beg ref"
    assert(begs(REPO_B) == begs(REPO_A))
end

print("<== ALL PASSED")
