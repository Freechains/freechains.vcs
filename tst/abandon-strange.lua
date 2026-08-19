#!/usr/bin/env lua5.4

-- Strange abandon cases (plan 260819-abandon, phases 2 and 4).
--
-- 1. Crossing a merge refuses, in BOTH forms: the sibling branch
--    would be collateral (and would resurrect on recv anyway)
--
--            S[K1]           <-- abandon --keep S refuses too
--            /   \
--       a1[K1]   b1[K2]      <-- abandon a1 refuses (crosses M)
--          |       |
--       a2[K1]   b2[K2]
--            \   /
--              M             <-- A's HEAD after recv
--
-- 2. Resurrection: my OWN abandoned action returns on the next
--    recv, once it was sent (durable abandon = unsent only)
--
-- 3. Landing ON a merge is fine (the README `day 1` rewind)
--
-- 4. Beg-attach like: a merge WITH an aid is abandonable
--
-- 5. `--keep` edges: linear drop; tip no-op; beg invalid

require "tests"

local CHAIN  = "#abandon-strange"
local ROOT_A = ROOT .. "/abandon-strange/A/"
local ROOT_B = ROOT .. "/abandon-strange/B/"
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
    cmd = EXE_A .. " --now=1000 chains add '" .. CHAIN .. "' init file " .. GEN_2,
}
local seed = exec {
    cmd = EXE_A .. " --now=1100 chain '" .. CHAIN .. "' post inline 'seed\n' --file s.txt --sign " .. KEY1,
}
exec {
    cmd = EXE_B .. " chains add '" .. CHAIN .. "' clone " .. DIR_A,
}

-- diverge: A posts a1 a2, B posts b1 b2
TEST "A and B diverge"
local a1 = exec {
    cmd = EXE_A .. " --now=1200 chain '" .. CHAIN .. "' post inline 'a1\n' --file a1.txt --sign " .. KEY1,
}
local a2 = exec {
    cmd = EXE_A .. " --now=1300 chain '" .. CHAIN .. "' post inline 'a2\n' --file a2.txt --sign " .. KEY1,
}
local b1 = exec {
    cmd = EXE_B .. " --now=1200 chain '" .. CHAIN .. "' post inline 'b1\n' --file b1.txt --sign " .. KEY2,
}
local b2 = exec {
    cmd = EXE_B .. " --now=1300 chain '" .. CHAIN .. "' post inline 'b2\n' --file b2.txt --sign " .. KEY2,
}

-- A merges B: HEAD is the sync merge M
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

-- 1. crossing a merge refuses, in both forms; nothing is mutated
do
    TEST "abandon a1 refuses: range crosses the sync merge"
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon " .. a1,
        err = "ERROR : chain abandon : unexpected merge",
    }

    TEST "abandon --keep seed refuses too (both forms linear)"
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon --keep " .. seed,
        err = "ERROR : chain abandon : unexpected merge",
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
do
    TEST "A posts c1; B recvs it; A abandons c1; A recvs: c1 is back"
    local c1 = exec {
        cmd = EXE_A .. " --now=1600 chain '" .. CHAIN .. "' post inline 'c1\n' --file c1.txt --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1700 chain '" .. CHAIN .. "' sync recv " .. DIR_A,
    }
    exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon " .. c1,
    }
    local _, S0 = ORDER(EXE_A, CHAIN)
    assert(not S0[c1], "c1 gone locally")
    exec {
        cmd = EXE_A .. " --now=1800 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
    }
    local _, S1 = ORDER(EXE_A, CHAIN)
    assert(S1[c1], "c1 is back: sent abandon = illusory")
end

-- 3. landing ON a merge: abandon the first action after a sync merge
do
    TEST "abandon d1 lands ON the sync merge below it"
    -- fresh divergence so A's next recv really merges
    exec {
        cmd = EXE_A .. " --now=1900 chain '" .. CHAIN .. "' post inline 'x1\n' --file x1.txt --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1900 chain '" .. CHAIN .. "' post inline 'y1\n' --file y1.txt --sign " .. KEY2,
    }
    exec {
        cmd = EXE_A .. " --now=1950 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
    }
    local d1 = exec {
        cmd = EXE_A .. " --now=2000 chain '" .. CHAIN .. "' post inline 'd1\n' --file d1.txt --sign " .. KEY1,
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
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon " .. d1,
    }
    assert(out == d1, "only d1 dropped: " .. out)
    local head = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(head == merge, "HEAD should be the merge itself")

    TEST "chain still works on top of the merge"
    exec {
        cmd = EXE_A .. " --now=2050 chain '" .. CHAIN .. "' post inline 'd2\n' --file d2.txt --sign " .. KEY1,
    }
