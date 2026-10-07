#!/usr/bin/env lua5.4

-- The fork winner must be a function of the DAG, not of the replay
-- path: peers at the SAME HEAD must list the SAME order.
-- Plan: .claude/plans/261006-bug-winner.md
--
-- Open chain, keys K1, K2, K3, every `--now` pinned:
--
--   * M3        D recv C              (E: FF, Z: fresh clone)
--   |\
--   | * c1[K3]  C: on M1
--   * |   M2    D recv A
--   |\ \
--   | |/
--   | * M1      A recv B
--   | |\
--   * | | a2[K2]  D: on a1
--   |/  |
--   *   | a1[K1]  A
--   |   * b1[K2]  B (concurrent)
--   |  /
--   * G
--
-- D (merger), E (FF from D at M2) and Z (clone at M3) share HEAD M3,
-- but each replays from a different floor:
--   - E: `oct` = M1 sits above the inner fork at a1, so G already
--     holds b1 (K2 = -500): a2's side loses, c1 first
--   - Z: `meet` climbs to `up` = a1 before deciding M1, so a1 lands
--     before b1, although b1 wins M1's tie
--
-- Every commit is deterministic (pinned dates, ed25519 signatures)
-- except the genesis nonce. `bug-winner.bundle` holds a genesis
-- whose nonce makes the cid ties fall the failing way, so A clones
-- it instead of `init`.
--
-- BW_INIT=<out.bundle>: search mode, A inits a fresh genesis, saves
-- it to <out.bundle> and the run reports AGREE/DIVERGE (no asserts).

require "tests"

local INIT = os.getenv("BW_INIT")

local BUNDLE = INIT or exec {
    cmd = "realpath bug-winner.bundle",
}

-- post cids for the bundled genesis: guard the fixture.
-- Merges are left out: their shape is what the fix decides
local GUARD = {
    a1 = "7caadff8e81d9ae63c11532f4ac582a87baef44a",
    b1 = "0f23a11f3918f91a734feba9ffe3d764a1b5dd1c",
    a2 = "e32928f62aa66e8935d44ad1a1c3e521d7403175",
}

local ROOT_A = ROOT .. "/bug-winner/A/"
local ROOT_B = ROOT .. "/bug-winner/B/"
local ROOT_C = ROOT .. "/bug-winner/C/"
local ROOT_D = ROOT .. "/bug-winner/D/"
local ROOT_E = ROOT .. "/bug-winner/E/"
local ROOT_Z = ROOT .. "/bug-winner/Z/"

local EXE_A = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C = ENV .. " ../src/freechains.lua --root " .. ROOT_C
local EXE_D = ENV .. " ../src/freechains.lua --root " .. ROOT_D
local EXE_E = ENV .. " ../src/freechains.lua --root " .. ROOT_E
local EXE_Z = ENV .. " ../src/freechains.lua --root " .. ROOT_Z

for _, dir in ipairs { ROOT_A, ROOT_B, ROOT_C, ROOT_D, ROOT_E, ROOT_Z } do
    exec {
        cmd = "mkdir -p " .. dir,
    }
end

local function CHAIN (root)
    return root .. "/chains/bw/"
end

