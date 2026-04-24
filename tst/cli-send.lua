#!/usr/bin/env lua5.4

require "tests"
local ssh = require "freechains.chain.ssh"

local ROOT_A = ROOT .. "/cli-sync/A/"
local ROOT_B = ROOT .. "/cli-sync/B/"
local ROOT_C = ROOT .. "/cli-sync/C/"
local ROOT_X = ROOT .. "/cli-sync/X/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C
local EXE_X  = ENV .. " ../src/freechains.lua --root " .. ROOT_X

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"
local REPO_C = ROOT_C .. "/chains/test/"
local REPO_X = ROOT_X .. "/chains/test/"


exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)
exec("mkdir -p " .. ROOT_C)
exec("mkdir -p " .. ROOT_X)

-- 1. create/clone + pre-receive hook installed + rejects non-main
do
    print("==> Step 1: create/clone + pre-receive hook")

    TEST "A creates chain"
    exec(EXE_A .. " --now=1000 chains add test init " .. GEN_1)

    TEST "B clones"
    exec(EXE_B .. " chains add test clone " .. REPO_A)

    TEST "A has executable pre-receive hook"
    local _, ok = exec (true,
        "test -x " .. REPO_A .. ".git/hooks/pre-receive"
    )
    assert(ok == 0, "A hook missing or not executable")

    TEST "B has executable pre-receive hook"
    local _, ok = exec (true,
        "test -x " .. REPO_B .. ".git/hooks/pre-receive"
    )
    assert(ok == 0, "B hook missing or not executable")

    TEST "reject push to refs/heads/hack"
    local _, ok, err = exec (true,
        "git -C " .. REPO_A .. " push " .. REPO_B .. " main:refs/heads/hack"
    )
    assert(ok ~= 0, "refs/heads/hack : push should have failed")
    assert (
        err and err:find("ERROR : chain sync : expected main branch"),
        "refs/heads/hack : unexpected stderr: " .. tostring(err)
    )

    TEST "reject push to refs/tags/v1"
    local _, ok, err = exec (true,
        "git -C " .. REPO_A .. " push " .. REPO_B .. " main:refs/tags/v1"
    )
    assert(ok ~= 0, "refs/tags/v1 : push should have failed")
    assert (
        err and err:find("ERROR : chain sync : expected main branch"),
        "refs/tags/v1 : unexpected stderr: " .. tostring(err)
    )

    TEST "reject push to refs/begs/foo"
    local _, ok, err = exec (true,
        "git -C " .. REPO_A .. " push " .. REPO_B .. " main:refs/begs/foo"
    )
    assert(ok ~= 0, "refs/begs/foo : push should have failed")
    assert (
        err and err:find("ERROR : chain sync : expected main branch"),
        "refs/begs/foo : unexpected stderr: " .. tostring(err)
    )

    TEST "reject multi-ref push"
    local _, ok, err = exec (true,
        "git -C " .. REPO_A .. " push " .. REPO_B .. " main:refs/heads/alpha main:refs/heads/beta"
    )
    assert(ok ~= 0, "multi-ref : push should have failed")
    assert (
        err and err:find("ERROR : chain sync : expected single branch"),
        "multi-ref : unexpected stderr: " .. tostring(err)
    )

    -- temp commit on A so next pushes trigger the hook
    exec (
        "git -C " .. REPO_A .. " commit --allow-empty -m 'tmp'"
    )

    TEST "reject push without freechains option"
    local _, ok, err = exec (true,
        "git -C " .. REPO_A .. " push " .. REPO_B .. " main"
    )
    assert(ok ~= 0, "push without options : should have failed")
    assert (
        err and err:find("ERROR : chain sync : missing freechains push option"),
        "no freechains option : unexpected stderr: " .. tostring(err)
    )

    TEST "reject push without url option"
    local _, ok, err = exec (true,
        "git -C " .. REPO_A .. " push -o freechains=true " .. REPO_B .. " main"
    )
    assert(ok ~= 0, "push without url : should have failed")
    assert (
        err and err:find("ERROR : chain sync : missing url push option"),
        "no url option : unexpected stderr: " .. tostring(err)
    )

    -- drop the temp commit
    exec (
        "git -C " .. REPO_A .. " reset --hard HEAD~1"
    )

    TEST "accept main:main no-op"
    exec (
        "git -C " .. REPO_A ..
        " push -o freechains=true -o url=" .. REPO_A .. " " ..
        REPO_B .. " main:refs/heads/main"
    )
