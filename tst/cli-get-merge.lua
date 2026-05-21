#!/usr/bin/env lua5.4

-- Minimal repro: `chain get metadata <LIKE>` errors when LIKE is a
-- like-merge whose ancestry passes through a state-merge produced by
-- sync.lua case-4 diverge (the unconventional `'x'` merge commit has
-- no Freechains trailer and trips get.lua's `rec` walker).

require "tests"

local ROOT_A = ROOT .. "/cli-get-merge/A/"
local ROOT_B = ROOT .. "/cli-get-merge/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

-- A creates chain (KEY1 pioneer)
exec(EXE_A .. " --now=1000 chains add test init inline --sign " .. KEY1)

-- B clones
exec(EXE_B .. " chains add test clone " .. REPO_A)

-- diverge: A and B each post from the same tip
exec(EXE_A .. " --now=2000 chain test post inline 'a' --sign " .. KEY1)
exec(EXE_B .. " --now=2500 chain test post inline 'b' --sign " .. KEY1)

-- B recvs from A → sync.lua case 4 → creates `'x'` + state-merge `M`
exec(EXE_B .. " --now=3000 chain test sync recv " .. REPO_A)

-- KEY2 (0 reps) begs
local BEG = exec(EXE_B .. " --now=4000 chain test post inline 'please' --beg --sign " .. KEY2)

-- KEY1 likes the beg → LIKE is a 2-parent merge with `Freechains: like`
local LIKE = exec(EXE_B .. " --now=5000 chain test like 1 post " .. BEG .. " --sign " .. KEY1)

TEST "get metadata on like-merge over a state-merge should succeed"
local out, code, err = exec(true,
    EXE_B .. " chain test get metadata " .. LIKE
)
assert(
    code == 0,
    "expected exit 0, got " .. tostring(code) .. " err=" .. tostring(err)
)

print("<== ALL PASSED")
