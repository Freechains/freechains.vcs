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

        TEST "B clones"
        exec(EXE_B .. " chains add test clone " .. REPO_A)
    end

    do
        TEST "A posts again"
        local out = exec (
            EXE_A .. " chain test post inline 'second from A' --sign " .. KEY
        )
        assert(#out == 40, "hash: " .. out)

        TEST "GF matches pioneer key"
        local gf = exec(ENV .. " git -C " .. REPO_A .. " log -1 --format='%GF' HEAD")
        assert(gf == KEY, "GF mismatch: [" .. gf .. "] vs [" .. KEY .. "]")

        TEST "B recvs from A"
        exec(EXE_B .. " chain test sync recv " .. REPO_A)
    end

    do
        TEST "B has A's latest post"
        local A = exec("git -C " .. REPO_A .. " rev-parse HEAD")
        local B = exec("git -C " .. REPO_B .. " rev-parse HEAD")
        assert (A == B,
            "heads should be equal: " .. A .. " vs " .. B
        )
    end
end

-- 2. recv bidirectional
do
    print("==> Step 2: recv bidirectional")

    do
        TEST "A posts"
        local out = exec (
            EXE_A .. " chain test post inline 'third from A' --sign " .. KEY
        )
        assert(#out == 40, "hash: " .. out)

        TEST "B recvs from A"
        exec(EXE_B .. " chain test sync recv " .. REPO_A)
    end

    do
        TEST "B posts"
        local out = exec (
            EXE_B .. " chain test post inline 'first from B' --sign " .. KEY
        )
        assert(#out == 40, "hash: " .. out)

        TEST "A recvs from B"
        exec(EXE_A .. " chain test sync recv " .. REPO_B)
    end

    do
        TEST "A and B are equal"
        local _, ok = exec (true,
            "diff -r --exclude=.git --exclude=now.lua --exclude=authors.lua --exclude=posts.lua " .. REPO_A .. " " .. REPO_B
        )
        assert(ok == 0, "A and B should not differ")
    end
end

-- 3. recv divergent + consensus
do
    print("==> Step 3: recv divergent")

    local A, B

    -- A,B posts independently
    do
        TEST "A posts (diverge)"
        A = exec (
            EXE_A .. " chain test post inline 'fourth from A' --sign " .. KEY
        )
        assert(#A == 40, "hash: " .. A)

        TEST "B posts (diverge)"
        B = exec (
            EXE_B .. " chain test post inline 'second from B' --sign " .. KEY
        )
        assert(#B == 40, "hash: " .. B)
    end

    -- A <-- B
    do
        TEST "A recvs from B"
        exec(EXE_A .. " chain test sync recv " .. REPO_B)

        TEST "A has both post files"
        local h = io.popen("cat " .. REPO_A .. "*.txt")
        local all = h:read("a")
        h:close()
        assert(all:match("fourth from A"), "A's post missing")
        assert(all:match("second from B"), "B's post missing")

        TEST "A's posts.lua has both entries"
        local posts = dofile(REPO_A .. ".freechains/state/posts.lua")
        assert(posts[A], "A's should be in posts.lua")
        assert(posts[B], "B's should be in posts.lua")
    end

    -- B <-- A
    do
        TEST "B recvs from A"
        exec(EXE_B .. " chain test sync recv " .. REPO_A)

        TEST "B has both post files"
        local h = io.popen("cat " .. REPO_B .. "*.txt")
        local all = h:read("a")
        h:close()
        assert(all:match("fourth from A"), "A's post missing in B")
        assert(all:match("second from B"), "B's post missing in B")

        TEST "A and B have same authors.lua"
        local aa = dofile(REPO_A .. ".freechains/state/authors.lua")
        local ab = dofile(REPO_B .. ".freechains/state/authors.lua")
        for k, v in pairs(aa) do
            assert(ab[k], "author missing in B: " .. k)
            assert(ab[k].reps == v.reps, "reps mismatch for " .. k)
        end

        TEST "A and B have same posts.lua"
        local pa = dofile(REPO_A .. ".freechains/state/posts.lua")
        local pb = dofile(REPO_B .. ".freechains/state/posts.lua")
        for k, v in pairs(pa) do
            assert(pb[k], "post missing in B: " .. k)
            assert(pb[k].state == v.state, "state mismatch for " .. k)
        end
        for k, v in pairs(pb) do
            assert(pa[k], "post missing in A: " .. k)
        end

        TEST "A and B are bit-equal"
        local _, ok = exec(true,
            "diff -r --exclude=.git --exclude=now.lua " .. REPO_A .. " " .. REPO_B
        )
        assert(ok == 0, "A and B should not differ")
    end
end

-- TODO(a): 4. conflicts: same results in both sides
do
end

print("<== ALL PASSED")
