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
    exec(EXE_A .. " chains add err-sign init " .. GEN_1)

    TEST "A posts signed"
    POST = exec(EXE_A .. " chain err-sign post inline 'legit' --sign " .. KEY1)

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
    exec(EXE_A .. " chains add err-payload init " .. GEN_1)
    exec(EXE_A .. " chain err-payload post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-payload clone " .. REPO_A2)

    TEST "A crafts like with no payload file"
    exec (
        ENV .. " git -C " .. REPO_A2
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
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
    exec(EXE_A .. " chains add err-lua init " .. GEN_1)
    exec(EXE_A .. " chain err-lua post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-lua clone " .. REPO_A3)

    TEST "A crafts like with invalid lua metadata"
    exec("mkdir -p " .. REPO_A3 .. ".freechains/likes/")
    local f = io.open(REPO_A3 .. ".freechains/likes/like-err.lua", "w")
    f:write("not valid lua !!!\n")
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A3
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A3
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
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
    exec(EXE_A .. " chains add err-table init " .. GEN_1)
    exec(EXE_A .. " chain err-table post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-table clone " .. REPO_A4)

    TEST "A crafts like with invalid lua metadata"
    exec("mkdir -p " .. REPO_A4 .. ".freechains/likes/")
    local f = io.open(REPO_A4 .. ".freechains/likes/like-err.lua", "w")
    f:write("return 10\n")
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A4
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A4
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
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
    exec(EXE_A .. " chains add err-target init " .. GEN_1)
    local post = exec(EXE_A .. " chain err-target post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-target clone " .. REPO_A5)

    TEST "A crafts like with bad target type"
    exec("mkdir -p " .. REPO_A5 .. ".freechains/likes/")
    local f = io.open(REPO_A5 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="xxx", id="'..post..'", number=1000 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A5
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A5
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
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
    exec(EXE_A .. " chains add err-post init " .. GEN_1)
    exec(EXE_A .. " chain err-post post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-post clone " .. REPO_A6)

    TEST "A crafts like targeting nonexistent post"
    exec("mkdir -p " .. REPO_A6 .. ".freechains/likes/")
    local f = io.open(REPO_A6 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="post", id="0000000000000000000000000000000000000000", number=1000 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A6
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A6
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
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
    exec(EXE_A .. " chains add err-reps init " .. GEN_1)
    local post = exec(EXE_A .. " chain err-reps post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-reps clone " .. REPO_A7)

    TEST "A crafts like signed by non-pioneer (0 reps)"
    exec("mkdir -p " .. REPO_A7 .. ".freechains/likes/")
    local f = io.open(REPO_A7 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="post", id="'..post..'", number=1000 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A7
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A7
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=ssh"
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
    exec(EXE_A .. " --now=10000 chains add err-time init " .. GEN_1)
    local post = exec(EXE_A .. " --now=11000 chain err-time post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-time clone " .. REPO_A8)

    TEST "A crafts like with old timestamp"
    exec("mkdir -p " .. REPO_A8 .. ".freechains/likes/")
    local f = io.open(REPO_A8 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="post", id="'..post..'", number=1000 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A8
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A8
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
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

-- sync rejects like with fractional number
do
    print("==> sync rejects like with fractional number")

    local REPO_A9 = ROOT_A .. "/chains/err-frac/"
    local REPO_B9 = ROOT_B .. "/chains/err-frac/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-frac init " .. GEN_1)
    local post = exec(EXE_A .. " chain err-frac post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-frac clone " .. REPO_A9)

    TEST "A crafts like with fractional number"
    exec("mkdir -p " .. REPO_A9 .. ".freechains/likes/")
    local f = io.open(REPO_A9 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="post", id="'..post..'", number=0.5 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A9
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A9
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " commit -S -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A9 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects like with fractional number on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-frac sync recv " .. REPO_A9
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : invalid number : expects non-zero integer"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects like with zero number
do
    print("==> sync rejects like with zero number")

    local REPO_A10 = ROOT_A .. "/chains/err-zero/"
    local REPO_B10 = ROOT_B .. "/chains/err-zero/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-zero init " .. GEN_1)
    local post = exec(EXE_A .. " chain err-zero post inline 'legit' --sign " .. KEY1)

    TEST "B clones from A"
    exec(EXE_B .. " chains add err-zero clone " .. REPO_A10)

    TEST "A crafts like with zero number"
    exec("mkdir -p " .. REPO_A10 .. ".freechains/likes/")
    local f = io.open(REPO_A10 .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="post", id="'..post..'", number=0 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_A10
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_A10
        .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh"
        .. " commit -S -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_A10 .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "B rejects like with zero number on sync"
    local _,Q,err = exec (true,
        EXE_B .. " chain err-zero sync recv " .. REPO_A10
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : invalid like : invalid number : expects non-zero integer"
        , "should fail: " .. tostring(err)
    )
end

-- sync rejects post with forged signature
do
    print("==> sync rejects forged signature post")

    local REPO_A3 = ROOT_A .. "/chains/err-forge/"
    local REPO_B3 = ROOT_B .. "/chains/err-forge/"

    TEST "A creates chain + post"
    exec(EXE_A .. " chains add err-forge init " .. GEN_1)
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

print("<== ALL PASSED")
