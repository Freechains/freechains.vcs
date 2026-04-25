#!/usr/bin/env lua5.4

require "tests"
local ssh = require "freechains.chain.ssh"

local DIR1 = ROOT .. "/chains/cli-begs-1/"
local DIR2 = ROOT .. "/chains/cli-begs-2/"
local DIR3 = ROOT .. "/chains/cli-begs-3/"
local DIR4 = ROOT .. "/chains/cli-begs-4/"
local DIR5 = ROOT .. "/chains/cli-begs-5/"
local DIR6 = ROOT .. "/chains/cli-begs-6/"

-- 1. Simple beg
do
    print("==> Simple beg")
    exec(ENV_EXE .. " chains add cli-begs-1 init " .. GEN_1)

    local HEAD = exec("git -C " .. DIR1 .. " rev-parse HEAD")

    local BEG
    do
        TEST "beg-post-succeeds"
        local out, code = exec (
            ENV_EXE .. " chain cli-begs-1 post inline 'please help' --beg --sign " .. KEY2
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
        BEG = out
    end

    do
        TEST "beg-not-on-head"
        local head = exec("git -C " .. DIR1 .. " rev-parse HEAD")
        assert(head == HEAD, "HEAD should not advance: " .. head .. " vs " .. HEAD)
    end

    do
        TEST "beg-on-ref"
        local out = exec (
            "git -C " .. DIR1 .. " for-each-ref refs/begs/ --format='%(refname)'"
        )
        assert(out:match("refs/begs/beg%-" .. BEG), "beg ref not found: " .. out)
    end

    do
        TEST "beg-not-in-main-posts"
        local posts = dofile(DIR1 .. ".freechains/state/posts.lua")
        assert(not posts[BEG], "beg should not be in main posts.lua")
    end
end

-- 2. Multiple begs from HEAD
do
    print("==> Multiple begs from HEAD")
    exec(ENV_EXE .. " chains add cli-begs-2 init " .. GEN_1)

    local HEAD = exec("git -C " .. DIR2 .. " rev-parse HEAD")

    do
        TEST "beg-multiple-from-head"
        local out1, code1 = exec (
            ENV_EXE .. " chain cli-begs-2 post inline 'beg from key2' --beg --sign " .. KEY2
        )
        assert(code1 == 0, "beg1 exit code: " .. tostring(code1))

        local out2, code2 = exec (
            ENV_EXE .. " chain cli-begs-2 post inline 'beg from key3' --beg --sign " .. KEY3
        )
        assert(code2 == 0, "beg2 exit code: " .. tostring(code2))

        local head = exec("git -C " .. DIR2 .. " rev-parse HEAD")
        assert(head == HEAD, "HEAD should not advance: " .. head .. " vs " .. HEAD)

        TEST "beg-refs-count"
        local out = exec (
            "git -C " .. DIR2 .. " for-each-ref refs/begs/ --format='%(refname)'"
        )
        local count = 0
        for _ in out:gmatch("[^\n]+") do count = count + 1 end
        assert(count == 2, "expected 2 refs/begs/, got: " .. count)
    end
end

-- 3. Multiple begs from different heads
do
    print("==> Multiple begs from different heads")
    exec(ENV_EXE .. " chains add cli-begs-3 init " .. GEN_1)

    -- KEY1 posts normally (advances HEAD)
    exec(ENV_EXE .. " chain cli-begs-3 post inline 'normal post 1' --sign " .. KEY1)
    local HEAD1 = exec("git -C " .. DIR3 .. " rev-parse HEAD")

    -- KEY2 begs from HEAD1
    local BEG1 = exec (
        ENV_EXE .. " chain cli-begs-3 post inline 'beg from head1' --beg --sign " .. KEY2
    )

    -- KEY1 posts again (advances HEAD)
    exec(ENV_EXE .. " chain cli-begs-3 post inline 'normal post 2' --sign " .. KEY1)
    local HEAD2 = exec("git -C " .. DIR3 .. " rev-parse HEAD")

    -- KEY3 begs from HEAD2
    local BEG2 = exec (
        ENV_EXE .. " chain cli-begs-3 post inline 'beg from head2' --beg --sign " .. KEY3
    )

    do
        TEST "beg-different-parents"
        local parent1 = exec("git -C " .. DIR3 .. " log -1 --format=%P " .. BEG1)
        local parent2 = exec("git -C " .. DIR3 .. " log -1 --format=%P " .. BEG2)
        assert(parent1 == HEAD1, "beg1 parent: " .. parent1 .. " expected: " .. HEAD1)
        assert(parent2 == HEAD2, "beg2 parent: " .. parent2 .. " expected: " .. HEAD2)
        assert(parent1 ~= parent2, "parents should differ")
    end
end

-- 4. Likes on begs
do
    print("==> Likes on begs")

    exec(ENV_EXE .. " chains add cli-begs-4 init " .. GEN_1)

    -- KEY2 begs
    local BEG = exec (
        ENV_EXE .. " chain cli-begs-4 post inline 'please accept me' --beg --sign " .. KEY2
    )

    local HEAD = exec("git -C " .. DIR4 .. " rev-parse HEAD")

    -- get ref name for later checks
    local REF = exec (
        "git -C " .. DIR4 .. " for-each-ref refs/begs/ --format='%(refname)'"
    )

    local LIKE
    do
        TEST "like-beg-succeeds"
        local out, code = exec (
            ENV_EXE .. " chain cli-begs-4 like 1 post " .. BEG .. " --sign " .. KEY1
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        LIKE = out
    end

    do
        TEST "like-beg-merges"
        local head = exec("git -C " .. DIR4 .. " rev-parse HEAD")
        assert(head ~= HEAD, "HEAD should advance after merge")

        TEST "like-beg-structure: BEG-S-LIKE"
        local like = exec("git -C " .. DIR4 .. " rev-parse HEAD~1")
        local beg = exec("git -C " .. DIR4 .. " rev-parse " .. like .. "~2")
        assert(beg == BEG, "beg: " .. beg .. " expected: " .. BEG)

        TEST "like-beg-ancestor-is-beg"
        local _, code = exec(true, "git -C " .. DIR4 .. " merge-base --is-ancestor " .. BEG .. " HEAD")
        assert(code == 0, "beg should be ancestor of HEAD")
    end

    do
        TEST "like-beg-unblocks"
        local posts = dofile(DIR4 .. ".freechains/state/posts.lua")
        assert(posts[BEG], "post entry not found: " .. BEG)
        assert(posts[BEG].state ~= "beg", "state should no longer be beg")
    end

    do
        TEST "like-beg-ref-removed"
        local out = exec (
            "git -C " .. DIR4 .. " for-each-ref refs/begs/ --format='%(refname)'"
        )
        assert(out == "" or not out:match(REF), "ref should be removed: " .. out)
    end

    do
        TEST "beg-sufficient-reps"
        local _,code,err = exec (true,
            ENV_EXE .. " chain cli-begs-4 post inline 'another beg' --beg --sign " .. KEY2
        )
        assert (code~=0 and
            err=="ERROR : chain post : --beg error : author has sufficient reputation"
            , err
        )
    end

    do
        TEST "like-beg-insufficient-reps"

        local beg = exec (
            ENV_EXE .. " chain cli-begs-4 post inline 'another beg' --beg --sign " .. KEY3
        )

        -- KEY3 has 0 reps, should fail to like
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-begs-4 like 1 post " .. beg .. " --sign " .. KEY3
        )
        assert (
            Q~=0 and err=="ERROR : chain like : insufficient reputation"
            , "should fail: " .. tostring(err)
        )

        TEST "like-beg-self-like-no-reps"
        -- KEY3 begged (0 reps), tries to like own beg
        local refs = exec (
            "git -C " .. DIR4 .. " for-each-ref refs/begs/ --format='%(refname)'"
        )
        local beg = refs:match("refs/begs/beg%-(%x+)")

        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-begs-4 like 1 post " .. beg .. " --sign " .. KEY3
        )
        assert (
            Q~=0 and err=="ERROR : chain like : insufficient reputation"
            , "should fail: " .. tostring(err)
        )
    end
