#!/usr/bin/env lua5.4

-- Strange discard cases (plan 260819-discard, phases 2 and 4).
--
-- Diagrams: the LEFT branch is a merge's first parent, the consensus
-- winner. K2 wins every fork here: K1 paid for the seed.
--
-- 1. Cutting a merge refuses, in BOTH forms: a branch on its other
--    side would be left (and would resurrect on recv anyway)
--
--            S[K1]
--            /   \
--       b1[K2]   a1[K1]      <-- discard a1 refuses (cuts M)
--          |       |
--       b2[K2]   a2[K1]      <-- discard --keep b2 refuses too
--            \   /
--              M             <-- A's HEAD after recv
--
-- 2. Resurrection: my OWN discarded action returns on the next
--    recv, once it was sent (durable discard = unsent only)
--
-- 3. Landing ON a merge is fine (the README `day 1` rewind)
--
-- 4. Beg-attach like: a merge WITH an aid is discardable
--
-- 5. `--keep` edges: linear drop; tip no-op; beg invalid

require "tests"

local CHAIN  = "/discard-strange"
local ROOT_A = ROOT .. "/discard-strange/A/"
local ROOT_B = ROOT .. "/discard-strange/B/"
local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local DIR_A  = ROOT_A .. "chains/" .. CHAIN .. "/"
local DIR_B  = ROOT_B .. "chains/" .. CHAIN .. "/"

exec {
    cmd = "mkdir -p " .. ROOT_A .. " " .. ROOT_B,
}

-- common base: S, cloned by B
TEST "A creates chain + seed; B clones"
exec {
    cmd = EXE_A .. " --now=1000 chains add '" .. CHAIN .. "' init " .. GEN_2,
}
local seed = exec {
    cmd = EXE_A .. " --now=1100 chain '" .. CHAIN .. "' post inline 'seed\n' --sign " .. KEY1,
}
exec {
    cmd = EXE_B .. " chains add '" .. CHAIN .. "' clone " .. DIR_A,
}

-- diverge: A posts a1 a2, B posts b1 b2
--
--   A:  S -- a1 -- a2            B:  S -- b1 -- b2
TEST "A and B diverge"
local a1 = exec {
    cmd = EXE_A .. " --now=1200 chain '" .. CHAIN .. "' post inline 'a1\n' --sign " .. KEY1,
}
local a2 = exec {
    cmd = EXE_A .. " --now=1300 chain '" .. CHAIN .. "' post inline 'a2\n' --sign " .. KEY1,
}
local b1 = exec {
    cmd = EXE_B .. " --now=1200 chain '" .. CHAIN .. "' post inline 'b1\n' --sign " .. KEY2,
}
local b2 = exec {
    cmd = EXE_B .. " --now=1300 chain '" .. CHAIN .. "' post inline 'b2\n' --sign " .. KEY2,
}

-- A merges B: HEAD is the sync merge M (B wins: b2 is M^1)
--
--   A:       S               B:  S -- b1 -- b2
--          /   \
--        b1     a1
--         |     |
--        b2     a2
--          \   /
--            M
TEST "A recvs B: nested fork merged"
exec {
    cmd = EXE_A .. " --now=1400 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
}
local M = exec {
    cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
}
do
    local ps = exec {
        cmd = "git -C " .. DIR_A .. " rev-list --parents -n 1 HEAD",
    }
    local n = select(2, ps:gsub("%x+", "")) - 1
    assert(n == 2, "HEAD should be a 2-parent merge, got " .. n)
end

-- 1. cutting a merge refuses, in both forms; nothing is mutated
do
    TEST "discard a1 refuses: it cuts the sync merge (b-side stays)"
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard " .. a1,
        err = "ERROR : chain discard : unexpected merge",
    }

    TEST "discard --keep b2 refuses too: a1 a2 were not built on it"
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --keep " .. b2,
        err = "ERROR : chain discard : unexpected merge",
    }

    TEST "the refusals mutated nothing"
    local head = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(head == M, "HEAD should still be the merge")
    exec {
        cmd = "git -C " .. DIR_A .. " rev-parse refs/payloads/" .. b1,
    }
    local _, S = ORDER(EXE_A, CHAIN)
    assert(S[a1] and S[a2] and S[b1] and S[b2], "order intact")
