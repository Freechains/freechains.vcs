#!/usr/bin/env lua5.4

require "tests"
local ssh = require "freechains.chain.ssh"

local ROOT_A = ROOT .. "/consensus/A/"
local ROOT_B = ROOT .. "/consensus/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}

-- 1. local wins by prefix reps
-- GEN_2: KEY1=15, KEY2=15
-- Before fork: KEY2 likes seed → KEY2 loses reps → KEY1 > KEY2
-- A posts with KEY1 (higher), B posts with KEY2 (lower)
-- B sends to A → A's hook recvs from B → A wins
-- B's main is not a fast-forward of A's main (non-ff push)
-- payloads live outside the tree: no conflict, the loser is
-- APPLIED AFTER the winner (consensus decides order, not survival)
do
    print("==> Test 1: local wins by prefix reps")

    TEST "A creates chain + seeds"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#cons-a' init file " .. GEN_2,
    }
    local seed_a = exec {
        cmd = EXE_A .. " --now=1100 chain '#cons-a' post inline 'seed\n' --sign " .. KEY1,
    }

    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    local like_a = exec {
        cmd = EXE_A .. " --now=1200 chain '#cons-a' like 1000 action " .. seed_a .. " --sign " .. KEY2,
    }

    TEST "B clones cons-a"
    exec {
        cmd = EXE_B .. " chains add '#cons-a' clone " .. ROOT_A .. "/chains/#cons-a/",
    }

    TEST "A posts alpha with KEY1 (higher prefix reps)"
    local alpha = exec {
        cmd = EXE_A .. " --now=2000 chain '#cons-a' post inline 'alpha\n' --sign " .. KEY1,
    }

    TEST "B posts beta with KEY2 (lower prefix reps)"
    local beta = exec {
        cmd = EXE_B .. " --now=2000 chain '#cons-a' post inline 'beta\n' --sign " .. KEY2,
    }

    TEST "B sends to A, non-ff (A wins by prefix reps)"
    exec {
        cmd = EXE_B .. " --now=3000 chain '#cons-a' sync send " .. ROOT_A .. "/chains/#cons-a/",
    }

    TEST "A's order: alpha before beta"
    do
        local O = ORDER(EXE_A, "#cons-a")
        assert(#O == 4, "expected 4 entries, got " .. #O)
        assert(O[1] == seed_a, "seed should be first")
        assert(O[2] == like_a, "like should be second")
        assert(O[3] == alpha,  "alpha should win")
        assert(O[4] == beta,   "beta should lose")
    end

    TEST "A holds both payloads"
    local pa = exec {
        cmd = EXE_A .. " chain '#cons-a' get payload " .. alpha,
    }
    local pb = exec {
        cmd = EXE_A .. " chain '#cons-a' get payload " .. beta,
    }
    assert(pa == "alpha", "alpha payload missing")
    assert(pb == "beta", "beta payload missing")
end

-- 2. remote wins by prefix reps
-- Same setup, but A posts with KEY2 (lower), B posts with KEY1 (higher)
-- A recvs B → B wins
do
    print("==> Test 2: remote wins by prefix reps")

    TEST "A creates chain + seeds"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#cons-b' init file " .. GEN_2,
    }
    local seed_b = exec {
        cmd = EXE_A .. " --now=1100 chain '#cons-b' post inline 'seed\n' --sign " .. KEY1,
    }

    TEST "KEY2 likes seed (loses reps, KEY1 > KEY2 at fork)"
    local like_b = exec {
        cmd = EXE_A .. " --now=1200 chain '#cons-b' like 1000 action " .. seed_b .. " --sign " .. KEY2,
    }

    TEST "B clones cons-b"
    exec {
        cmd = EXE_B .. " chains add '#cons-b' clone " .. ROOT_A .. "/chains/#cons-b/",
    }

    TEST "A posts alpha with KEY2 (lower prefix reps)"
    local alpha = exec {
        cmd = EXE_A .. " --now=2000 chain '#cons-b' post inline 'alpha\n' --sign " .. KEY2,
    }

    TEST "B posts beta with KEY1 (higher prefix reps)"
    local beta = exec {
        cmd = EXE_B .. " --now=2000 chain '#cons-b' post inline 'beta\n' --sign " .. KEY1,
    }

    TEST "A recvs from B (B wins by prefix reps)"
    local out = exec {
        cmd = EXE_A .. " --now=3000 chain '#cons-b' sync recv " .. ROOT_B .. "/chains/#cons-b/",
    }
    assert(not out:match("voided"), "loser applies cleanly: " .. out)

    TEST "A's order: beta before alpha"
    do
        local O = ORDER(EXE_A, "#cons-b")
        assert(#O == 4, "expected 4 entries, got " .. #O)
        assert(O[1] == seed_b, "seed should be first")
        assert(O[2] == like_b, "like should be second")
        assert(O[3] == beta,   "beta should win")
        assert(O[4] == alpha,  "alpha should lose")
    end

    TEST "A holds both payloads"
    local pa = exec {
        cmd = EXE_A .. " chain '#cons-b' get payload " .. alpha,
    }
    local pb = exec {
        cmd = EXE_A .. " chain '#cons-b' get payload " .. beta,
    }
    assert(pa == "alpha", "alpha payload missing")
    assert(pb == "beta", "beta payload missing")
end

-- 3. loser invalidated by winner context
-- GEN_4: KEY1..KEY4 = 12500 each
-- Remote: KEY1,KEY2,KEY3 each dislike KEY4 author by 4500
--   → KEY4 = 12500 - 3*4050 = 350 < cost
-- Local: KEY4 posts P1, KEY2 posts P2
-- Remote wins (37500 > 25000)
-- Loser replay: P1 by KEY4 fails → P2 by KEY2 also voided (cascade)
do
    print("==> Test 3: loser invalidated by winner context")

    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#cons-c' init file " .. GEN_4,
    }

    TEST "B clones cons-c"
    exec {
        cmd = EXE_B .. " chains add '#cons-c' clone " .. ROOT_A .. "/chains/#cons-c/",
    }

    TEST "B: KEY1 dislikes KEY4 author by 4500"
    local X1 = exec {
        cmd = EXE_B .. " --now=2000 chain '#cons-c' dislike 4500 author '" .. PUB4 .. "' --sign " .. KEY1,
    }

    TEST "B: KEY2 dislikes KEY4 author by 4500"
    local X2 = exec {
        cmd = EXE_B .. " --now=2000 chain '#cons-c' dislike 4500 author '" .. PUB4 .. "' --sign " .. KEY2,
    }

    TEST "B: KEY3 dislikes KEY4 author by 4500"
    local X3 = exec {
        cmd = EXE_B .. " --now=2000 chain '#cons-c' dislike 4500 author '" .. PUB4 .. "' --sign " .. KEY3,
    }

    TEST "A: KEY2 posts P1 (survives)"
    local P1 = exec {
        cmd = EXE_A .. " --now=2000 chain '#cons-c' post inline 'P1\n' --sign " .. KEY2,
    }

    TEST "A: KEY4 posts P2 (fails in winner context)"
    local P2 = exec {
        cmd = EXE_A .. " --now=2100 chain '#cons-c' post inline 'P2\n' --sign " .. KEY4,
    }

    TEST "A: KEY2 posts P3 (valid but voided by cascade)"
    local P3 = exec {
        cmd = EXE_A .. " --now=2200 chain '#cons-c' post inline 'P3\n' --sign " .. KEY2,
    }

    TEST "order before merge: P1, P2, P3 present"
    do
        local O, S = ORDER(EXE_A, "#cons-c")
        assert(#O == 3, "expected 3 entries, got " .. #O)
        assert(S[P1], "P1 should be in order")
        assert(S[P2], "P2 should be in order")
        assert(S[P3], "P3 should be in order")
    end

    TEST "A recvs from B (B wins, P2+P3 voided, P1 survives)"
    local out = exec {
        cmd = EXE_A .. " --now=3000 chain '#cons-c' sync recv " .. ROOT_B .. "/chains/#cons-c/",
    }
    local voided = 0
    for _ in out:gmatch("voided") do voided = voided + 1 end
    assert(voided == 2, "expected 2 voided, got " .. voided)

    TEST "A's snapshot has 1 post (P1 survived)"
    local acts = STATE(ROOT_A .. "/chains/#cons-c/").actions
    local n = 0
    for _, v in pairs(acts) do
        if v.action == 'post' then n = n + 1 end
    end
    assert(n == 1, "expected 1 post (P1), got " .. n)

    TEST "A order after merge: X1,X2,X3,P1 present; P2,P3 revoked"
    do
        local O, S = ORDER(EXE_A, "#cons-c")
        assert(#O == 4, "expected 4 entries, got " .. #O)
        assert(S[X1], "X1 should be in order")
        assert(S[X2], "X2 should be in order")
        assert(S[X3], "X3 should be in order")
        assert(S[P1], "P1 should survive in order")
        assert(not S[P2], "P2 should be revoked from order")
        assert(not S[P3], "P3 should be revoked from order")
    end

    TEST "B recvs from A"
    exec {
        cmd = EXE_B .. " --now=3000 chain '#cons-c' sync recv " .. ROOT_A .. "/chains/#cons-c/",
    }

    TEST "B order matches A"
    do
        local OA = ORDER(EXE_A, "#cons-c")
        local OB = ORDER(EXE_B, "#cons-c")
        assert(#OA == #OB, "length mismatch: A=" .. #OA .. " B=" .. #OB)
        for i = 1, #OA do
            assert(OA[i] == OB[i], "order mismatch at " .. i)
        end
    end
end

-- 4. nested cascade (fails under flat replay, passes under recursive)
-- GEN_4: KEY1..KEY4 = 12500 each.
-- A side (inner winner): KEY1+KEY2+KEY3 dislike KEY4 by 4500 (sum 37500).
-- B side (inner loser):  KEY4 posts P_c (sum 12500).
-- A recvs B → inner merge M1 on A. A wins. P_c voided.
-- C clones A (gets M1). C's replay_remote walks com..A_tip,
--   which contains M1.
-- Flat: P_c may be applied before the dislikes → P_c survives.
-- Recursive: winner-first at M1 → dislikes apply first → P_c voided.
do
    print("==> Test 4: nested cascade")

    local ROOT_C = ROOT .. "/consensus/C/"
    local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C
    exec {
        cmd = "mkdir -p " .. ROOT_C,
    }

    -- A: G
    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#cons-d' init file " .. GEN_4,
    }

    -- A: G
    -- B: G
    TEST "B clones cons-d"
    exec {
        cmd = EXE_B .. " chains add '#cons-d' clone " .. ROOT_A .. "/chains/#cons-d/",
    }

    -- A: G -- D1
    -- B: G
    -- K4: 12500 - 4050 = 8450
    TEST "A: KEY1 dislikes KEY4 author by 4500"
    exec {
        cmd = EXE_A .. " --now=2000 chain '#cons-d' dislike 4500 author '" .. PUB4 .. "' --sign " .. KEY1,
    }

    -- A: G -- D1 -- D2
    -- B: G
    -- K4: 8450 - 4050 = 4400
    TEST "A: KEY2 dislikes KEY4 author by 4500"
    exec {
        cmd = EXE_A .. " --now=2000 chain '#cons-d' dislike 4500 author '" .. PUB4 .. "' --sign " .. KEY2,
    }

    -- A: G -- D1 -- D2 -- D3
    -- B: G
    -- K4: 4400 - 4050 = 350 < cost
    TEST "A: KEY3 dislikes KEY4 author by 4500"
    exec {
        cmd = EXE_A .. " --now=2000 chain '#cons-d' dislike 4500 author '" .. PUB4 .. "' --sign " .. KEY3,
    }

    -- A: G -- D1 -- D2 -- D3
    -- B: G -- P_c
    TEST "B: KEY4 posts P_c"
    local P_c = exec {
        cmd = EXE_B .. " --now=2100 chain '#cons-d' post inline 'P_c\n' --sign " .. KEY4,
    }

    --         D1 -- D2 -- D3 --\
    --        /                  M -- S
    -- A:    G                   /
    --        \                 /
    --         P_c* -----------/      (* voided by cascade)
    --
    -- B: G -- P_c
    TEST "A recvs B (inner merge; A wins; P_c voided on A)"
    exec {
        cmd = EXE_A .. " --now=3000 chain '#cons-d' sync recv " .. ROOT_B .. "/chains/#cons-d/",
    }

    -- C: (same DAG as A) — replay walks com..A_tip, encounters M
    --   Flat:      interleaves D1,D2,D3,P_c → P_c may survive
    --   Recursive: winner-first at M → D1,D2,D3 first → P_c voided
    TEST "C clones from A (replay walks range containing inner merge)"
    exec {
        cmd = EXE_C .. " chains add '#cons-d' clone " .. ROOT_A .. "/chains/#cons-d/",
    }

    TEST "C's snapshot should not contain P_c"
    local acts = STATE(ROOT_C .. "/chains/#cons-d/").actions
    assert (
        acts[P_c] == nil,
        "P_c should be voided by nested cascade"
    )

    TEST "C order matches A"
    local OA = ORDER(EXE_A, "#cons-d")
    local OC = ORDER(EXE_C, "#cons-d")
    assert(#OA == #OC, "length mismatch: A=" .. #OA .. " C=" .. #OC)
    for i = 1, #OA do
        assert(OA[i] == OC[i], "order mismatch at " .. i)
    end
end

print("<== ALL PASSED")
