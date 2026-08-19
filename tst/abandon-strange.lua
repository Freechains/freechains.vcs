#!/usr/bin/env lua5.4

-- Strange abandon cases (plan 260819-abandon, phase 2).
-- These tests DOCUMENT today's behavior to settle the design:
-- each assert states what happens now, not what should happen.
--
-- 1. Collateral: abandon inside a merged fork drops the sibling branch
--
--            S[K1]
--            /   \
--       a1[K1]   b1[K2]
--          |       |
--       a2[K1]   b2[K2]
--            \   /
--              M               <-- A's HEAD after recv
--
-- `abandon a1` at A: lands on S, drops a1 a2 AND b1 b2 M.
--
-- 2. Resurrection: the dropped received branch returns on next recv
--
-- 3. Resurrection of my OWN action, once it was sent
--
-- 4. Landing ON a merge is fine (the README `day 1` rewind)
--
-- 5. Beg-attach like: a merge WITH an aid is abandonable

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

-- 1. collateral: abandon a1 drops the b's and M too
do
    TEST "abandon a1 drops sibling branch b1 b2 (collateral)"
    local out = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' abandon " .. a1,
    }
    local S = {}
    local n = 0
    for h in out:gmatch("[^\n]+") do
        S[h] = true
        n = n + 1
    end
    -- M has no aid, so 4 actions are listed: a1 a2 b1 b2
    assert(n == 4, "expected 4 dropped, got " .. n)
    assert(S[a1] and S[a2], "a1 a2 dropped")
    assert(S[b1] and S[b2], "b1 b2 dropped: COLLATERAL")

    TEST "HEAD lands on the fork point S"
    local head = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse HEAD",
    }
    assert(head == CID(DIR_A, seed), "HEAD should be seed")

    TEST "collateral payload anchors are gone too"
    local _, code = exec { err=false, stderr=false,
        cmd = "git -C " .. DIR_A .. " rev-parse refs/payloads/" .. b1,
    }
    assert(code ~= 0, "b1 payload ref should be gone")
end

-- 2. the received branch resurrects on the next recv
do
    TEST "recv B again: b1 b2 return (abandon of received = illusory)"
    exec {
        cmd = EXE_A .. " --now=1500 chain '" .. CHAIN .. "' sync recv " .. DIR_B,
    }
    local _, S = ORDER(EXE_A, CHAIN)
    assert(S[b1] and S[b2], "b1 b2 should be back")
    assert(not (S[a1] or S[a2]), "a1 a2 stay gone (never sent)")

    TEST "resurrected payload anchors are restored"
    exec {
        cmd = "git -C " .. DIR_A .. " rev-parse refs/payloads/" .. b1,
    }
    local v = exec {
        cmd = EXE_A .. " chain '" .. CHAIN .. "' get payload " .. b1,
    }
    assert(v == "b1", "b1 payload should read: " .. v)
end

-- 3. my OWN action resurrects too, once it was sent
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

-- 4. landing ON a merge: abandon the first action after a sync merge
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

-- 5. a beg-attach like is a merge WITH an aid: abandonable
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

print("<== ALL PASSED")
