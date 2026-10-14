#!/usr/bin/env lua5.4

-- A fork point WITHOUT a snapshot must still score the fork.
--
-- A pull derives the remote's states (`CONSENSUS.state`), but an inner
-- merge's LOSER side is only replayed on top of the winner: its commits
-- get no snapshot of their own. Such a commit can later be the
-- merge-base of a new fork. Then `recv` first derives the remote's
-- lineage through it, writing its snapshot with a DEFERRED ref, and
-- `winner` (which trusts `STATE.has`) peeks a ref not yet in git:
--  "bug found : no snapshot : <y>"
--
-- GEN_2: KEY2 likes seed so KEY1 > KEY2: `x` beats `y` by reps.
--
--                    seed[K1] -- like[K2]       <- B, C, D clone here
--                    /                \
--               x[K1] (C)            y[K2] (B)
--                    \                /    \
--                     M  (C recv B)       y2[K2] (B)
--
--   D recv C : D gets M, x, y; y is M's loser, so D has no snapshot at y
--   D recv B : loc=M, rem=y2, merge-base=y (unsnapshotted on D)

require "tests"

local ROOT_A = ROOT .. "/bug-floor-snapshot/A/"
local ROOT_B = ROOT .. "/bug-floor-snapshot/B/"
local ROOT_C = ROOT .. "/bug-floor-snapshot/C/"
local ROOT_D = ROOT .. "/bug-floor-snapshot/D/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C
local EXE_D  = ENV .. " ../src/freechains.lua --root " .. ROOT_D

for _, r in ipairs { ROOT_A, ROOT_B, ROOT_C, ROOT_D } do
    exec {
        cmd = "mkdir -p " .. r,
    }
end

do
    print("==> Test: fork point without a snapshot")

    TEST "A creates chain, seed[K1], like[K2]"
    exec {
        cmd = EXE_A .. " --now=1000 chains add /bfs init " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1020 chain /bfs post inline 'seed\n' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_A .. " --now=1040 chain /bfs like 1000 action " .. seed .. " --sign " .. KEY2,
    }

    TEST "B, C, D clone A"
    exec {
        cmd = EXE_B .. " chains add /bfs clone " .. ROOT_A .. "/chains/bfs/",
    }
    exec {
        cmd = EXE_C .. " chains add /bfs clone " .. ROOT_A .. "/chains/bfs/",
    }
    exec {
        cmd = EXE_D .. " chains add /bfs clone " .. ROOT_A .. "/chains/bfs/",
    }

    TEST "C posts x[K1], B posts y[K2] (concurrent)"
    exec {
        cmd = EXE_C .. " --now=1100 chain /bfs post inline 'x\n' --sign " .. KEY1,
    }
    local y = exec {
        cmd = EXE_B .. " --now=1100 chain /bfs post inline 'y\n' --sign " .. KEY2,
    }

    TEST "C recvs B: merge M, x wins, y is the loser"
    exec {
        cmd = EXE_C .. " --now=1110 chain /bfs sync recv " .. ROOT_B .. "/chains/bfs/",
    }

    TEST "D recvs C: D has no snapshot at y"
    exec {
        cmd = EXE_D .. " --now=1120 chain /bfs sync recv " .. ROOT_C .. "/chains/bfs/",
    }
    do
        local _, code = exec { stderr=false, err=false,
            cmd = "git -C " .. ROOT_D .. "/chains/bfs/ show-ref --verify --quiet refs/local/" .. y,
        }
        assert(code ~= 0, "precondition: y must have no snapshot on D")
    end

    TEST "B posts y2[K2] on top of y"
    exec {
        cmd = EXE_B .. " --now=1200 chain /bfs post inline 'y2\n' --sign " .. KEY2,
    }

    -- loc=M, rem=y2, merge-base=y: the floor has no snapshot
    TEST "D recvs B: fork at y scores and merges"
    exec {
        cmd = EXE_D .. " --now=1210 chain /bfs sync recv " .. ROOT_B .. "/chains/bfs/",
    }

    TEST "D's order holds x, y, y2"
    do
        local O = ORDER(EXE_D, "/bfs")
        assert(#O == 5, "expected 5 entries, got " .. #O)
    end
end

print("<== ALL PASSED")
