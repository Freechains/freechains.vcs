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
        exec(EXE_A .. " --now=1000 chains add test init " .. GEN_1)
        local out = exec (
            EXE_A .. " --now=2000 chain test post inline 'post from A' --sign " .. KEY1
        )
        assert(#out == 40, "hash: " .. out)

        TEST "B clones"
        exec(EXE_B .. " chains add test clone " .. REPO_A)
    end
    -- A:  [state] genesis ── [post] P1 ── [state] S1
    -- B:  [state] genesis ── [post] P1 ── [state] S1

    do
        TEST "A posts again"
        local out = exec (
            EXE_A .. " --now=3000 chain test post inline 'second from A' --sign " .. KEY1
        )
        assert(#out == 40, "hash: " .. out)

        TEST "GF matches pioneer key"
        local gf = exec(ENV .. " git -C " .. REPO_A .. " log -1 --format='%GF' HEAD~1")
        assert(gf == KEY1, "GF mismatch: [" .. gf .. "] vs [" .. KEY1 .. "]")
    end
    -- A:  [state] genesis ── [post] P1 ── [state] S1 ── [post] P2 ── [state] S2
    -- B:  [state] genesis ── [post] P1 ── [state] S1

    do
        TEST "B recvs from A"
        exec(EXE_B .. " --now=3500 chain test sync recv " .. REPO_A)

        TEST "B has A's latest post"
        local A = exec("git -C " .. REPO_A .. " rev-parse HEAD")
        local B = exec("git -C " .. REPO_B .. " rev-parse HEAD")
        assert (A == B,
            "heads should be equal: " .. A .. " vs " .. B
        )
    end
    -- A:  [state] genesis ── [post] P1 ── [state] S1 ── [post] P2 ── [state] S2
    -- B:  [state] genesis ── [post] P1 ── [state] S1 ── [post] P2 ── [state] S2
end

-- 2. recv bidirectional
do
    print("==> Step 2: recv bidirectional")

    do
        TEST "A posts"
        local out = exec (
            EXE_A .. " --now=4000 chain test post inline 'third from A' --sign " .. KEY1
        )
        assert(#out == 40, "hash: " .. out)

        TEST "B recvs from A"
        exec(EXE_B .. " --now=4500 chain test sync recv " .. REPO_A)
    end
    -- A:  genesis ── P1 ── S1 ── P2 ── S2 ── [post] P3 ── [state] S3
    -- B:  genesis ── P1 ── S1 ── P2 ── S2 ── [post] P3 ── [state] S3

    do
        TEST "B posts"
        local out = exec (
            EXE_B .. " --now=5000 chain test post inline 'first from B' --sign " .. KEY1
        )
        assert(#out == 40, "hash: " .. out)

        TEST "A recvs from B"
        exec(EXE_A .. " --now=5500 chain test sync recv " .. REPO_B)
    end
    -- A:  genesis ── ... ── S3 ── [post] P4 ── [state] S4
    -- B:  genesis ── ... ── S3 ── [post] P4 ── [state] S4

    do
        TEST "A and B are equal"
        local _, ok = exec (true,
            "diff -r --exclude=.git " .. REPO_A .. " " .. REPO_B
        )
        assert(ok == 0, "A and B should not differ")
    end
    -- A:  genesis ── ... ── S3 ── [post] P4 ── [state] S4
    -- B:  genesis ── ... ── S3 ── [post] P4 ── [state] S4
end

-- 3. recv divergent + consensus
do
    print("==> Step 3: recv divergent")

    local A, B

    -- A,B posts independently
    do
        TEST "A posts (diverge)"
        A = exec (
            EXE_A .. " --now=6000 chain test post inline 'fourth from A' --sign " .. KEY1
        )
        assert(#A == 40, "hash: " .. A)

        TEST "B posts (diverge)"
        B = exec (
            EXE_B .. " --now=7000 chain test post inline 'second from B' --sign " .. KEY1
        )
        assert(#B == 40, "hash: " .. B)
    end
    -- A:  genesis ── ... ── S4 ── [post] P5 ── [state] S5
    -- B:  genesis ── ... ── S4 ── [post] P6 ── [state] S6

    -- A <-- B
    do
        TEST "A recvs from B"
        exec(EXE_A .. " --now=7500 chain test sync recv " .. REPO_B)

        TEST "no wall-clock timestamps"
        local out = exec("git -C " .. REPO_A .. " log --format=%at")
        for ts in out:gmatch("%d+") do
            assert(tonumber(ts) <= 10000, "wall-clock leak: " .. ts)
        end

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
    --                             ┌── [post] P5 ── [state] S5
    -- A:  genesis ── ... ── S4 ── [merge] (amend w/ state)
    --                             └── [post] P6 ── [state] S6
    -- B:  genesis ── ... ── S4 ── [post] P6 ── [state] S6

    -- B <-- A
    do
        TEST "B recvs from A"
        exec(EXE_B .. " --now=7500 chain test sync recv " .. REPO_A)

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
            "diff -r --exclude=.git " .. REPO_A .. " " .. REPO_B
        )
        assert(ok == 0, "A and B should not differ")
    end
    --                             ┌── [post] P5 ── [state] S5
    -- A:  genesis ── ... ── S4 ── [merge] (amend w/ state)
    --                             └── [post] P6 ── [state] S6
    -- B:  same as A (FF recv)
end

-- 4. recv with like
do
    print("==> Step 4: recv like")

    local A
    do
        local posts = dofile(REPO_A .. ".freechains/state/posts.lua")
        for k in pairs(posts) do
            A = k
            break
        end
        assert(A, "need a post hash from previous steps")
    end

    do
        TEST "A likes a post"

        local bef = {
            author = tonumber((exec (
                EXE_A .. " --now=8000 chain test reps author '" .. PUB1 .. "'
            ))),
            post = tonumber((exec (
                EXE_A .. " --now=8000 chain test reps post " .. A
            ))),
        }
        assert(bef.author==29, "bef.author expected 29, got " .. bef.author)
        assert(bef.post  == 0, "bef.post expected 0, got " .. bef.post)

        exec (
            EXE_A .. " --now=8000 chain test like 5 post " .. A .. " --sign " .. KEY1
        )

        local aft = {
            author = tonumber((exec (
                EXE_A .. " --now=8000 chain test reps author '" .. PUB1 .. "'
            ))),
            post = tonumber((exec (
                EXE_A .. " --now=8000 chain test reps post " .. A
            ))),
        }
        assert(aft.author == 28, "aft.author expected 28, got " .. aft.author)
        assert(aft.post   == 3,  "aft.post expected 3, got " .. aft.post)

        TEST "B recvs from A (with like)"
        exec(EXE_B .. " --now=8500 chain test sync recv " .. REPO_A)

        TEST "B reflects like"
        local b = {
            author = tonumber((exec (
                EXE_B .. " --now=8500 chain test reps author '" .. PUB1 .. "'
            ))),
            post = tonumber((exec (
                EXE_B .. " --now=8500 chain test reps post " .. A
            ))),
        }
        assert(b.author == aft.author, "author reps: A=" .. aft.author .. " B=" .. b.author)
        assert(b.post   == aft.post,   "post reps: A=" .. aft.post .. " B=" .. b.post)
    end
end

print("<== ALL PASSED")