end

-- 4. a beg-attach like is a merge WITH an aid: abandonable
do
    TEST "beg + like: the like commit is a 2-parent action"
    local beg = exec {
        cmd = EXE_A .. " --now=2100 chain '" .. CHAIN .. "' post inline 'beg\n' --file beg.txt --beg --sign " .. KEY3,
    }
    local like = exec {
        cmd = EXE_A .. " --now=2200 chain '" .. CHAIN .. "' like 1000 action " .. beg .. " --sign " .. KEY1,
    }
    local ps = exec {
        cmd = "git -C " .. DIR_A .. " rev-list --parents -n 1 HEAD",
    }
    local n = select(2, ps:gsub("%x+", "")) - 1
    assert(n == 2, "like should be a 2-parent commit, got " .. n)

    TEST "abandon the like drops it AND the beg post"
    local before = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD~1",
    }
    local out = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon " .. like,
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
do
    TEST "--keep the tip itself is a no-op"
    local e1 = exec {
        cmd = EXE_A .. " --now=2300 chain '" .. CHAIN .. "' post inline 'e1\n' --file e1.txt --sign " .. KEY1,
    }
    local head = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    local out = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon --keep " .. e1,
    }
    assert(out == "", "nothing dropped: " .. out)
    local now = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(now == head, "HEAD should not move")

    TEST "--keep drops the linear stretch above the survivor"
    local e2 = exec {
        cmd = EXE_A .. " --now=2350 chain '" .. CHAIN .. "' post inline 'e2\n' --file e2.txt --sign " .. KEY1,
    }
    local out2 = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon --keep " .. e1,
    }
    assert(out2 == e2, "e2 dropped: " .. out2)
    local h2 = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(h2 == head, "HEAD should be back on e1")

    TEST "--keep on a beg is invalid (not in main)"
    local bg = exec {
        cmd = EXE_A .. " --now=2400 chain '" .. CHAIN .. "' post inline 'bg\n' --file bg.txt --beg --sign " .. KEY4,
    }
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon --keep " .. bg,
        err = "ERROR : chain abandon : invalid action",
    }
    -- the beg ref must survive the refused --keep
    exec {
        cmd = "git -C " .. DIR_A .. " show-ref --verify --quiet refs/begs/beg-" .. bg,
    }

    TEST "default form still abandons the beg"
    local out2 = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon " .. bg,
    }
    assert(out2 == bg, "beg dropped alone: " .. out2)
end

-- 6. P1: refuse when the landing snapshot is gone (simulates prune P3
-- by hiding the landing commit's snapshot). Inert until P3 exists, so
-- the test manufactures the pruned state directly.
do
    TEST "abandon refuses when the landing snapshot is pruned"
    local f1 = exec {
        cmd = EXE_A .. " --now=2500 chain '" .. CHAIN .. "' post inline 'f1\n' --file f1.txt --sign " .. KEY1,
    }
    local f2 = exec {
        cmd = EXE_A .. " --now=2600 chain '" .. CHAIN .. "' post inline 'f2\n' --file f2.txt --sign " .. KEY1,
    }
    -- default form lands on f1 (f2's parent); hide f1's snapshot
    local snap = DIR_A .. ".git/states/" .. CID(DIR_A, f1) .. ".lua"
    exec { cmd = "mv " .. snap .. " " .. snap .. ".off" }

    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon " .. f2,
        err = "ERROR : chain abandon : pruned state",
    }
    -- --keep form lands ON f1 too: same refusal
    FAIL {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon --keep " .. f1,
        err = "ERROR : chain abandon : pruned state",
    }

    TEST "the refusal mutated nothing (f2 payload, order intact)"
    exec {
        cmd = "git -C " .. DIR_A .. " rev-parse refs/payloads/" .. f2,
    }
    local _, S = ORDER(EXE_A, CHAIN)
    assert(S[f1] and S[f2], "f1 f2 still in the order")

    TEST "with the snapshot restored, the same abandon works"
    exec { cmd = "mv " .. snap .. ".off " .. snap }
    local out = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon " .. f2,
    }
    assert(out == f2, "f2 dropped: " .. out)
end

print("<== ALL PASSED")
