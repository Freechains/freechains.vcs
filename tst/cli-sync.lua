#!/usr/bin/env lua5.4

require "tests"
local ssh = require "freechains.chain.ssh"

local ROOT_A = ROOT .. "/cli-sync/A/"
local ROOT_B = ROOT .. "/cli-sync/B/"
local ROOT_C = ROOT .. "/cli-sync/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"
local REPO_C = ROOT_C .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)
exec("mkdir -p " .. ROOT_C)

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

        TEST "pubkey matches pioneer key"
        local hash = exec("git -C " .. REPO_A .. " rev-parse HEAD~1")
        local pk = ssh.verify(REPO_A, hash)
        assert(pk == PUB1, "pubkey mismatch: [" .. tostring(pk) .. "] vs [" .. PUB1 .. "]")
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
                EXE_A .. " --now=8000 chain test reps author '" .. PUB1 .. "'"
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
                EXE_A .. " --now=8000 chain test reps author '" .. PUB1 .. "'"
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
                EXE_B .. " --now=8500 chain test reps author '" .. PUB1 .. "'"
            ))),
            post = tonumber((exec (
                EXE_B .. " --now=8500 chain test reps post " .. A
            ))),
        }
        assert(b.author == aft.author, "author reps: A=" .. aft.author .. " B=" .. b.author)
        assert(b.post   == aft.post,   "post reps: A=" .. aft.post .. " B=" .. b.post)
    end
end

-- 5. recv unrelated histories
do
    print("==> Step 5: recv unrelated histories")

    TEST "C creates independent chain"
    exec(EXE_C .. " --now=1000 chains add test init " .. GEN_1)
    exec (
        EXE_C .. " --now=2000 chain test post inline 'post from C' --sign " .. KEY1
    )

    TEST "B's HEAD before recv"
    local before = exec("git -C " .. REPO_B .. " rev-parse HEAD")

    TEST "B recvs from C fails with unrelated histories"
    local _, Q, err = exec (true,
        EXE_B .. " --now=9000 chain test sync recv " .. REPO_C
    )
    assert (
        Q~=0 and err=="ERROR : chain sync : incompatible genesis"
        , "should fail: " .. tostring(err)
    )

    TEST "B's HEAD unchanged"
    local after = exec("git -C " .. REPO_B .. " rev-parse HEAD")
    assert(before == after, "B's HEAD changed: " .. before .. " vs " .. after)
end

-- 6a. recv conflict — local wins (loser = remote)
do
    print("==> Step 6a: recv conflict — local wins")

    TEST "A creates conflict-a chain + seeds shared.txt"
    exec(EXE_A .. " --now=9000 chains add conflict-a init " .. GEN_1)
    exec (
        EXE_A .. " --now=9100 chain conflict-a post inline 'seed\n' --file shared.txt --sign " .. KEY1
    )

    TEST "B clones conflict-a"
    exec(EXE_B .. " chains add conflict-a clone " .. ROOT_A .. "/chains/conflict-a/")

    TEST "A appends alpha (earlier)"
    exec (
        EXE_A .. " --now=10000 chain conflict-a post inline 'alpha\n' --file shared.txt --sign " .. KEY1
    )

    TEST "B appends beta (later)"
    exec (
        EXE_B .. " --now=11000 chain conflict-a post inline 'beta\n' --file shared.txt --sign " .. KEY1
    )

    TEST "A recvs from B (A wins)"
    exec (
        EXE_A .. " --now=12000 chain conflict-a sync recv " .. ROOT_B .. "/chains/conflict-a/"
    )

    TEST "A's shared.txt has alpha, not beta"
    local h = io.open(ROOT_A .. "/chains/conflict-a/shared.txt")
    local content = h:read("a")
    h:close()
    assert(content:match("alpha"), "alpha missing: " .. content)
    assert(not content:match("beta"), "beta should be discarded: " .. content)

    TEST "A's posts.lua has only the winning post"
    local posts = dofile(ROOT_A .. "/chains/conflict-a/.freechains/state/posts.lua")
    local n = 0
    for _ in pairs(posts) do n = n + 1 end
    -- seed + alpha, beta discarded
    assert(n == 2, "expected 2 posts (seed+alpha), got " .. n)
end

-- 6b. recv conflict — remote wins (loser = local, deferred)
do
    print("==> Step 6b: recv conflict — remote wins (deferred)")

    TEST "A creates conflict-b chain + seeds shared.txt"
    exec(EXE_A .. " --now=9000 chains add conflict-b init " .. GEN_1)
    exec (
        EXE_A .. " --now=9100 chain conflict-b post inline 'seed\n' --file shared.txt --sign " .. KEY1
    )

    TEST "B clones conflict-b"
    exec(EXE_B .. " chains add conflict-b clone " .. ROOT_A .. "/chains/conflict-b/")

    TEST "A appends alpha (later)"
    exec (
        EXE_A .. " --now=11000 chain conflict-b post inline 'alpha\n' --file shared.txt --sign " .. KEY1
    )

    TEST "B appends beta (earlier)"
    exec (
        EXE_B .. " --now=10000 chain conflict-b post inline 'beta\n' --file shared.txt --sign " .. KEY1
    )

    TEST "A recvs from B (B wins, A is local loser — deferred)"
    local _, Q, err = exec (true,
        EXE_A .. " --now=12000 chain conflict-b sync recv " .. ROOT_B .. "/chains/conflict-b/"
    )
    assert (
        Q ~= 0 and err == "ERROR : chain sync : TODO local loser rewrite"
        , "should fail: " .. tostring(err)
    )
end

print("<== ALL PASSED")
