#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/err-post/A/"
local ROOT_B = ROOT .. "/err-post/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

-- sync rejects post from author with insufficient reputation
do
    print("==> sync rejects post with insufficient reputation")

    local REPO_A1 = ROOT_A .. "/chains/err-reps/"
    local REPO_B1 = ROOT_B .. "/chains/err-reps/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-reps init file " .. GEN_1)
    exec(EXE_A .. " chain err-reps post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-reps clone " .. REPO_A1)

    TEST "A crafts post signed by non-pioneer (0 reps)"
    local f = io.open(REPO_A1 .. "forged.txt", "w")
    f:write("forged content\n")
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A1
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=ssh"
        .. " add forged.txt"
    )
    exec (
        ENV .. " git -C " .. REPO_A1
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=ssh"
        .. " commit -S -m 'x' --trailer 'Freechains: post'"
    )
    exec (
        "git -C " .. REPO_A1 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects post with insufficient reps on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-reps sync recv " .. REPO_A1
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid post : insufficient reputation"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects post with too big time difference
do
    print("==> sync rejects post with too old timestamp")

    local REPO_A2 = ROOT_A .. "/chains/err-time/"
    local REPO_B2 = ROOT_B .. "/chains/err-time/"

    TEST "A creates chain + post"
    exec(EXE_A .. " --now=10000 chains add err-time init file " .. GEN_1)
    exec(EXE_A .. " --now=11000 chain err-time post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-time clone " .. REPO_A2)

    TEST "A crafts post with old timestamp"
    local f = io.open(REPO_A2 .. "forged.txt", "w")
    f:write("forged content\n")
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A2
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " add forged.txt"
    )
    exec (
        ENV .. " git -C " .. REPO_A2
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " commit -S --date='1970-01-01T00:00:01+0000' -m 'x' --trailer 'Freechains: post'"
    )
    exec (
        "git -C " .. REPO_A2 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects post with old timestamp on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-time sync recv " .. REPO_A2
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid post : too old"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects post with forged signature
do
    print("==> sync rejects forged signature post")

    local REPO_A3 = ROOT_A .. "/chains/err-forge/"
    local REPO_B3 = ROOT_B .. "/chains/err-forge/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-forge init file " .. GEN_1)
    exec(EXE_A .. " chain err-forge post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-forge clone " .. REPO_A3)

    TEST "A crafts a post with forged signature"
    exec(EXE_A .. " chain err-forge post inline 'original content' --sign " .. KEY1)
    -- Strip state commit
    exec("git -C " .. REPO_A3 .. " reset --hard HEAD~1")
    -- Tamper: change commit message, gpgsig header stays intact
    local raw = exec("git -C " .. REPO_A3 .. " cat-file commit HEAD")
    local forged = raw:gsub("%(empty message%)", "(tampered)")
    assert(forged ~= raw, "substitution must change something")
    local tmpf = REPO_A3 .. ".freechains/tmp/forged-commit"
    local fh = io.open(tmpf, "w")
    fh:write(forged)
    fh:close()
    local new_hash = exec("git -C " .. REPO_A3 .. " hash-object -t commit -w --stdin <" .. tmpf)
    os.remove(tmpf)
    exec("git -C " .. REPO_A3 .. " reset --hard " .. new_hash)
    -- State commit on top
    exec("git -C " .. REPO_A3 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty")

    TEST "B rejects forged signature on sync"
    local _,Q,err = exec(true, EXE_B .. " chain err-forge sync recv " .. REPO_A3)
    assert(Q~=0 and err == "ERROR : chain sync : invalid post : invalid signature", "should fail: " .. tostring(err))
end

-- sync fetch failed
do
    print("==> sync fetch failed")

    TEST "sync recv from nonexistent remote"
    local _,Q,err = exec(true, EXE_A .. " chain err-forge sync recv /nonexistent/repo")
    assert(Q~=0 and err=="ERROR : chain sync : fetch failed", "should fail: " .. tostring(err))
end

print("<== ALL PASSED")