do
    print("==> Test: same HEAD, same order (fork winner vs replay path)")

    if INIT then
        TEST "A creates bw (search mode)"
        exec {
            cmd = EXE_A .. " --now=1000 chains add /bw init " .. GEN_0,
        }
        exec {
            cmd = "git -C " .. CHAIN(ROOT_A) .. " bundle create " .. INIT .. " refs/genesis main",
        }
    else
        TEST "A clones bw from the bundled genesis"
        exec {
            cmd = EXE_A .. " --now=1000 chains add /bw clone " .. BUNDLE,
        }
    end

    TEST "B, C, D clone A (at G)"
    for _, exe in ipairs { EXE_B, EXE_C, EXE_D } do
        exec {
            cmd = exe .. " --now=1000 chains add /bw clone " .. CHAIN(ROOT_A),
        }
    end

    TEST "A posts a1 (K1), B posts b1 (K2), concurrent"
    local a1 = exec {
        cmd = EXE_A .. " --now=1010 chain /bw post inline 'a1' --sign " .. KEY1,
    }
    local b1 = exec {
        cmd = EXE_B .. " --now=1020 chain /bw post inline 'b1' --sign " .. KEY2,
    }

    TEST "D recvs A: D has a1"
    exec {
        cmd = EXE_D .. " --now=1030 chain /bw sync recv " .. CHAIN(ROOT_A),
    }

    TEST "A recvs B: M1 = a1 + b1"
    exec {
        cmd = EXE_A .. " --now=1040 chain /bw sync recv " .. CHAIN(ROOT_B),
    }

    TEST "D posts a2 on a1 (K2)"
    local a2 = exec {
        cmd = EXE_D .. " --now=1050 chain /bw post inline 'a2' --sign " .. KEY2,
    }

    TEST "C recvs A (M1), posts c1 on M1 (K3)"
    exec {
        cmd = EXE_C .. " --now=1060 chain /bw sync recv " .. CHAIN(ROOT_A),
    }
    local c1 = exec {
        cmd = EXE_C .. " --now=1070 chain /bw post inline 'c1' --sign " .. KEY3,
    }

    TEST "D recvs A: M2 = a2 + M1"
    exec {
        cmd = EXE_D .. " --now=1080 chain /bw sync recv " .. CHAIN(ROOT_A),
    }

    TEST "E clones D (HEAD M2)"
    exec {
        cmd = EXE_E .. " --now=1090 chains add /bw clone " .. CHAIN(ROOT_D),
    }

    TEST "D recvs C: M3 = M2 + c1"
    exec {
        cmd = EXE_D .. " --now=1100 chain /bw sync recv " .. CHAIN(ROOT_C),
    }

    TEST "E recvs D: fast-forward to M3"
    exec {
        cmd = EXE_E .. " --now=1110 chain /bw sync recv " .. CHAIN(ROOT_D),
    }

    TEST "Z clones D (fresh, at M3)"
    exec {
        cmd = EXE_Z .. " --now=1120 chains add /bw clone " .. CHAIN(ROOT_D),
    }

    local NAME = { [a1]="a1", [b1]="b1", [a2]="a2", [c1]="c1" }
    local function names (T)
        local t = {}
        for i, cid in ipairs(T) do
            t[i] = NAME[cid] or cid
        end
        return table.concat(t, " ")
    end

    local hd = TREE(CHAIN(ROOT_D))
    local he = TREE(CHAIN(ROOT_E))
    local hz = TREE(CHAIN(ROOT_Z))
    local od = names((ORDER(EXE_D, "/bw")))
    local oe = names((ORDER(EXE_E, "/bw")))
    local oz = names((ORDER(EXE_Z, "/bw")))

    if INIT then
        local agree = (od == oe) and (oe == oz)
        print("HEAD " .. hd)
        print("D " .. od)
        print("E " .. oe)
        print("Z " .. oz)
        print(agree and "AGREE" or "DIVERGE")
        os.exit(0)
    end

    TEST "posts match the bundled genesis (fixture not stale)"
    for k, cid in pairs { a1=a1, b1=b1, a2=a2 } do
        assert(cid == GUARD[k], "fixture stale: " .. k .. " " .. cid .. " ~= " .. GUARD[k])
    end

    TEST "D, E, Z share HEAD M3"
    assert(hd == he and he == hz, "HEADs differ: " .. hd .. " " .. he .. " " .. hz)

    TEST "D (merger) and E (FF) list the same order"
    assert(od == oe, "D: " .. od .. " | E: " .. oe)

    TEST "D (merger) and Z (clone) list the same order"
    assert(od == oz, "D: " .. od .. " | Z: " .. oz)
end

print("<== ALL PASSED")
