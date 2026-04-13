#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/cli-order/A/"
local ROOT_B = ROOT .. "/cli-order/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

local function order (exe)
    local out = exec(exe .. " chain test order")
    local lines = {}
    for line in out:gmatch("[^\n]+") do
        lines[#lines+1] = line
    end
    return lines
end

-- 1. post order
do
    print("==> Step 1: post order")

    TEST "A creates chain"
    exec(EXE_A .. " --now=1000 chains add test init " .. GEN_1)

    TEST "A posts P1"
    local P1 = exec(EXE_A .. " --now=2000 chain test post inline 'hello' --sign " .. KEY1)

    TEST "order has P1"
    local O = order(EXE_A)
    assert(#O == 1, "expected 1 entry, got " .. #O)
    assert(O[1] == P1, "expected P1")

    TEST "A posts P2"
    local P2 = exec(EXE_A .. " --now=3000 chain test post inline 'world' --sign " .. KEY1)

    TEST "order has P1, P2"
    O = order(EXE_A)
    assert(#O == 2, "expected 2 entries, got " .. #O)
    assert(O[1] == P1, "first should be P1")
    assert(O[2] == P2, "second should be P2")
end

-- 2. like order
do
    print("==> Step 2: like + order")

    local O = order(EXE_A)
    local P1 = O[1]

    TEST "A likes P1"
    exec(EXE_A .. " --now=4000 chain test like 1 post " .. P1 .. " --sign " .. KEY1)

    TEST "order has P1, P2, L1"
    O = order(EXE_A)
    assert(#O == 3, "expected 3 entries, got " .. #O)
end

-- 3. sync preserves order
do
    print("==> Step 3: sync preserves order")

    TEST "B clones"
    exec(EXE_B .. " chains add test clone " .. REPO_A)

    TEST "B order matches A"
    local oa = order(EXE_A)
    local ob = order(EXE_B)
    assert(#oa == #ob, "length mismatch: A=" .. #oa .. " B=" .. #ob)
    for i = 1, #oa do
        assert(oa[i] == ob[i], "mismatch at " .. i)
    end
end

-- 4. recv preserves order
do
    print("==> Step 4: recv preserves order")

    TEST "A posts P3"
    local P3 = exec(EXE_A .. " --now=5000 chain test post inline 'third' --sign " .. KEY1)

    TEST "B recvs from A"
    exec(EXE_B .. " --now=5500 chain test sync recv " .. REPO_A)

    TEST "B order matches A"
    local oa = order(EXE_A)
    local ob = order(EXE_B)
    assert(#oa == #ob, "length mismatch: A=" .. #oa .. " B=" .. #ob)
    for i = 1, #oa do
        assert(oa[i] == ob[i], "mismatch at " .. i)
    end
end

print("<== ALL PASSED")