end

-- 2. my OWN action resurrects, once it was sent
--
--   A posts c1       B recvs (FF)     A discards c1    A recvs (FF)
--   A: M -- c1       B: M -- c1       A: M             A: M -- c1
do
    TEST "A posts c1; B recvs it; A discards c1; A recvs: c1 is back"
    local c1 = exec {
        cmd = EXE_A .. " --now=1600 chain '" .. CHAIN .. "' post inline 'c1\n' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1700 chain '" .. CHAIN .. "' sync recv " .. DIR_A,
    }
    exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard " .. c1,
    }
    local _, S0 = ORDER(EXE_A, CHAIN)
    assert(not S0[c1], "c1 gone locally")
    exec {
        cmd = EXE_A .. " --now=1800 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
    }
    local _, S1 = ORDER(EXE_A, CHAIN)
    assert(S1[c1], "c1 is back: sent discard = illusory")
end

-- 3. landing ON a merge: discard the first action after a sync merge
--
--          c1                         c1                    c1
--         /  \                       /  \                  /  \
--   y1[K2]    x1[K1]               y1    x1              y1    x1
--         \  /           ->          \  /        ->        \  /
--          M2                         M2  <-- HEAD          M2
--          |                                                |
--        d1[K1]  <-- discard d1                           d2[K1]
do
    TEST "discard d1 lands ON the sync merge below it"
    -- fresh divergence so A's next recv really merges
    exec {
        cmd = EXE_A .. " --now=1900 chain '" .. CHAIN .. "' post inline 'x1\n' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1900 chain '" .. CHAIN .. "' post inline 'y1\n' --sign " .. KEY2,
    }
    exec {
        cmd = EXE_A .. " --now=1950 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
    }
    local d1 = exec {
        cmd = EXE_A .. " --now=2000 chain '" .. CHAIN .. "' post inline 'd1\n' --sign " .. KEY1,
    }
    local merge = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD~1",
    }
    do
        local ps = exec {
            cmd = "git -C " .. DIR_A .. " rev-list --parents -n 1 " .. merge,
        }
        local n = select(2, ps:gsub("%x+", "")) - 1
        assert(n == 2, "d1's parent should be a merge, got " .. n)
    end
    local out = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard " .. d1,
    }
    assert(out == d1, "only d1 dropped: " .. out)
    local head = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(head == merge, "HEAD should be the merge itself")

    TEST "chain still works on top of the merge"
    exec {
        cmd = EXE_A .. " --now=2050 chain '" .. CHAIN .. "' post inline 'd2\n' --sign " .. KEY1,
    }
end

-- 4. a beg-attach like is a merge WITH an aid: discardable
--
--        d2                           d2  <-- HEAD
--        |  \
--        |   beg[K3]     ->
--        |  /
--      like[K1]  <-- discard like
do
    TEST "beg + like: the like commit is a 2-parent action"
    local beg = exec {
        cmd = EXE_A .. " --now=2100 chain '" .. CHAIN .. "' post inline 'beg\n' --beg --sign " .. KEY3,
    }
    local like = exec {
        cmd = EXE_A .. " --now=2200 chain '" .. CHAIN .. "' like 1000 action " .. beg .. " --sign " .. KEY1,
    }
    local ps = exec {
        cmd = "git -C " .. DIR_A .. " rev-list --parents -n 1 HEAD",
    }
    local n = select(2, ps:gsub("%x+", "")) - 1
    assert(n == 2, "like should be a 2-parent commit, got " .. n)

    TEST "discard the like drops it AND the beg post"
    local before = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD~1",
    }
    local out = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard " .. like,
    }
    local S = {}
    for h in out:gmatch("[^\n]+") do
        S[h] = true
    end
    assert(S[like] and S[beg], "like and beg dropped: " .. out)
    local head = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(head == before, "HEAD should be the pre-like tip")
end