end

-- 5. Merge structure (fast-forward)
do
    print("==> Merge structure (fast-forward)")

    exec(ENV_EXE .. " chains add cli-begs-5 init " .. GEN_1)

    -- KEY2 begs
    local BEG = exec (
        ENV_EXE .. " chain cli-begs-5 post inline 'merge test beg' --beg --sign " .. KEY2
    )
    local HEAD = exec("git -C " .. DIR5 .. " rev-parse HEAD")

    -- KEY1 likes the beg (triggers merge)
    exec(ENV_EXE .. " chain cli-begs-5 like 1 post " .. BEG .. " --sign " .. KEY1)

    local MERGE = exec("git -C " .. DIR5 .. " rev-parse HEAD")

    do
        TEST "merge-fast-forward"
        local parents = exec("git -C " .. DIR5 .. " log -1 --format=%P " .. MERGE)
        local count = 0
        for _ in parents:gmatch("%x+") do count = count + 1 end
        assert(count == 1, "fast-forward should have 1 parent, got: " .. count)
    end

    do
        TEST "merge-preserves-beg-sig"
        local key = ssh.verify(DIR5, BEG)
        assert(key, "beg commit signature should be intact")
    end

    do
        TEST "merge-head-advances"
        assert(MERGE ~= HEAD, "HEAD should be merge commit, not old HEAD")
    end
end

-- 6. Merge structure (true merge)
do
    print("==> Merge structure (true merge)")

    exec(ENV_EXE .. " chains add cli-begs-6 init " .. GEN_1)

    -- KEY2 begs
    local BEG = exec (
        ENV_EXE .. " chain cli-begs-6 post inline 'merge test beg' --beg --sign " .. KEY2
    )

    -- KEY1 posts normally (advances HEAD past genesis)
    exec(ENV_EXE .. " chain cli-begs-6 post inline 'normal post' --sign " .. KEY1)
    local HEAD = exec("git -C " .. DIR6 .. " rev-parse HEAD")

    -- KEY1 likes the beg (triggers true merge)
    local LIKE = exec(ENV_EXE .. " chain cli-begs-6 like 1 post " .. BEG .. " --sign " .. KEY1)

    do
        TEST "merge-has-two-parents"
        local parents = exec("git -C " .. DIR6 .. " log -1 --format=%P " .. LIKE)
        local count = 0
        for _ in parents:gmatch("%x+") do count = count + 1 end
        assert(count == 2, "true merge should have 2 parents, got: " .. count)
    end

    do
        TEST "merge-ancestor-includes-beg"
        local _, code = exec(true, "git -C " .. DIR6 .. " merge-base --is-ancestor " .. BEG .. " " .. LIKE)
        assert(code == 0, "beg should be ancestor of like")
    end
end

print("<== ALL PASSED")
