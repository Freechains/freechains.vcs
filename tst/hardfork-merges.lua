#!/usr/bin/env lua5.4

-- Same posts, different merges: two peers holding the SAME actions
-- must not hard fork on each other.
--
-- Found in 2606-sims (usenet 2k, local-first, action 405): L04 and M1
-- held the same posts, merged in a different structure, so their
-- orders swapped two old posts. 7 days of chain time later the sync
-- was refused (`ERROR : chain sync : hard fork`) and never healed.
--
-- With pairwise merges, the order of a merge was the winner's order
-- plus the loser's replay, so it depended on which pairs met first,
-- not only on the action set.
-- GEN_3 + likes: K1 > K2 > K3, but K2 + K3 > K1.
--
--             seed[K1] -- likes[K2,K3]
--           /      |       \
--        x[K1]   y[K2]    z[K3]       t: three peers post at once
--
--   pairwise, A: (x + y) + z  ->  x y z
--   pairwise, C: (z + y) + x  ->  y z x
--
-- Now a sync joins the tip SET in one canonical merge, ranked by
-- the reps at the common floor: both reach the same merge {x,y,z},
-- ordered x y z. 8 days later both post again and sync: no hard
-- fork, same final order.

require "tests"

local DIR = ROOT .. "/hardfork-merges/"
local ROOT_A = DIR .. "A/"
local ROOT_B = DIR .. "B/"
local ROOT_C = DIR .. "C/"
local ROOT_D = DIR .. "D/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C
local EXE_D  = ENV .. " ../src/freechains.lua --root " .. ROOT_D

local WEEK = 7 * 24 * 60 * 60
local T    = 2000
local LATE = T + WEEK + 24*60*60

for _, r in ipairs { ROOT_A, ROOT_B, ROOT_C, ROOT_D } do
    exec {
        cmd = "mkdir -p " .. r,
    }
end

do
    print("==> Test: same posts, different merges, no hard fork")

    TEST "A creates chain + seed[K1]"
    exec {
        cmd = EXE_A .. " --now=1000 chains add /hm init " .. GEN_3,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1100 chain /hm post inline 'seed\n' --sign " .. KEY1,
    }

    -- K2 pays 1, K3 pays 2: K1 > K2 > K3, K2 + K3 > K1
    TEST "K2, K3 like seed"
    exec {
        cmd = EXE_A .. " --now=1200 chain /hm like 1000 action " .. seed .. " --sign " .. KEY2,
    }
    exec {
        cmd = EXE_A .. " --now=1300 chain /hm like 2000 action " .. seed .. " --sign " .. KEY3,
    }
    do
        local r1 = REPS(EXE_A, "/hm", PUB1)
        local r2 = REPS(EXE_A, "/hm", PUB2)
        local r3 = REPS(EXE_A, "/hm", PUB3)
        assert(r1 > r2 and r2 > r3 and r2+r3 > r1,
            "reps: " .. r1 .. " " .. r2 .. " " .. r3)
    end

    TEST "B, C clone A"
    exec {
        cmd = EXE_B .. " chains add /hm clone " .. ROOT_A .. "/chains/hm/",
    }
    exec {
        cmd = EXE_C .. " chains add /hm clone " .. ROOT_A .. "/chains/hm/",
    }

    TEST "A, B, C post x, y, z at once"
    local x = exec {
        cmd = EXE_A .. " --now=" .. T .. " chain /hm post inline 'x\n' --sign " .. KEY1,
    }
    local y = exec {
        cmd = EXE_B .. " --now=" .. T .. " chain /hm post inline 'y\n' --sign " .. KEY2,
    }
    local z = exec {
        cmd = EXE_C .. " --now=" .. T .. " chain /hm post inline 'z\n' --sign " .. KEY3,
    }

    -- D: z alone, for A to merge it last
    TEST "D clones C (z only)"
    exec {
        cmd = EXE_D .. " chains add /hm clone " .. ROOT_C .. "/chains/hm/",
    }

    TEST "C merges y, then x"
    exec {
        cmd = EXE_C .. " --now=" .. (T+100) .. " chain /hm sync recv " .. ROOT_B .. "/chains/hm/",
    }
    exec {
        cmd = EXE_C .. " --now=" .. (T+200) .. " chain /hm sync recv " .. ROOT_A .. "/chains/hm/",
    }

    TEST "A merges y, then z"
    exec {
        cmd = EXE_A .. " --now=" .. (T+100) .. " chain /hm sync recv " .. ROOT_B .. "/chains/hm/",
    }
    exec {
        cmd = EXE_A .. " --now=" .. (T+200) .. " chain /hm sync recv " .. ROOT_D .. "/chains/hm/",
    }

    -- same actions, merged in another sequence: same merge commit
    -- (the canonical join of {x,y,z}), same order (x y z)
    TEST "A and C: same posts, same main, same order"
    do
        local OA, SA = ORDER(EXE_A, "/hm")
        local OC, SC = ORDER(EXE_C, "/hm")
        assert(#OA == #OC, "sizes: " .. #OA .. " " .. #OC)
        for k in pairs(SA) do
            assert(SC[k], "C lacks " .. k)
        end
        assert(SA[x] and SA[y] and SA[z])
        assert(table.concat(OA, " ") == table.concat(OC, " "),
            "orders differ")
        assert(OA[#OA-2]==x and OA[#OA-1]==y and OA[#OA]==z,
            "order x y z")
        local ha = exec {
            cmd = "git -C " .. ROOT_A .. "/chains/hm/ rev-parse HEAD",
        }
        local hc = exec {
            cmd = "git -C " .. ROOT_C .. "/chains/hm/ rev-parse HEAD",
        }
        assert(ha == hc, "mains differ: " .. ha .. " " .. hc)
    end

    -- 8 days later: x y z are settled on both sides
    TEST "A, C post again 8 days later"
    exec {
        cmd = EXE_A .. " --now=" .. LATE .. " chain /hm post inline 'w\n' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_C .. " --now=" .. LATE .. " chain /hm post inline 'v\n' --sign " .. KEY2,
    }

    -- pairwise merges: whichever side won, the other refused
    TEST "A recvs C: no hard fork"
    exec {
        cmd = EXE_A .. " --now=" .. (LATE+100) .. " chain /hm sync recv " .. ROOT_C .. "/chains/hm/",
    }
    TEST "C recvs A: no hard fork"
    exec {
        cmd = EXE_C .. " --now=" .. (LATE+200) .. " chain /hm sync recv " .. ROOT_A .. "/chains/hm/",
    }

    TEST "A and C: same order"
    do
        local OA = ORDER(EXE_A, "/hm")
        local OC = ORDER(EXE_C, "/hm")
        assert(table.concat(OA, " ") == table.concat(OC, " "),
            "orders differ")
    end
end

print("<== ALL PASSED")
