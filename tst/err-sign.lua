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

-- sync rejects unsigned post from remote

print("==> sync rejects unsigned post")

do
    TEST "C creates chain"
    exec(EXE_C .. " --now=1000 chains add err-sign config " .. GEN_1)

    TEST "C posts signed"
    exec(EXE_C .. " --now=2000 chain err-sign post inline 'legit' --sign " .. KEY)

    TEST "D clones from C"
    exec(EXE_D .. " chains add err-sign clone " .. REPO_C)
end

-- craft unsigned commit directly via git (bypass freechains)
do
    TEST "C crafts unsigned post via raw git"
    local f = io.open(REPO_C .. "forged.txt", "w")
    f:write("forged content\n")
    f:close()
    exec("git -C " .. REPO_C .. " add forged.txt")
    exec (
        "GIT_AUTHOR_DATE='2005-04-07T22:13:13' GIT_COMMITTER_DATE='2005-04-07T22:13:13' "
        .. "git -C " .. REPO_C .. " commit -m '(empty message)' --trailer 'Freechains: post'"
    )
    -- add state commit (replay expects it)
    exec (
        "GIT_AUTHOR_DATE='2005-04-07T22:13:13' GIT_COMMITTER_DATE='2005-04-07T22:13:13' "
        .. "git -C " .. REPO_C .. " commit --allow-empty -m '(empty message)' --trailer 'Freechains: state'"
    )
end

do
    TEST "D rejects unsigned post on sync"
    local _, Q, err = exec (true,
        EXE_D .. " --now=3000 chain err-sign sync recv " .. REPO_C
    )
    assert (
        Q~=0 and err:match("ERROR : chain sync : invalid remote")
        , "should fail: " .. tostring(err)
    )
end

print("<== ALL PASSED")
