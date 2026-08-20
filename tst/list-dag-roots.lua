#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/list-dag-roots/A/"
local ROOT_B = ROOT .. "/list-dag-roots/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/#roots/"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}

-- TWO CONTENT ROOTS: B clones before any post exists, so both peers'
-- first posts fork at the genesis commit itself. `backs` walks THROUGH
-- genesis and returns empty for both, and `list dag` averages the
-- columns of that empty set:
--
--     list.lua: attempt to divide by zero
--
-- Nested merges are NOT needed to reach it -- clone a fresh chain and
-- have both peers post once.
--
--   git:  genesis --+-- AW --+
--                   `-- CW --'-- M    (M = state merge, filtered out)
--   dag:  AW  CW                      (siblings of nothing)
do
    print("==> Test: list dag with two content roots")

    TEST "A creates chain (no post yet)"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#roots' init --pioneer=" .. KEY1,
    }

    TEST "B clones before any post exists"
    exec {
        cmd = EXE_B .. " chains add '#roots' clone " .. REPO_A,
    }

    TEST "A and B post concurrently (both fork at genesis)"
    exec {
        cmd = EXE_A .. " --now=1100 chain '#roots' post inline 'AW' --sign " .. KEY1,
    }
    exec {
        cmd = EXE_B .. " --now=1100 chain '#roots' post inline 'CW' --sign " .. KEY1,
    }

    TEST "B recvs from A"
    exec {
        cmd = EXE_B .. " --now=1200 chain '#roots' sync recv " .. REPO_A,
    }

    TEST "B order has both posts"
    local lines = {}
    for line in (exec {
        cmd = EXE_B .. " chain '#roots' list order",
    }):gmatch("[^\n]+") do
        lines[#lines+1] = line
    end
    assert(#lines == 2, "expected 2 commits, got " .. #lines)
    local fst, snd = lines[1], lines[2]

    TEST "B dag draws both roots on one row"
    assert(
        exec {
            cmd = EXE_B .. " chain '#roots' list dag",
        } ==
        -- single-line output: `exec` strips the trailing newline
        string.format("%s     %s", fst:sub(1,7), snd:sub(1,7))
    )
end

print("<== ALL PASSED")
