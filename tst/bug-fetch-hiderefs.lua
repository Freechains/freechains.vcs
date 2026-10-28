#!/usr/bin/env lua5.4

-- A chain repo must hide its local refs from fetch.
--
-- Every commit has a snapshot, in the index ref refs/local (a tree
-- keyed by cid), and every post a payload ref (refs/payloads/*).
-- After a fetch, git checks connectivity with `rev-list --objects
-- --not --all`, which would walk them (once ~2 refs per post: a
-- 1-post pull at 50k posts spent 7.5 of 11.5 s there).
-- `fetch.hideRefs` drops them from that check (`--exclude-hidden`).

require "tests"

local ROOT_A = ROOT .. "/bug-fetch-hiderefs/A/"
local ROOT_B = ROOT .. "/bug-fetch-hiderefs/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

for _, r in ipairs { ROOT_A, ROOT_B } do
    exec {
        cmd = "mkdir -p " .. r,
    }
end

--[[
-- Assert a chain repo hides both local prefixes from fetch.
-- Inputs:
--  - dir [string]: the chain repo dir
-- Outputs:
--  - none
-- Errors:
--  - assert "missing fetch.hideRefs : <prefix>"
-- Callers:
--  - main chunk (this file): after init and after clone
--]]
local function hidden (dir)
    local out = exec { err=false, stderr=false,
        cmd = "git -C " .. dir .. " config --get-all fetch.hideRefs",
    } or ""
    local set = {}
    for l in out:gmatch("[^\n]+") do
        set[l] = true
    end
    for _, p in ipairs { "refs/local", "refs/payloads/" } do
        assert(set[p], "missing fetch.hideRefs : " .. p)
    end
end

do
    print("==> Test: chain repos hide local refs from fetch")

    TEST "A creates chain: hideRefs set"
    exec {
        cmd = EXE_A .. " --now=1000 chains add /bfh init",
    }
    hidden(ROOT_A .. "/chains/bfh/")

    TEST "B clones A: hideRefs set"
    exec {
        cmd = EXE_B .. " chains add /bfh clone " .. ROOT_A .. "/chains/bfh/",
    }
    hidden(ROOT_B .. "/chains/bfh/")
end

print("<== ALL PASSED")
