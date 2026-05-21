#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/cli-all/A/"
local ROOT_B = ROOT .. "/cli-all/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

local P1, P2, L1, P3, AP4, BP4, fst, snd, BEG, LIKE

-- 1. post order
do
    print("==> Step 1: post order")

    TEST "A creates chain"
    exec(EXE_A .. " --now=1000 chains add test init inline --sign " .. KEY1)

    TEST "A posts P1"
    P1 = exec(EXE_A .. " --now=2000 chain test post inline 'hello' --sign " .. KEY1)

    TEST "order has P1"
    assert(exec(EXE_A .. " chain test all order") == P1)

    TEST "dag has P1"
    assert(
        exec(EXE_A .. " chain test all dag") ==
        string.format([[
                 %s]], P1:sub(1,7))
    )

    TEST "A posts P2"
    P2 = exec(EXE_A .. " --now=3000 chain test post inline 'world' --sign " .. KEY1)

    TEST "order has P1, P2"
    assert(exec(EXE_A .. " chain test all order") == P1.."\n"..P2.."\n")

    TEST "dag has P1, P2"
    assert(
        exec(EXE_A .. " chain test all dag") ==
        string.format([[
                 %s
                    |
                 %s
]], P1:sub(1,7), P2:sub(1,7))
    )
end

-- 2. like order
do
    print("==> Step 2: like + order")

    TEST "A likes P1"
    L1 = exec(EXE_A .. " --now=4000 chain test like 1 post " .. P1 .. " --sign " .. KEY1)

    TEST "order has P1, P2, L1"
    assert(exec(EXE_A .. " chain test all order") == P1.."\n"..P2.."\n"..L1.."\n")

    TEST "dag has P1, P2, L1"
    assert(
        exec(EXE_A .. " chain test all dag") ==
        string.format([[
                 %s
                    |
                 %s
                    |
                 %s
]], P1:sub(1,7), P2:sub(1,7), L1:sub(1,7))
    )
end

-- 3. sync preserves order
do
    print("==> Step 3: sync preserves order")

    TEST "B clones"
    exec(EXE_B .. " chains add test clone " .. REPO_A)

    TEST "B order matches A"
    assert(
        exec(EXE_A .. " chain test all order") ==
        exec(EXE_B .. " chain test all order")
    )

    TEST "B dag matches A"
    assert(
        exec(EXE_A .. " chain test all dag") ==
        exec(EXE_B .. " chain test all dag")
    )
end

-- 4. recv preserves order
do
    print("==> Step 4: recv preserves order")

    TEST "A posts P3"
    P3 = exec(EXE_A .. " --now=5000 chain test post inline 'third' --sign " .. KEY1)

    TEST "B recvs from A"
    exec(EXE_B .. " --now=5500 chain test sync recv " .. REPO_A)

    TEST "B order matches A"
    assert(
        exec(EXE_A .. " chain test all order") ==
        exec(EXE_B .. " chain test all order")
    )

    TEST "B dag matches A"
    assert(
        exec(EXE_A .. " chain test all dag") ==
        exec(EXE_B .. " chain test all dag")
    )

    TEST "A dag has 4 nodes"
    assert(
        exec(EXE_A .. " chain test all dag") ==
        string.format([[
                 %s
                    |
                 %s
                    |
                 %s
                    |
                 %s
]], P1:sub(1,7), P2:sub(1,7), L1:sub(1,7), P3:sub(1,7))
    )
end

-- 5. fork via diverge
do
    print("==> Step 5: fork via diverge")

    TEST "A posts AP4"
    AP4 = exec(EXE_A .. " --now=6000 chain test post inline 'a_post_4' --sign " .. KEY1)

    TEST "B posts BP4 (diverges from A)"
    BP4 = exec(EXE_B .. " --now=6500 chain test post inline 'b_post_4' --sign " .. KEY1)

    TEST "B recvs from A (case 4 diverge)"
    exec(EXE_B .. " --now=7000 chain test sync recv " .. REPO_A)

    TEST "A dag is linear with 5 nodes"
    assert(
        exec(EXE_A .. " chain test all dag") ==
        string.format([[
                 %s
                    |
                 %s
                    |
                 %s
                    |
                 %s
                    |
                 %s
]], P1:sub(1,7), P2:sub(1,7), L1:sub(1,7), P3:sub(1,7), AP4:sub(1,7))
    )

    TEST "B order has fork resolution"
    local lines = {}
    for line in exec(EXE_B .. " chain test all order"):gmatch("[^\n]+") do
        lines[#lines+1] = line
    end
    assert(#lines == 6, "expected 6 commits, got " .. #lines)
    assert(lines[1] == P1, "expected P1 at 1")
    assert(lines[2] == P2, "expected P2 at 2")
    assert(lines[3] == L1, "expected L1 at 3")
    assert(lines[4] == P3, "expected P3 at 4")
    fst, snd = lines[5], lines[6]
    assert(
        (fst == BP4 and snd == AP4) or (fst == AP4 and snd == BP4),
        "fst/snd should be BP4/AP4 in some order"
    )

    TEST "B dag shows fork (state-merge filtered)"
    assert(
        exec(EXE_B .. " chain test all dag") ==
        string.format([[
                 %s
                    |
                 %s
                    |
                 %s
                    |
                 %s
                  /   \
             %s %s
]], P1:sub(1,7), P2:sub(1,7), L1:sub(1,7), P3:sub(1,7), fst:sub(1,7), snd:sub(1,7))
    )
end

-- 6. beg + like (like-merge in V)
do
    print("==> Step 6: beg + like")

    TEST "KEY2 begs on B"
    BEG = exec(EXE_B .. " --now=8000 chain test post inline 'please help' --beg --sign " .. KEY2)
    assert(#BEG == 40, "expected hash, got: " .. BEG)

    TEST "KEY1 likes BEG"
    LIKE = exec(EXE_B .. " --now=8500 chain test like 1 post " .. BEG .. " --sign " .. KEY1)
    assert(#LIKE == 40, "expected hash, got: " .. LIKE)

    TEST "B order now has 8 commits (M filtered, BEG+LIKE added)"
    local lines = {}
    for line in exec(EXE_B .. " chain test all order"):gmatch("[^\n]+") do
        lines[#lines+1] = line
    end
    assert(#lines == 8, "expected 8 commits, got " .. #lines)
    assert(lines[7] == BEG,  "expected BEG at 7")
    assert(lines[8] == LIKE, "expected LIKE at 8")

    TEST "B dag extends with BEG hash + LIKE as join hash"
    assert(
        exec(EXE_B .. " chain test all dag") ==
        string.format([[
                 %s
                    |
                 %s
                    |
                 %s
                    |
                 %s
                  /   \
             %s %s
                  \   /
                 %s
                  \   /
                 %s
]], P1:sub(1,7), P2:sub(1,7), L1:sub(1,7), P3:sub(1,7), fst:sub(1,7), snd:sub(1,7), BEG:sub(1,7), LIKE:sub(1,7))
    )
end

print("<== ALL PASSED")
