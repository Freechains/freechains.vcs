#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/cli-sync/A/"
local ROOT_B = ROOT .. "/cli-sync/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

-- 1. recv basic (fetch + merge)
do
    print("==> Step 1: recv basic")

    do
        TEST "A creates chain + posts"
        exec(EXE_A .. " chains add test config " .. GEN_1)
        local out = exec (
            EXE_A .. " chain test post inline 'post from A' --sign " .. KEY
        )
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "B clones"
        exec(EXE_B .. " chains add test clone " .. REPO_A)
    end

    do
        TEST "A posts again"
        local out = exec (
            EXE_A .. " chain test post inline 'second from A' --sign " .. KEY
        )
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "B recvs from A"
        exec(EXE_B .. " chain test sync recv " .. REPO_A)
    end

    do
        TEST "B has A's latest post"
        local head_a = exec("git -C " .. REPO_A .. " rev-parse HEAD")
        local head_b = exec("git -C " .. REPO_B .. " rev-parse HEAD")
        assert(head_a == head_b, "heads differ: " .. head_a .. " vs " .. head_b)
    end
end

print("<== ALL PASSED")
