#!/usr/bin/env lua5.4
require "common"

local ROOT_A = ROOT .. "/repl-local/A/"
local ROOT_B = ROOT .. "/repl-local/B/"

local EXE_A  = ENV .. " ../src/freechains --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)

-- HOST A: create chain + post
local CHAIN_HASH

do
    print("==> Host A: create chain + post")

    os.execute("sleep 1")
    do
        TEST "chain created"
        CHAIN_HASH = exec (
            EXE_A .. " chains add test lua " .. GEN
        )
        assert(#CHAIN_HASH == 40, "hash: " .. CHAIN_HASH)
        assert(CHAIN_HASH:match("^%x+$"), "not hex")
    end

    do
        TEST "post on A"
        local out = exec (
            EXE_A
            .. " chain test post inline 'post from A'"
        )
        assert(#out == 40, "hash: " .. out)
        assert(out:match("^%x+$"), "not hex")
    end
end

do
    print("==> Host B: clone chain + post")

    do
        TEST "clone succeeds"
        exec (
            "mkdir -p " .. ROOT_B .. "/chains"
        )
        local tmp = ROOT_B .. "/chains/_tmp"
        exec (
            "git clone " .. REPO_A .. " " .. tmp
        )
        local hash = exec (
            "git -C " .. tmp .. " rev-list --max-parents=0 HEAD"
        )
        exec (
            "mv " .. tmp .. " " .. ROOT_B .. "/chains/" .. hash
        )
        exec (
            "ln -s " .. hash .. " " .. ROOT_B .. "/chains/test"
        )
    end

    do
        TEST "B has same genesis"
        local gen_a = exec (
            "git -C " .. REPO_A .. " rev-list --max-parents=0 HEAD"
        )
        local gen_b = exec (
            "git -C " .. REPO_B .. " rev-list --max-parents=0 HEAD"
        )
        assert(gen_a == gen_b, "genesis mismatch")
    end

    do
        TEST "B has 2 commits (genesis + A's post)"
        local count = exec (
            "git -C " .. REPO_B .. " rev-list --count HEAD"
        )
        assert(count == "2", "count: " .. count)
    end

    do
        TEST "post on B"
        local out = exec (
            EXE_B
            .. " chain test post inline 'post from B'"
        )
        assert(#out == 40, "hash: " .. out)
        assert(out:match("^%x+$"), "not hex")
    end

    do
        TEST "B has 3 commits (genesis + A + B)"
        local count = exec (
            "git -C " .. REPO_B .. " rev-list --count HEAD"
        )
        assert(count == "3", "count: " .. count)
    end
end

-- HOST A: pull from B
do
    print("==> Host A: pull from B")

    do
        TEST "pull from B"
        local branch = exec (
            "git -C " .. REPO_A .. " rev-parse --abbrev-ref HEAD"
        )
        exec (
            "git -C " .. REPO_A
            .. " -c user.name='-' -c user.email='-'"
            .. " pull --no-edit " .. REPO_B .. " " .. branch
        )
    end

    do
        TEST "A has 3 commits (genesis + A + B, fast-forward)"
        local count = exec(
            "git -C " .. REPO_A .. " rev-list --count HEAD"
        )
        assert(count == "3", "count: " .. count)
    end

    do
        TEST "both post files present in A"
        local a, b = false, false
        local h = io.open(REPO_A .. "/*.txt"):read'*a'
        h:close()
        a = all:match("post from A") ~= nil
        b = all:match("post from B") ~= nil
        assert(a, "A's post content missing")
        assert(b, "B's post content missing")
    end
end

-- UNRELATED HISTORIES: independent chain creation must fail sync
do
    print("==> Unrelated histories rejected")

    local ROOT_C = TMP .. "/root-C/"
    local EXE_C  = ENV .. " ../src/freechains --root " .. ROOT_C
    exec("mkdir -p " .. ROOT_C .. "/chains")

    os.execute("sleep 1")
    local hash_c = exec(
        EXE_C .. " chains add test lua " .. GEN
    )
    assert(hash_c ~= CHAIN_HASH, "should differ")

    local REPO_C = ROOT_C .. "/chains/" .. hash_c .. "/"

    do
        TEST "pull from unrelated chain fails"
        local branch = exec(
            "git -C " .. REPO_C
            .. " rev-parse --abbrev-ref HEAD"
        )
        local _, code = exec(
            "git -C " .. REPO_C
            .. " -c user.name='-' -c user.email='-'"
            .. " pull --no-rebase --no-edit "
            .. REPO_A .. " " .. branch
        )
        assert(code ~= 0, "should reject unrelated histories")
    end
end

print("<== ALL PASSED")
