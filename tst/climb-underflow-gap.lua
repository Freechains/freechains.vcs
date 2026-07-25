#!/usr/bin/env lua5.4

-- KNOWN FAILURE (not wired into `make tests`): run via
--   make T=climb-underflow-gap test
--
-- The simple `climb` fix (visited + ancestor guards, tst/climb-underflow.lua)
-- resolves the nested-merge underflow and matches across peers WHEN the
-- posts are close in time. But when the nested merge spans a large time gap
-- (crossing the 24h maturation/consolidation window, as the README guide
-- does), the two derivation paths -- `climb` (ff-check, from the shallow
-- `oct`) and the reorder-append (divergent store) -- DIVERGE, and the strict
-- state check rejects the recv:
--
--   ERROR : chain sync : remote state mismatch
--
-- Same nested topology as climb-underflow.lua, but `day7` sits ~7 days after
-- the fork so maturation kicks in. Asserts H's order == A's order after the
-- recv; RED today. A full fix (single canonical `derive` fold over both tips
-- from genesis) makes it green -- see .claude/plans/260724-climb-underflow.md.

require "tests"

local ROOT_A = ROOT .. "/climb-gap/A/"
local ROOT_B = ROOT .. "/climb-gap/B/"
local ROOT_H = ROOT .. "/climb-gap/H/"

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
    local T = {}
    for line in out:gmatch("[^\n]+") do
        T[#T+1] = line
    end
    return T
end

-- reuse the nested topology, but the community advances across a 7-day gap
do
    print("==> Test: nested merge across a maturation gap (KNOWN FAILURE)")

    TEST "A creates chain, B and H clone"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#cg' init file " .. GEN_2,
    }
    exec {
        cmd = EXE_B .. " chains add '#cg' clone " .. ROOT_A .. "/chains/#cg/",
    }
    exec {
        cmd = EXE_H .. " chains add '#cg' clone " .. ROOT_A .. "/chains/#cg/",
    }

    TEST "A posts AW, B posts CW (fork at genesis)"
    exec {
        cmd = EXE_A .. " --now=1100 chain '#cg' post inline 'AW\n' --file aw.txt --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1100 chain '#cg' post inline 'CW\n' --file cw.txt --sign " .. KEY2,
    }

    TEST "B recvs A -> inner merge M1"
    exec {
        cmd = EXE_B .. " --now=1150 chain '#cg' sync recv " .. ROOT_A .. "/chains/#cg/",
    }

    TEST "B posts day1, then day7 ~7 days later (crosses maturation)"
    exec {
        cmd = EXE_B .. " --now=1200 chain '#cg' post inline 'day1\n' --file d1.txt --sign " .. KEY2,
    }
    exec {
        cmd = EXE_B .. " --now=1780000000 chain '#cg' post inline 'day7\n' --file d7.txt --sign " .. KEY2,
    }

    TEST "H recvs the community branch"
    exec {
        cmd = EXE_H .. " --now=1780000001 chain '#cg' sync recv " .. ROOT_B .. "/chains/#cg/",
    }

    TEST "A posts takeover, then recvs community -> outer merge M2"
    exec {
        cmd = EXE_A .. " --now=1780000002 chain '#cg' post inline 'takeover\n' --file to.txt --sign " .. KEY1,
    }
    exec {
        cmd = EXE_A .. " --now=1780000003 chain '#cg' sync recv " .. ROOT_B .. "/chains/#cg/",
    }

    -- RED: the simple fix fails here with "remote state mismatch"
    TEST "H recvs A (nested merge across the gap) -- must not mismatch"
    exec {
        cmd = EXE_H .. " --now=1780000004 chain '#cg' sync recv " .. ROOT_A .. "/chains/#cg/",
    }

    TEST "H's order equals A's order"
    local a = order(EXE_A, "#cg")
    local h = order(EXE_H, "#cg")
    assert(#a == #h, "order length differs: A=" .. #a .. " H=" .. #h)
    for i = 1, #a do
        assert(a[i] == h[i], "order differs at " .. i .. ": A=" .. a[i] .. " H=" .. h[i])
    end
end