-- 5. --keep edge cases
--
--   d2 -- e1           d2 -- e1 -- e2           d2 -- e1 .. bg[K4]
--   --keep e1: no-op   --keep e1: drops e2      --keep bg: invalid (a beg)
--                                               discard bg: drops the beg
do
    TEST "--keep the tip itself is a no-op"
    local e1 = exec {
        cmd = EXE_A .. " --now=2300 chain '" .. CHAIN .. "' post inline 'e1\n' --sign " .. KEY1,
    }
    local head = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    local out = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --keep " .. e1,
    }
    assert(out == "", "nothing dropped: " .. out)
    local now = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(now == head, "HEAD should not move")

    TEST "--keep drops the linear stretch above the survivor"
    local e2 = exec {
        cmd = EXE_A .. " --now=2350 chain '" .. CHAIN .. "' post inline 'e2\n' --sign " .. KEY1,
    }
    local out2 = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --keep " .. e1,
    }
    assert(out2 == e2, "e2 dropped: " .. out2)
    local h2 = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(h2 == head, "HEAD should be back on e1")

    TEST "--keep on a beg is invalid (not in main)"
    local bg = exec {
        cmd = EXE_A .. " --now=2400 chain '" .. CHAIN .. "' post inline 'bg\n' --beg --sign " .. KEY4,
    }
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --keep " .. bg,
        err = "ERROR : chain discard : invalid action",
    }
    -- the beg ref must survive the refused --keep
    exec {
        cmd = "git -C " .. DIR_A .. " show-ref --verify --quiet refs/begs/beg-" .. bg,
    }

    TEST "default form still discards the beg"
    local out2 = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard " .. bg,
    }
    assert(out2 == bg, "beg dropped alone: " .. out2)
end

-- 6. `--merge` drops a branch from its FIRST action: the same point
--    section 1 refused (plan 260921-discard); last, since it drops
--    everything above M
--
--   A, before:                        B, before:
--            S                                 S
--          /   \                             /   \
--        b1     a1  <-- --merge a1          b1     a1  <-- --merge a1
--         |     |                            |     |
--        b2     a2  <-- (a2 refuses)        b2     a2
--          \   /                               \   /
--            M                                   M
--            |                                   |
--           c1                                  c1
--          /  \                                 |
--        y1    x1                               y1
--          \  /
--           M2 -- d2 -- e1
--
--   A, after:  S -- b1 -- b2          B, after:  S -- b1 -- b2
--
--   discard drops the cid and what was built on it, nothing else:
--    - `--merge a1`: a1 a2 M and above go, b2 is the one tip left
--    - `--merge a2`: a1 and b2 would both be tips: partial branch
--    - `--merge e1`: cuts no merge: expected merge
--    - `--keep b2`: cuts M, and `--keep --merge` is no way out:
--      `--merge` names the first of a branch, which no `--keep` can
do
    TEST "discard --merge a2 refuses: a1 would be lost"
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --merge " .. a2,
        err = "ERROR : chain discard : partial branch",
    }

    TEST "discard --merge on a plain sequence refuses"
    do
        local e1 = exec {
            cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
        }
        FAIL {
            cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --merge " .. e1,
            err = "ERROR : chain discard : expected merge",
        }
    end

    TEST "discard --keep --merge is not a form"
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --keep --merge " .. b2,
    }

    TEST "the refusals mutated nothing (section 6)"
    do
        local head = exec {
            cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
        }
        assert(head ~= b2, "the refusals should not move HEAD")
        local _, S = ORDER(EXE_A, CHAIN)
        assert(S[a1] and S[a2] and S[b1] and S[b2], "order intact")
    end

    TEST "discard --merge a1 drops the WHOLE merged-in side, lands on b2"
    local out = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --merge " .. a1,
    }
    local T = {}
    for h in out:gmatch("[^\n]+") do
        T[h] = true
    end
    assert(T[a1] and T[a2], "a1 a2 listed: " .. out)
    assert(not (T[b1] or T[b2]), "the other side stays: " .. out)
    assert(not T[M], "the sync merge is not an action: " .. out)
    local head = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(head == b2, "HEAD should be b2")
    local _, S = ORDER(EXE_A, CHAIN)
    assert(S[seed] and S[b1] and S[b2], "the other side intact")
    assert(not (S[a1] or S[a2]), "the dropped branch out of the order")
    local _, code = exec { err=false, stderr=false,
        cmd = "git -C " .. DIR_A .. " rev-parse refs/payloads/" .. a1,
    }
    assert(code ~= 0, "payload ref should be gone: " .. a1)
    exec {
        cmd = "git -C " .. DIR_A .. " rev-parse refs/payloads/" .. b1,
    }

    TEST "B: discard --keep b2 refuses; --merge a1 lands on b2 too"
    FAIL {
        cmd = EXE_B .. " chain '" .. CHAIN .. "' discard --keep " .. b2,
        err = "ERROR : chain discard : unexpected merge",
    }
    local out = exec {
        cmd = EXE_B .. " chain '" .. CHAIN .. "' discard --merge " .. a1,
    }
    local T = {}
    for h in out:gmatch("[^\n]+") do
        T[h] = true
    end
    assert(T[a1] and T[a2], "a1 a2 listed: " .. out)
    assert(not (T[b1] or T[b2] or T[M]), "b1 b2 M not listed: " .. out)
    local head = exec {
        cmd = "git -C " .. DIR_B .. " rev-parse HEAD",
    }
    assert(head == b2, "HEAD should be b2")
    local _, S = ORDER(EXE_B, CHAIN)
    assert(S[seed] and S[b1] and S[b2], "B's branch intact")
    assert(not (S[a1] or S[a2]), "A's branch out of the order")
