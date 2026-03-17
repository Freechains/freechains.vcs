#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-begs/"

exec(ENV_EXE .. " chains add cli-begs dir " .. GEN_1P)

-- 1. Simple beg
do
    print("==> Simple beg")

    local HEAD_BEFORE = exec("git -C " .. DIR .. " rev-parse HEAD")

    local BEG
    do
        TEST "beg-post-succeeds"
        local out, code = exec (
            ENV_EXE .. " chain cli-begs post inline 'please help' --beg --sign " .. KEY2
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
        BEG = out

        TEST "beg-not-on-head"
        local head = exec("git -C " .. DIR .. " rev-parse HEAD")
        assert(head == HEAD_BEFORE, "HEAD should not advance: " .. head .. " vs " .. HEAD_BEFORE)
    end

    do
        TEST "beg-on-ref"
        local out = exec (
            "git -C " .. DIR .. " for-each-ref refs/begs/ --format='%(objectname)'"
        )
        assert(out:match(BEG), "beg hash not found in refs/begs/: " .. out)
    end

    do
        TEST "beg-blocked-in-posts"
        local posts = dofile(DIR .. ".freechains/posts.lua")
        local blob = exec (true,
            "git -C " .. DIR .. " diff-tree --no-commit-id --name-only -r " .. BEG .. " -- '*.txt'"
        )
        local hash = exec (true,
            "git -C " .. DIR .. " show " .. BEG .. ":" .. blob .. " | git hash-object --stdin"
        )
        assert(posts[hash], "post entry not found for blob: " .. hash)
        assert(posts[hash].blocked == true, "blocked should be true")
    end
end

-- 2. Multiple begs from HEAD
do
    print("==> Multiple begs from HEAD")

    exec("rm -rf " .. TMP)
    exec("mkdir -p " .. ROOT)
    exec(ENV_EXE .. " chains add cli-begs dir " .. GEN_1P)

    local HEAD_BEFORE = exec("git -C " .. DIR .. " rev-parse HEAD")

    do
        TEST "beg-multiple-from-head"
        local out1, code1 = exec (
            ENV_EXE .. " chain cli-begs post inline 'beg from key2' --beg --sign " .. KEY2
        )
        assert(code1 == 0, "beg1 exit code: " .. tostring(code1))

        local out2, code2 = exec (
            ENV_EXE .. " chain cli-begs post inline 'beg from key3' --beg --sign " .. KEY3
        )
        assert(code2 == 0, "beg2 exit code: " .. tostring(code2))

        local head = exec("git -C " .. DIR .. " rev-parse HEAD")
        assert(head == HEAD_BEFORE, "HEAD should not advance: " .. head .. " vs " .. HEAD_BEFORE)
    end

    do
        TEST "beg-refs-count"
        local out = exec (
            "git -C " .. DIR .. " for-each-ref refs/begs/ --format='%(refname)'"
        )
        local count = 0
        for _ in out:gmatch("[^\n]+") do count = count + 1 end
        assert(count == 2, "expected 2 refs/begs/, got: " .. count)
    end
end

-- 3. Multiple begs from different heads
do
    print("==> Multiple begs from different heads")

    exec("rm -rf " .. TMP)
    exec("mkdir -p " .. ROOT)
    exec(ENV_EXE .. " chains add cli-begs dir " .. GEN_1P)

    -- KEY posts normally (advances HEAD)
    exec(ENV_EXE .. " chain cli-begs post inline 'normal post 1' --sign " .. KEY)
    local HEAD1 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- KEY2 begs from HEAD1
    local BEG1 = exec (
        ENV_EXE .. " chain cli-begs post inline 'beg from head1' --beg --sign " .. KEY2
    )

    -- KEY posts again (advances HEAD)
    exec(ENV_EXE .. " chain cli-begs post inline 'normal post 2' --sign " .. KEY)
    local HEAD2 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- KEY3 begs from HEAD2
    local BEG2 = exec (
        ENV_EXE .. " chain cli-begs post inline 'beg from head2' --beg --sign " .. KEY3
    )

    do
        TEST "beg-different-parents"
        local parent1 = exec("git -C " .. DIR .. " log -1 --format=%P " .. BEG1)
        local parent2 = exec("git -C " .. DIR .. " log -1 --format=%P " .. BEG2)
        assert(parent1 == HEAD1, "beg1 parent: " .. parent1 .. " expected: " .. HEAD1)
        assert(parent2 == HEAD2, "beg2 parent: " .. parent2 .. " expected: " .. HEAD2)
        assert(parent1 ~= parent2, "parents should differ")
    end
end

-- 4. Likes on begs
do
    print("==> Likes on begs")

    exec("rm -rf " .. TMP)
    exec("mkdir -p " .. ROOT)
    exec(ENV_EXE .. " chains add cli-begs dir " .. GEN_1P)

    -- KEY2 begs
    local BEG = exec (
        ENV_EXE .. " chain cli-begs post inline 'please accept me' --beg --sign " .. KEY2
    )

    local HEAD_BEFORE = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- get ref name for later checks
    local REF = exec (
        "git -C " .. DIR .. " for-each-ref refs/begs/ --format='%(refname)'"
    )

    local LIKE
    do
        TEST "like-beg-succeeds"
        local out, code = exec (
            ENV_EXE .. " chain cli-begs like 1 post " .. BEG .. " --sign " .. KEY
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        LIKE = out
    end

    do
        TEST "like-beg-merges"
        local head = exec("git -C " .. DIR .. " rev-parse HEAD")
        assert(head ~= HEAD_BEFORE, "HEAD should advance after merge")
    end

    do
        TEST "like-beg-unblocks"
        local posts = dofile(DIR .. ".freechains/posts.lua")
        local blob = exec (true,
            "git -C " .. DIR .. " diff-tree --no-commit-id --name-only -r " .. BEG .. " -- '*.txt'"
        )
        local hash = exec (true,
            "git -C " .. DIR .. " show " .. BEG .. ":" .. blob .. " | git hash-object --stdin"
        )
        assert(posts[hash], "post entry not found for blob: " .. hash)
        assert(posts[hash].blocked ~= true, "blocked should no longer be true")
    end

    do
        TEST "like-beg-ref-removed"
        local out = exec (
            "git -C " .. DIR .. " for-each-ref refs/begs/ --format='%(refname)'"
        )
        assert(out == "" or not out:match(REF), "ref should be removed: " .. out)
    end

    do
        TEST "like-beg-insufficient-reps"
        -- fresh beg for this test
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add cli-begs dir " .. GEN_1P)

        local beg = exec (
            ENV_EXE .. " chain cli-begs post inline 'another beg' --beg --sign " .. KEY2
        )

        -- KEY3 has 0 reps, should fail to like
        local ok, code, out = exec ('stderr',
            ENV_EXE .. " chain cli-begs like 1 post " .. beg .. " --sign " .. KEY3
        )
        assert(code ~= 0, "should fail: KEY3 has no reps")
    end

    do
        TEST "like-beg-self-like-no-reps"
        -- KEY2 begged (0 reps), tries to like own beg
        local refs = exec (
            "git -C " .. DIR .. " for-each-ref refs/begs/ --format='%(objectname)'"
        )
        local beg = refs:match("%x+")

        local ok, code, out = exec ('stderr',
            ENV_EXE .. " chain cli-begs like 1 post " .. beg .. " --sign " .. KEY2
        )
        assert(code ~= 0, "should fail: KEY2 has 0 reps, cannot like own beg")
    end
end

-- 5. Merge structure
do
    print("==> Merge structure")

    exec("rm -rf " .. TMP)
    exec("mkdir -p " .. ROOT)
    exec(ENV_EXE .. " chains add cli-begs dir " .. GEN_1P)

    -- KEY2 begs
    local BEG = exec (
        ENV_EXE .. " chain cli-begs post inline 'merge test beg' --beg --sign " .. KEY2
    )
    local MAIN_BEFORE = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- KEY likes the beg (triggers merge)
    exec(ENV_EXE .. " chain cli-begs like 1 post " .. BEG .. " --sign " .. KEY)

    local MERGE = exec("git -C " .. DIR .. " rev-parse HEAD")

    do
        TEST "merge-has-two-parents"
        local parents = exec("git -C " .. DIR .. " log -1 --format=%P " .. MERGE)
        local count = 0
        for _ in parents:gmatch("%x+") do count = count + 1 end
        assert(count == 2, "merge should have 2 parents, got: " .. count)
    end

    do
        TEST "merge-preserves-beg-sig"
        local _, code = exec (
            ENV .. " git -C " .. DIR .. " verify-commit " .. BEG
        )
        assert(code == 0, "beg commit signature should be intact")
    end

    do
        TEST "merge-head-advances"
        assert(MERGE ~= MAIN_BEFORE, "HEAD should be merge commit, not old HEAD")
    end
end

exec("rm -rf " .. TMP)

print("<== ALL PASSED")
