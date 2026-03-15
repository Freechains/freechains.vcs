#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/repl-local/A/"
local ROOT_B = ROOT .. "/repl-local/B/"
local ROOT_C = ROOT .. "/repl-local/C/"

local EXE_A  = ENV .. " ../src/freechains --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains --root " .. ROOT_C

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"
local REPO_C = ROOT_C .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)
exec("mkdir -p " .. ROOT_C)

-- HOST A: create chain + post
local CHAIN_HASH

do
    print("==> Host A: create chain + post")

    do
        TEST "chain created"
        CHAIN_HASH = exec (
            EXE_A .. " chains add test dir " .. GEN
        )
        assert(#CHAIN_HASH == 40, "hash: " .. CHAIN_HASH)
        assert(CHAIN_HASH:match("^%x+$"), "not hex")
    end

    do
        TEST "post on A"
        local out = exec (
            EXE_A .. " chain test post inline 'post from A'"
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
        git_config(REPO_B)
        exec (
            "mkdir -p " .. REPO_B .. ".freechains/local"
        )
        do
            local f = io.open(REPO_B .. ".freechains/local/now.lua", "w")
            f:write("return 0\n")
            f:close()
        end
        do
            local f = io.open(REPO_B .. ".git/info/exclude", "a")
            f:write(".freechains/local/\n")
            f:close()
        end
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
            EXE_B .. " chain test post inline 'post from B'"
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

-- HOST A: fetch+merge from B
do
    print("==> Host A: fetch+merge from B")

    do
        TEST "fetch from B"
        local branch = exec (
            "git -C " .. REPO_A .. " rev-parse --abbrev-ref HEAD"
        )
        local _, code = exec (
            "git -C " .. REPO_A .. " fetch " .. REPO_B .. " " .. branch
        )
        assert(code == 0, "fetch failed")

        TEST "dry-run merge ok"
        local _, code = exec (
            "git -C " .. REPO_A .. " merge --no-commit --no-ff FETCH_HEAD"
        )
        assert(code == 0, "dry-run merge failed")
        local _, code = exec (
            "git -C " .. REPO_A .. " merge --abort"
        )
        assert(code == 0, "abort failed")

        TEST "merge from B"
        exec (
            "git -C " .. REPO_A .. " merge --no-edit FETCH_HEAD"
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
        local h = io.popen("cat " .. REPO_A .. "*.txt")
        local all = h:read("a")
        h:close()
        assert(all:match("post from A"), "A's post missing")
        assert(all:match("post from B"), "B's post missing")
    end

    do
        TEST "A and B are equal"
        local _,ok = exec ('stderr',
            "diff -r --exclude=.git --exclude=local " .. REPO_A .. " " .. REPO_B
        )
        assert(ok==0, "A and B differ")
    end
end

-- BIDIRECTIONAL SYNC: both post, A merges B, B merges A
do
    print("==> Bidirectional sync")

    do
        TEST "A posts again"
        local out = exec (
            EXE_A .. " chain test post inline 'second from A'"
        )
        assert(#out == 40, "hash: " .. out)

        TEST "B posts again"
        local out = exec (
            EXE_B .. " chain test post inline 'second from B'"
        )
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "A fetches from B"
        local branch = exec (
            "git -C " .. REPO_A .. " rev-parse --abbrev-ref HEAD"
        )
        local _, code = exec (
            "git -C " .. REPO_A .. " fetch " .. REPO_B .. " " .. branch
        )
        assert(code == 0, "fetch failed")

        TEST "A dry-run merge ok"
        local _, code = exec (
            "git -C " .. REPO_A .. " merge --no-commit --no-ff FETCH_HEAD"
        )
        assert(code == 0, "dry-run merge failed")
        local _, code = exec (
            "git -C " .. REPO_A .. " merge --abort"
        )
        assert(code == 0, "abort failed")

        TEST "A merges B (true merge)"
        exec (
            "git -C " .. REPO_A .. " merge --no-edit FETCH_HEAD"
        )

        TEST "A has 6 commits"
        local count = exec (
            "git -C " .. REPO_A .. " rev-list --count HEAD"
        )
        assert(count == "6", "count: " .. count)
    end

    do
        TEST "B fetches from A"
        local branch = exec (
            "git -C " .. REPO_B .. " rev-parse --abbrev-ref HEAD"
        )
        local _, code = exec (
            "git -C " .. REPO_B .. " fetch " .. REPO_A .. " " .. branch
        )
        assert(code == 0, "fetch failed")

        TEST "B dry-run merge ok"
        local _, code = exec (
            "git -C " .. REPO_B .. " merge --no-commit --no-ff FETCH_HEAD"
        )
        assert(code == 0, "dry-run merge failed")
        local _, code = exec (
            "git -C " .. REPO_B .. " merge --abort"
        )
        assert(code == 0, "abort failed")

        TEST "B merges A (fast-forward)"
        exec (
            "git -C " .. REPO_B .. " merge --no-edit FETCH_HEAD"
        )

        TEST "B has 6 commits"
        local count = exec (
            "git -C " .. REPO_B .. " rev-list --count HEAD"
        )
        assert(count == "6", "count: " .. count)
    end

    do
        TEST "A and B are equal after bidirectional sync"
        local _, ok = exec ('stderr',
            "diff -r --exclude=.git --exclude=local " .. REPO_A .. " " .. REPO_B
        )
        assert(ok == 0, "A and B differ")
    end
end

-- UNRELATED HISTORIES: independent chain creation must fail sync
do
    print("==> Unrelated histories rejected")

    local h = exec (
        EXE_C .. " chains add test dir " .. GEN
    )
    assert(h ~= CHAIN_HASH, "should differ")

    do
        TEST "fetch from unrelated chain succeeds"
        local branch = exec (
            "git -C " .. REPO_C .. " rev-parse --abbrev-ref HEAD"
        )
        local _, code = exec (
            "git -C " .. REPO_C .. " fetch " .. REPO_A .. " " .. branch
        )
        assert(code == 0, "fetch should succeed")

        TEST "dry-run merge from unrelated chain fails"
        local _, code = exec (
            "git -C " .. REPO_C .. " merge --no-commit --no-ff FETCH_HEAD"
        )
        assert(code ~= 0, "should reject unrelated histories")
    end
end

-- CONFLICT: both post to same file independently
do
    print("==> Conflict: both post to log.txt")

    do
        TEST "A posts to log.txt"
        local out = exec (
            EXE_A .. " chain test post" .. " inline 'from A' --file log.txt"
        )
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "B posts to log.txt"
        local out = exec (
            EXE_B .. " chain test post" .. " inline 'from B' --file log.txt"
        )
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "fetch succeeds"
        local branch = exec (
            "git -C " .. REPO_A .. " rev-parse --abbrev-ref HEAD"
        )
        local _, code = exec (
            "git -C " .. REPO_A .. " fetch " .. REPO_B .. " " .. branch
        )
        assert(code == 0, "fetch should succeed")

        TEST "dry-run merge fails with conflict"
        local _, code = exec (
            "git -C " .. REPO_A .. " merge --no-commit --no-ff FETCH_HEAD"
        )
        assert(code ~= 0, "should fail with conflict")
        local _, code = exec (
            "git -C " .. REPO_A .. " merge --abort"
        )
        assert(code == 0, "abort failed")

        TEST "merge fails with conflict"
        local _, code = exec (
            "git -C " .. REPO_A .. " merge --no-edit FETCH_HEAD"
        )
        assert(code ~= 0, "should fail with conflict")
    end

    do
        TEST "log.txt has conflict markers"
        local h = io.open(REPO_A .. "log.txt")
        local content = h:read("a")
        h:close()
        assert(
            content:match("<<<<<<<"),
            "no conflict markers"
        )
    end

    do
        TEST "abort merge restores clean state"
        local _, code = exec (
            "git -C " .. REPO_A .. " merge --abort"
        )
        assert(code == 0, "abort failed")
        local h = io.open(REPO_A .. "log.txt")
        local content = h:read("a")
        h:close()
        assert(
            content == "from A\n",
            "content: " .. content
        )
    end
end

print("<== ALL PASSED")
