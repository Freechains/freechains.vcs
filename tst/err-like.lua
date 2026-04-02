#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/err-sign/A/"
local ROOT_B = ROOT .. "/err-sign/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/err-sign/"
local REPO_B = ROOT_B .. "/chains/err-sign/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

-- sync rejects unsigned like from remote

print("==> sync rejects unsigned like")

local POST

do
    TEST "A creates chain"
    exec(EXE_A .. " chains add err-sign config " .. GEN_1)

    TEST "A posts signed"
    POST = exec(EXE_A .. " chain err-sign post inline 'legit' --sign " .. KEY)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-sign clone " .. REPO_A)
end

-- craft unsigned like directly via git (bypass freechains)
do
    TEST "A crafts unsigned like via raw git"
    exec("mkdir -p " .. REPO_A .. ".freechains/likes/")
    local f = io.open(REPO_A .. ".freechains/likes/like-forged.lua", "w")
    f:write('return { target="post", id="'..POST..'", number=1000 }\n')
    f:close()
    exec (
        "git -C " .. REPO_A .. " add .freechains/likes/like-forged.lua"
    )
    exec (
        "git -C " .. REPO_A .. " commit -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects unsigned like on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-sign sync recv " .. REPO_A
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : missing sign key"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects like with no payload file
do
    print("==> sync rejects like without payload")

    local REPO_A2 = ROOT_A .. "/chains/err-payload/"
    local REPO_B2 = ROOT_B .. "/chains/err-payload/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-payload config " .. GEN_1)
    exec(EXE_A .. " chain err-payload post inline 'legit' --sign " .. KEY)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-payload clone " .. REPO_A2)

    TEST "A crafts like with no payload file"
    exec (
        ENV .. " git -C " .. REPO_A2
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " commit --allow-empty -S -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A2 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects like without payload on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-payload sync recv " .. REPO_A2
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : missing metadata file"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects like with invalid lua metadata (syntax error)
do
    print("==> sync rejects like with bad lua metadata (syntax error)")

    local REPO_A3 = ROOT_A .. "/chains/err-lua/"
    local REPO_B3 = ROOT_B .. "/chains/err-lua/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-lua config " .. GEN_1)
    exec(EXE_A .. " chain err-lua post inline 'legit' --sign " .. KEY)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-lua clone " .. REPO_A3)

    TEST "A crafts like with invalid lua metadata"
    exec("mkdir -p " .. REPO_A3 .. ".freechains/likes/")
    local f = io.open(REPO_A3 .. ".freechains/likes/like-err.lua", "w")
    f:write("not valid lua !!!\n")
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A3
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A3
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " commit -S -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A3 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects like with bad lua on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-lua sync recv " .. REPO_A3
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : invalid lua metadata"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects like with invalid lua metadata (not table)
do
    print("==> sync rejects like with bad lua metadata (not table)")

    local REPO_A4 = ROOT_A .. "/chains/err-table/"
    local REPO_B4 = ROOT_B .. "/chains/err-table/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-table config " .. GEN_1)
    exec(EXE_A .. " chain err-table post inline 'legit' --sign " .. KEY)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-table clone " .. REPO_A4)

    TEST "A crafts like with invalid lua metadata"
    exec("mkdir -p " .. REPO_A4 .. ".freechains/likes/")
    local f = io.open(REPO_A4 .. ".freechains/likes/like-err.lua", "w")
    f:write("return 10\n")
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A4
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A4
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " commit -S -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A4 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects like with bad lua on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-table sync recv " .. REPO_A4
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : invalid lua metadata"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects like with invalid target type
do
    print("==> sync rejects like with bad target type")

    local REPO_A5 = ROOT_A .. "/chains/err-target/"
    local REPO_B5 = ROOT_B .. "/chains/err-target/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-target config " .. GEN_1)
    local post = exec(EXE_A .. " chain err-target post inline 'legit' --sign " .. KEY)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-target clone " .. REPO_A5)

    TEST "A crafts like with bad target type"
    exec("mkdir -p " .. REPO_A5 .. ".freechains/likes/")
    local f = io.open(REPO_A5 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="xxx", id="'..post..'", number=1000 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A5
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A5
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " commit -S -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A5 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects like with bad target type on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-target sync recv " .. REPO_A5
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : invalid target : expects 'post' or 'author'"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects like with nonexistent post target
do
    print("==> sync rejects like with post not found")

    local REPO_A6 = ROOT_A .. "/chains/err-post/"
    local REPO_B6 = ROOT_B .. "/chains/err-post/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-post config " .. GEN_1)
    exec(EXE_A .. " chain err-post post inline 'legit' --sign " .. KEY)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-post clone " .. REPO_A6)

    TEST "A crafts like targeting nonexistent post"
    exec("mkdir -p " .. REPO_A6 .. ".freechains/likes/")
    local f = io.open(REPO_A6 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="post", id="0000000000000000000000000000000000000000", number=1000 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A6
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A6
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " commit -S -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A6 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects like with post not found on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-post sync recv " .. REPO_A6
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : invalid target : post not found"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects like from author with insufficient reputation
do
    print("==> sync rejects like with insufficient reputation")

    local REPO_A7 = ROOT_A .. "/chains/err-reps/"
    local REPO_B7 = ROOT_B .. "/chains/err-reps/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-reps config " .. GEN_1)
    local post = exec(EXE_A .. " chain err-reps post inline 'legit' --sign " .. KEY)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-reps clone " .. REPO_A7)

    TEST "A crafts like signed by non-pioneer (0 reps)"
    exec("mkdir -p " .. REPO_A7 .. ".freechains/likes/")
    local f = io.open(REPO_A7 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="post", id="'..post..'", number=1000 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A7
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=openpgp"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A7
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=openpgp"
        .. " commit -S -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A7 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects like with insufficient reps on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-reps sync recv " .. REPO_A7
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : insufficient reputation"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects like with too big time difference
do
    print("==> sync rejects like with too big time difference")

    local REPO_A8 = ROOT_A .. "/chains/err-time/"
    local REPO_B8 = ROOT_B .. "/chains/err-time/"

    TEST "A creates chain + post"
    exec(EXE_A .. " --now=10000 chains add err-time config " .. GEN_1)
    local post = exec(EXE_A .. " --now=11000 chain err-time post inline 'legit' --sign " .. KEY)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-time clone " .. REPO_A8)

    TEST "A crafts like with old timestamp"
    exec("mkdir -p " .. REPO_A8 .. ".freechains/likes/")
    local f = io.open(REPO_A8 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="post", id="'..post..'", number=1000 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A8
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A8
        .. " -c user.signingkey=" .. KEY .. " -c gpg.format=openpgp"
        .. " commit -S --date='1970-01-01T00:00:01+0000' -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A8 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects like with old timestamp on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-time sync recv " .. REPO_A8
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : too old"
        , "should fail: " .. tostring(err)
    )
end

print("<== ALL PASSED")
