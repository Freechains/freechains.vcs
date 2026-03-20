#!/usr/bin/env lua5.4

require "tests"

exec(ENV_EXE .. " chains add cli-like config " .. GEN_2)
local DIR = ROOT .. "/chains/cli-like/"

-- Pioneer posts a target block
local POST

do
    print("==> freechains post")
    POST = exec (
        ENV_EXE .. " chain cli-like post inline 'target post' --sign " .. KEY
    )
    assert(#POST == 40, "target hash: " .. POST)

    print("==> freechains: post trailer")
    do
        TEST "post-has-trailer"
        local out = exec("git -C " .. DIR .. " cat-file commit HEAD")
        assert(out:match("Freechains: post"), "missing freechains: post trailer")
    end
end

-- LIKE COMMAND (+)
do
    print("==> freechains chain like (+1)")

    local LIKE
    do
        TEST "like-success"
        local out, code = exec (
            ENV_EXE .. " chain cli-like like 1 post " .. POST .. " --sign " .. KEY2
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
        LIKE = out
    end

    do
        TEST "like-has-trailer"
        local out = exec("git -C " .. DIR .. " cat-file commit HEAD")
        assert(out:match("Freechains: like"), "missing freechains: like trailer")
    end

    do
        TEST "like-payload-file"
        local file = exec (
            "git -C " .. DIR .. " diff-tree --no-commit-id --name-only -r "
                .. LIKE .. " -- .freechains/likes/"
        )
        assert(file ~= "", "like payload file missing")
        local out = exec("git -C " .. DIR .. " show " .. LIKE .. ":" .. file)
        local tbl = load(out)()
        assert(tbl.target == "post", "target: " .. tostring(tbl.target))
        assert(tbl.id == POST, "id: " .. tostring(tbl.id))
        assert(tbl.number == 1000, "number: " .. tostring(tbl.number))
    end

    do
        TEST "like-is-signed"
        local _, code = exec (
            ENV .. " git -C " .. DIR .. " verify-commit HEAD"
        )
        assert(code == 0, "verify-commit failed")
    end

    do
        TEST "like-parent"
        local parent = exec("git -C " .. DIR .. " rev-parse HEAD~1")
        assert(parent == POST,
            "parent: " .. parent .. " expected: " .. POST)
    end
end

-- DISLIKE (like -1)
do
    print("==> freechains chain like (-1)")

    local TARGET2 = exec (
        ENV_EXE .. " chain cli-like post inline 'another post' --sign " .. KEY
    )

    do
        TEST "dislike-success"
        local out, code = exec (
            ENV_EXE .. " chain cli-like dislike 1 post " .. TARGET2 .. " --sign " .. KEY2
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
    end

    do
        TEST "dislike-payload"
        local out = exec("git -C " .. DIR .. " cat-file commit HEAD")
        assert(out:match("Freechains: like"), "missing freechains: like trailer")
    end

    do
        TEST "dislike-with-why"
        local TARGET3 = exec (
            ENV_EXE .. " chain cli-like post inline 'bad content' --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cli-like dislike 1 post " .. TARGET3
            .. " --sign " .. KEY2 .. " --why 'spam content'"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        local msg = exec("git -C " .. DIR .. " log -1 --format=%s")
        assert(msg:match("spam content"), "reason not recorded")
    end
end

-- LIKE AUTHOR (fresh chain)
exec(ENV_EXE .. " chains rem cli-like")
exec(ENV_EXE .. " chains add cli-like config " .. GEN_2)
do
    print("==> freechains chain like author")

    -- KEY=15, KEY2=15
    do
        TEST "like-author-success"
        local out, code = exec (
            ENV_EXE .. " chain cli-like like 1 author " .. KEY2 .. " --sign " .. KEY
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
    end

    do
        TEST "like-author-liker-cost"
        -- KEY: 15 - 1 (cost) = 14
        local out = exec(ENV_EXE .. " chain cli-like reps author " .. KEY)
        assert(out == "14", "liker reps: " .. out)

        TEST "like-author-target-gains"
        -- KEY2: 15000 + 900 = 15900 -> ext = 16
        local out = exec(ENV_EXE .. " chain cli-like reps author " .. KEY2)
        assert(out == "16", "target reps: " .. out)
    end

    do
        TEST "like-author-2-transfer"
        -- like 2: KEY pays 2000 cost, KEY2 gets 2000*90%=1800
        exec(ENV_EXE .. " chain cli-like like 2 author " .. KEY2 .. " --sign " .. KEY)
        local k1 = exec(ENV_EXE .. " chain cli-like reps author " .. KEY)
        local k2 = exec(ENV_EXE .. " chain cli-like reps author " .. KEY2)
        -- KEY: 14000 - 2000 = 12000 -> ext=12
        -- KEY2: 15900 + 1800 = 17700 -> ext=18
        assert(k1 == "12", "liker reps: " .. k1)
        assert(k2 == "18", "target reps: " .. k2)
    end

    do
        TEST "dislike-author"
        exec(ENV_EXE .. " chain cli-like dislike 1 author " .. KEY2 .. " --sign " .. KEY)
        local k1 = exec(ENV_EXE .. " chain cli-like reps author " .. KEY)
        local k2 = exec(ENV_EXE .. " chain cli-like reps author " .. KEY2)
        -- KEY: 12000 - 1000 = 11000 -> ext=11
        -- KEY2: 17700 - 900 = 16800 -> ext=17
        assert(k1 == "11", "liker reps: " .. k1)
        assert(k2 == "17", "target reps: " .. k2)
    end
end

-- ERROR CASES
do
    print("==> Error cases")

    do
        TEST "like-nonexistent-post"
        local fake = "0000000000000000000000000000000000000000"
        local _, code = exec (true,
            ENV_EXE .. " chain cli-like like 1 post " .. fake .. " --sign " .. KEY2
        )
        assert(code ~= 0, "should fail")
    end

    do
        TEST "self-like-allowed"
        local self_target = exec (
            ENV_EXE .. " chain cli-like post inline 'self target' --sign " .. KEY
        )
        local _, code = exec (
            ENV_EXE .. " chain cli-like like 1 post " .. self_target .. " --sign " .. KEY
        )
        assert(code == 0, "self-like should succeed")
    end

    do
        TEST "self-dislike-allowed"
        local self_target = exec (
            ENV_EXE .. " chain cli-like post inline 'self dislike' --sign " .. KEY
        )
        local _, code = exec (
            ENV_EXE .. " chain cli-like dislike 1 post " .. self_target .. " --sign " .. KEY
        )
        assert(code == 0, "self-dislike should succeed")
    end

    do
        TEST "like-requires-sign"
        local _, code = exec (true,
            ENV_EXE .. " chain cli-like like 1 post " .. POST
        )
        assert(code ~= 0, "like without --sign should fail")
    end

    do
        TEST "like-bad-target-type"
        local _, code = exec (true,
            ENV_EXE .. " chain cli-like like 1 foo " .. POST .. " --sign " .. KEY
        )
        assert(code ~= 0, "bad target type should fail")
    end
end

print("<== ALL PASSED")