end

-- 2. send rejects like from author with insufficient reputation
--    (based on tst/err-like.lua lines 268-308)
do
    print("==> Step 2: send rejects like with insufficient reps")

    TEST "X clones from A"
    exec(EXE_X .. " chains add test clone " .. REPO_A)

    TEST "X crafts malicious like signed by non-pioneer (0 reps)"
    exec("mkdir -p " .. REPO_X .. ".freechains/likes/")
    local f = io.open(REPO_X .. ".freechains/likes/like-err.lua", "w")
    f:write('return { target="author", id="'..PUB1..'", number=1000 }\n')
    f:close()
    exec (
        ENV .. " git -C " .. REPO_X
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=ssh"
        .. " add .freechains/likes/like-err.lua"
    )
    exec (
        ENV .. " git -C " .. REPO_X
        .. " -c user.signingkey=" .. KEY3 .. " -c gpg.format=ssh"
        .. " commit -S -m 'x' --trailer 'Freechains: like'"
    )
    exec (
        "git -C " .. REPO_X .. " commit -m 'x' --trailer 'Freechains: state' --allow-empty"
    )

    TEST "X sends to B: push should be rejected"
    local _, Q, err = exec (true,
        EXE_X .. " chain test sync send " .. REPO_B
    )
    assert (
        Q~=0 and err and err:find("ERROR : chain sync : invalid like : insufficient reputation"),
        "send should fail: " .. tostring(err)
    )
end

-- 3. A send after 1st post
do
    print("==> Step 3: A send after 1st post")

    TEST "A posts"
    local out = exec (
        EXE_A .. " --now=2000 chain test post inline 'post from A' --sign " .. KEY1
    )
    assert(#out == 40, "hash: " .. out)
    -- A:  [state] genesis ── [post] P1 ── [state] S1
    -- B:  [state] genesis

    TEST "A sends to B"
    exec(EXE_A .. " --now=2500 chain test sync send " .. REPO_B)

    TEST "B has A's latest post"
    local A = exec("git -C " .. REPO_A .. " rev-parse HEAD")
    local B = exec("git -C " .. REPO_B .. " rev-parse HEAD")
    assert (A == B,
        "heads should be equal: " .. A .. " vs " .. B
    )
    -- A:  [state] genesis ── [post] P1 ── [state] S1
    -- B:  [state] genesis ── [post] P1 ── [state] S1
end

-- 4. send bidirectional
do
    print("==> Step 4: send bidirectional")

    do
        TEST "A posts"
        local out = exec (
            EXE_A .. " --now=4000 chain test post inline 'third from A' --sign " .. KEY1
        )
        assert(#out == 40, "hash: " .. out)

        TEST "A sends to B"
        exec(EXE_A .. " --now=4500 chain test sync send " .. REPO_B)
    end
    -- A:  genesis ── P1 ── S1 ── P2 ── S2 ── [post] P3 ── [state] S3
    -- B:  genesis ── P1 ── S1 ── P2 ── S2 ── [post] P3 ── [state] S3

    do
        TEST "B posts"
        local out = exec (
            EXE_B .. " --now=5000 chain test post inline 'first from B' --sign " .. KEY1
        )
        assert(#out == 40, "hash: " .. out)

        TEST "B sends to A"
        exec(EXE_B .. " --now=5500 chain test sync send " .. REPO_A)
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

-- 5. recv divergent + consensus
do
    print("==> Step 5: recv divergent")

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

-- 6. recv with like
do
    print("==> Step 6: recv like")

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

-- 7. recv unrelated histories
do
    print("==> Step 7: recv unrelated histories")

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

print("<== ALL PASSED")
