#!/usr/bin/env lua5.4

require "tests"

local ROOT_C = ROOT .. "/err-sign/C/"
local ROOT_D = ROOT .. "/err-sign/D/"

local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C
local EXE_D  = ENV .. " ../src/freechains.lua --root " .. ROOT_D

local REPO_C = ROOT_C .. "/chains/err-sign/"
local REPO_D = ROOT_D .. "/chains/err-sign/"

exec("mkdir -p " .. ROOT_C)
exec("mkdir -p " .. ROOT_D)

-- sync rejects unsigned like from remote

print("==> sync rejects unsigned like")

local POST

do
    TEST "C creates chain"
    exec(EXE_C .. " chains add err-sign config " .. GEN_1)

    TEST "C posts signed"
    POST = exec(EXE_C .. " chain err-sign post inline 'legit' --sign " .. KEY)

    TEST "D clones from C"
    exec(EXE_D .. " chains add err-sign clone " .. REPO_C)
end

-- craft unsigned like directly via git (bypass freechains)
do
    TEST "C crafts unsigned like via raw git"
    exec("mkdir -p " .. REPO_C .. ".freechains/likes/")
    local f = io.open(REPO_C .. ".freechains/likes/like-forged.lua", "w")
    f:write('return { target="post", id="'..POST..'", number=1000 }\n')
    f:close()
    exec (
        "git -C " .. REPO_C .. " add .freechains/likes/like-forged.lua"
    )
    exec (
        "git -C " .. REPO_C .. " commit -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_C .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )
end

do
    TEST "D rejects unsigned like on sync"
    local _,Q,err = exec (true,
        EXE_D .. " chain err-sign sync recv " .. REPO_C
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : missing sign key"
        , "should fail: " .. tostring(err)
    )
end

print("<== ALL PASSED")