end

-- 7. Refutation, the full scenario behind `--merge`: an attacker
--    extends a legit branch, peers merge it and keep posting
--
--   F: K1 (sole pioneer) welcomes K2 (honest) and K3 (attacker)
--
--   A:  F -- b1[K1]            B:  F -- a1[K2] -- a2[K3]    (a2: fake)
--
--   A recvs B (K1 wins: b1 is M^1) and keeps posting on top:
--
--              F
--            /   \
--       b1[K1]   a1[K2]
--          |       |
--          |     a2[K3]
--            \   /
--              M -- c1[K1]
--
--   discovery: `--merge a2` refuses (a1 would be lost), `--merge a1`
--   drops the branch and what was built on it:
--
--   A:  F -- b1
--
--   A dislikes K3, then recvs B again: replay takes a1, voids a2
--
--              F
--            /   \
--       b1[K1]   a1[K2]
--          |       |
--        D[K1]     |           (a2 voided: K3 cannot afford it after D)
--            \   /
--              M'
--
--   B recvs A: its own a2 is voided, both peers agree (c2: c1 reposted)
--
--   then the two remaining forms, one per peer, on M' -- c2:
--
--   A: `--keep F`: all above F was       B: `--merge b1`: the mirror of
--      built on F, M' goes whole:           `--merge a1`, b1 is the first
--      a plain sequence, no flag            of the OTHER branch
--
--      F                                    F -- a1
do
    local CHAIN = "/discard-refute"
    local DIR_A = ROOT_A .. "chains/" .. CHAIN .. "/"
    local DIR_B = ROOT_B .. "chains/" .. CHAIN .. "/"

    TEST "refute: K1 welcomes K2 and K3; B clones; both diverge"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '" .. CHAIN .. "' init " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " --now=1100 chain '" .. CHAIN .. "' like 2000 member '" .. PUB2 .. "' --sign " .. KEY1,
    }
    local F = exec {
        cmd = EXE_A .. " --now=1200 chain '" .. CHAIN .. "' like 1000 member '" .. PUB3 .. "' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " chains add '" .. CHAIN .. "' clone " .. DIR_A,
    }
    local b1 = exec {
        cmd = EXE_A .. " --now=1300 chain '" .. CHAIN .. "' post inline 'b1\n' --sign " .. KEY1,
    }
    local a1 = exec {
        cmd = EXE_B .. " --now=1300 chain '" .. CHAIN .. "' post inline 'a1\n' --sign " .. KEY2,
    }
    local a2 = exec {
        cmd = EXE_B .. " --now=1400 chain '" .. CHAIN .. "' post inline 'a2 fake\n' --sign " .. KEY3,
    }

    TEST "refute: A merges the branch and keeps posting"
    exec {
        cmd = EXE_A .. " --now=1500 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
    }
    local c1 = exec {
        cmd = EXE_A .. " --now=1600 chain '" .. CHAIN .. "' post inline 'c1\n' --sign " .. KEY1,
    }
    do
        local _, S = ORDER(EXE_A, CHAIN)
        assert(S[b1] and S[a1] and S[a2] and S[c1], "all merged")
    end

    TEST "refute: cannot cut at a2, the branch goes from a1"
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --merge " .. a2,
        err = "ERROR : chain discard : partial branch",
    }
    exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --merge " .. a1,
    }
    do
        local head = exec {
            cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
        }
        assert(head == b1, "HEAD should be b1")
    end

    TEST "refute: A dislikes K3, recvs again: a1 is back, a2 is voided"
    local D = exec {
        cmd = EXE_A .. " --now=1700 chain '" .. CHAIN .. "' dislike 1000 member '" .. PUB3 .. "' --sign " .. KEY1,
    }
    exec { stderr=false,
        cmd = EXE_A .. " --now=1800 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
    }
    do
        local _, S = ORDER(EXE_A, CHAIN)
        assert(S[b1] and S[D], "the local branch stays")
        assert(S[a1], "a1 returns with no repost")
        assert(not S[a2], "a2 is voided")
        assert(not S[c1], "c1 sat on the fake: gone")
        -- the new merge takes a1, the last non-failing commit
        local p2 = exec {
            cmd = "git -C " .. DIR_A .. " rev-parse HEAD^2",
        }
        assert(p2 == a1, "merge should bring a1, got " .. p2)
    end

    TEST "refute: c1 is reposted on top"
    local c2 = exec {
        cmd = EXE_A .. " --now=1900 chain '" .. CHAIN .. "' post inline 'c1\n' --sign " .. KEY1,
    }
    assert(#c2 == 40 and c2 ~= c1, "a new post: " .. c2)

    TEST "refute: B recvs A: its a2 is voided, both peers agree"
    exec { stderr=false,
        cmd = EXE_B .. " --now=2000 chain '" .. CHAIN .. "' sync recv " .. DIR_A,
    }
    do
        local TA, _  = ORDER(EXE_A, CHAIN)
        local TB, SB = ORDER(EXE_B, CHAIN)
        assert(not SB[a2], "a2 is voided on B too")
        assert(SB[a1] and SB[b1] and SB[D] and SB[c2], "B holds the rest")
        assert(table.concat(TA, " ") == table.concat(TB, " "), "same order")
    end

    TEST "refute: A: --keep F needs no --merge, drops both branches"
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --merge " .. c2,
        err = "ERROR : chain discard : expected merge",
    }
    do
        local out = exec {
            cmd = EXE_A .. " chain '" .. CHAIN .. "' discard --keep " .. F,
        }
        local T = {}
        for h in out:gmatch("[^\n]+") do
            T[h] = true
        end
        assert(T[b1] and T[D] and T[a1] and T[c2], "both branches listed: " .. out)
        local head = exec {
            cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
        }
        assert(head == F, "HEAD should be F")
    end

    TEST "refute: B: --merge b1 drops the other branch, lands on a1"
    FAIL {
        cmd = EXE_B .. " chain '" .. CHAIN .. "' discard " .. b1,
        err = "ERROR : chain discard : unexpected merge",
    }
    do
        local out = exec {
            cmd = EXE_B .. " chain '" .. CHAIN .. "' discard --merge " .. b1,
        }
        local T = {}
        for h in out:gmatch("[^\n]+") do
            T[h] = true
        end
        assert(T[b1] and T[D] and T[c2], "b1 D c2 listed: " .. out)
        assert(not T[a1], "a1 stays: " .. out)
        local head = exec {
            cmd = "git -C " .. DIR_B .. " rev-parse HEAD",
        }
        assert(head == a1, "HEAD should be a1")
        local _, S = ORDER(EXE_B, CHAIN)
        assert(S[a1] and not (S[b1] or S[D] or S[c2]), "only a1's side")
    end
end

print("<== ALL PASSED")
