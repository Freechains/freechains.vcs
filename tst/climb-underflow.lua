#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/climb-underflow/A/"
local ROOT_B = ROOT .. "/climb-underflow/B/"
local ROOT_H = ROOT .. "/climb-underflow/H/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_H  = ENV .. " ../src/freechains.lua --root " .. ROOT_H

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}
exec {
    cmd = "mkdir -p " .. ROOT_H,
}

local function order (exe, chain)
    local out = exec {
        cmd = exe .. " chain '" .. chain .. "' list order",
    }
    local S = {}
    for line in out:gmatch("[^\n]+") do
        S[line] = true
    end
    return S
end

-- Nested merges underflow `climb`: an INNER merge M1 forks DEEPER than
-- the OUTER merge M2. `meet` reconciles M2 from its fork F2 (=AW), then
-- climbs the community side and re-enters M1 with com=F2; M1's own fork
-- F1 (=seed) is below F2, so climb descends past com to a root ->
-- parents(nil) crash at sync.lua (concatenate nil 'tip').
--
--            AW[K1] (F2) ----------------- takeover[K1] --\
--           /       \                                      M2
-- seed[K1] (F1)      M1 = merge(CW, AW) -- day1 -- day7 --/
--           \       /
--            CW[K2] (forks at F1)
do
    print("==> Test: nested merges do not underflow climb")

    -- A: G -- seed[K1]
    TEST "A creates chain + seed"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#cu' init file " .. GEN_2,
    }
    exec {
        cmd = EXE_A .. " --now=1050 chain '#cu' post inline 'seed\n' --file seed.txt --sign " .. KEY1,
    }

    -- B, H clone at seed
    TEST "B and H clone cu (at seed = F1)"
    exec {
        cmd = EXE_B .. " chains add '#cu' clone " .. ROOT_A .. "/chains/#cu/",
    }
    exec {
        cmd = EXE_H .. " chains add '#cu' clone " .. ROOT_A .. "/chains/#cu/",
    }

    -- Concurrent children of seed (fork at F1):
    -- A: seed -- AW[K1]     (AW = F2)
    -- B: seed -- CW[K2]
    TEST "A posts AW (=F2), B posts CW, both forking at seed"
    exec {
        cmd = EXE_A .. " --now=1100 chain '#cu' post inline 'AW\n' --file aw.txt --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1100 chain '#cu' post inline 'CW\n' --file cw.txt --sign " .. KEY2,
    }

    -- B recv A -> INNER merge M1 = merge(CW, AW), fork = seed = F1
    TEST "B recvs A -> inner merge M1 (fork = seed)"
    exec {
        cmd = EXE_B .. " --now=1150 chain '#cu' sync recv " .. ROOT_A .. "/chains/#cu/",
    }

    -- Community advances past M1
    -- B: ... M1 -- day1[K2] -- day7[K2]
    TEST "B posts day1, day7 on top of M1 (community)"
    exec {
        cmd = EXE_B .. " --now=1200 chain '#cu' post inline 'day1\n' --file d1.txt --sign " .. KEY2,
    }
    exec {
        cmd = EXE_B .. " --now=1300 chain '#cu' post inline 'day7\n' --file d7.txt --sign " .. KEY2,
    }

    -- H gets the community branch (day7), but NOT takeover
    TEST "H recvs community (day7) from B"
    exec {
        cmd = EXE_H .. " --now=1350 chain '#cu' sync recv " .. ROOT_B .. "/chains/#cu/",
    }

    -- A (still at AW = F2) posts takeover
    -- A: seed -- AW -- takeover[K1]
    TEST "A posts takeover (child of AW = F2)"
    local takeover = exec {
        cmd = EXE_A .. " --now=1400 chain '#cu' post inline 'takeover\n' --file to.txt --sign " .. KEY1,
    }

    -- A recv community -> OUTER merge M2 = merge(takeover, day7), fork = AW = F2
    TEST "A recvs community -> outer merge M2 (fork = AW), nesting M1"
    exec {
        cmd = EXE_A .. " --now=1450 chain '#cu' sync recv " .. ROOT_B .. "/chains/#cu/",
    }

    -- H recv A: climb M2 (com=oct) -> meet up=AW=F2 -> climb community
    -- side re-enters M1 -> meet com=F2, up=seed=F1 < F2 -> underflow.
    TEST "H recvs A: must not underflow climb (nested merges)"
    exec {
        cmd = EXE_H .. " --now=1500 chain '#cu' sync recv " .. ROOT_A .. "/chains/#cu/",
    }

    TEST "H's order contains takeover"
    local S = order(EXE_H, "#cu")
    assert(S[takeover], "takeover missing from H order (climb underflow)")
end
