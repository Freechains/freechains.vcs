#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/cli-all/A/"
local ROOT_B = ROOT .. "/cli-all/B/"
local ROOT_C = ROOT .. "/cli-all/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)
exec("mkdir -p " .. ROOT_C)

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

    -- git:  genesis ── P1 ── S1 ── P2 ── S2   (S* = per-post state commits)
    -- dag:  P1 │ P2                            (state commits filtered out)

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

    -- git:  ... S2 ── L1 ── S3        (L1 = like on P1)
    -- dag:  P1 │ P2 │ L1

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

    -- git:  ... S3 ── P3 ── S4        (A posts P3; B fast-forwards to match)
    -- dag:  P1 │ P2 │ L1 │ P3

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

    -- A stays linear:  ... P3 ── AP4
    -- B diverges, then recvs A → state-merge M (filtered from dag):
    --   git:  ... P3 ──┬── BP4 ──┐
    --                  └── AP4 ──┴── M
    --   dag:  ... P3 ──┬── fst        (winner col 16)
    --                  └── snd        (loser  col 24)

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

    -- beg lives on refs/begs/ (off-main): invisible to order/dag, listed by begs
    TEST "all begs lists the pending beg"
    assert(exec(EXE_B .. " chain test all begs") == BEG)

    TEST "all order does not include the pending beg"
    local has_beg = false
    for line in exec(EXE_B .. " chain test all order"):gmatch("[^\n]+") do
        if line == BEG then has_beg = true end
    end
    assert(not has_beg, "pending beg should not be in order")

    TEST "KEY1 likes BEG"
    LIKE = exec(EXE_B .. " --now=8500 chain test like 1 post " .. BEG .. " --sign " .. KEY1)
    assert(#LIKE == 40, "expected hash, got: " .. LIKE)

    TEST "all begs empty after like (ref consumed)"
    assert(exec(EXE_B .. " chain test all begs") == "")

    -- KEY2 begs (BEG lives on refs/begs/, off-main); KEY1's like merges it back:
    --   git:  ... M ─────────────── LIKE ── S      (LIKE: a like-trailer merge)
    --             \               /
    --              BEG ── Sbeg ──/
    --   dag:  ... fst│snd ── (M filtered) ── BEG ── LIKE
    --         LIKE's backs: BEG (immediate, drawn as |) + fst,snd (distant, annotated)

    TEST "B order now has 8 commits (M filtered, BEG+LIKE added)"
    local lines = {}
    for line in exec(EXE_B .. " chain test all order"):gmatch("[^\n]+") do
        lines[#lines+1] = line
    end
    assert(#lines == 8, "expected 8 commits, got " .. #lines)
    assert(lines[7] == BEG,  "expected BEG at 7")
    assert(lines[8] == LIKE, "expected LIKE at 8")

    TEST "B dag: LIKE has immediate parent (|) + distant parents annotated"
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
                    |
                 %s
           (^%s ^%s)
]], P1:sub(1,7), P2:sub(1,7), L1:sub(1,7), P3:sub(1,7), fst:sub(1,7), snd:sub(1,7), BEG:sub(1,7), LIKE:sub(1,7), fst:sub(1,7), snd:sub(1,7))
    )
end

-- 7. three-way fork (3 peers post from a shared tip)
do
    print("==> Step 7: three-way fork")

    local REPO_A2 = ROOT_A .. "/chains/tri/"
    local REPO_B2 = ROOT_B .. "/chains/tri/"
    local REPO_C2 = ROOT_C .. "/chains/tri/"

    TEST "A creates tri + shared post P0"
    exec(EXE_A .. " --now=1000 chains add tri init inline --sign " .. KEY1)
    local P0 = exec(EXE_A .. " --now=2000 chain tri post inline 'shared' --sign " .. KEY1)

    TEST "B, C clone tri"
    exec(EXE_B .. " chains add tri clone " .. REPO_A2)
    exec(EXE_C .. " chains add tri clone " .. REPO_A2)

    TEST "A, B, C each post from P0"
    exec(EXE_A .. " --now=3000 chain tri post inline 'from a' --sign " .. KEY1)
    exec(EXE_B .. " --now=3500 chain tri post inline 'from b' --sign " .. KEY1)
    exec(EXE_C .. " --now=4000 chain tri post inline 'from c' --sign " .. KEY1)

    TEST "A recvs B then C (two diverge merges)"
    exec(EXE_A .. " --now=5000 chain tri sync recv " .. REPO_B2)
    exec(EXE_A .. " --now=5500 chain tri sync recv " .. REPO_C2)

    -- 3 peers post from shared P0; A recvs B then C → two state-merges M1, M2:
    --   git:  P0 ──┬── PA ──┐
    --              ├── PB ──┼── M1 ── M2     (merges filtered from dag)
    --              └── PC ──┘
    --   dag:  P0 ──┬── s2     (col 12)
    --              ├── s3     (col 20)
    --              └── s4     (col 28)

    TEST "A order: P0 then 3 siblings"
    local lines = {}
    for line in exec(EXE_A .. " chain tri all order"):gmatch("[^\n]+") do
        lines[#lines+1] = line
    end
    assert(#lines == 4, "expected 4 commits, got " .. #lines)
    assert(lines[1] == P0, "expected P0 first, got " .. lines[1])

    TEST "A dag shows 3-way fork"
    assert(
        exec(EXE_A .. " chain tri all dag") ==
        string.format([[
                 %s
                /   |   \
         %s %s %s
]], P0:sub(1,7), lines[2]:sub(1,7), lines[3]:sub(1,7), lines[4]:sub(1,7))
    )
end

print("<== ALL PASSED")
