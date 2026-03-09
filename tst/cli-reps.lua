#!/usr/bin/env lua5.4
require "tests"

exec(ENV_EXE .. " chains add cli-reps dir " .. GEN_1P)

-- BASIC QUERY
do
    print("==> Basic query")

    do
        TEST "reps-pioneer-initial"
        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY
        )
        assert(code==0, "exit code: " .. tostring(code))
        assert(out=="30", "reps: " .. out)
    end

    do
        TEST "reps-unknown-pubkey"
        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY2
        )
        assert(code==0,  "exit code: " .. tostring(code))
        assert(out=="0", "reps: " .. out)
    end

    do
        TEST "reps-list-all"
        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps authors"
        )
        assert(code==0,         "exit code: " .. tostring(code))
        assert(out:match(KEY),  "KEY not listed")
        assert(out:match("30"), "30 not in output")
    end
end

-- AFTER POSTS
do
    print("==> After posts")

    do
        TEST "reps-after-1-post"
        exec (
            ENV_EXE .. " chain cli-reps post inline 'p1'" .. " --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "29", "reps: " .. out)    -- KEY: 30 -> post -> 29
    end

    do
        TEST "reps-after-3-posts"
        exec (
            ENV_EXE .. " chain cli-reps post inline 'p2'" .. " --sign " .. KEY
        )
        exec (
            ENV_EXE .. " chain cli-reps post inline 'p3'" .. " --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY
        )
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "27", "reps: " .. out)    -- KEY: 30 -> posts -> 27
    end
end

exec(ENV_EXE .. " chains rem cli-reps")

-- AFTER LIKE/DISLIKE
do
    print("==> After like/dislike")

    exec(ENV_EXE .. " chains add cli-reps dir " .. GEN_2P)

    do
        TEST "reps-liker-after-like"
        local post = exec (
            ENV_EXE .. " chain cli-reps post inline 'hello'" .. " --sign " .. KEY2
        )
        exec (
            ENV_EXE .. " chain cli-reps like 2 post " .. post .. " --sign " .. KEY
        )

        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY
        )
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "13", "reps: " .. out)    -- KEY: 15 -> like -> 13

        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps post " .. post
        )
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "1", "reps: " .. out)     -- post: 0 -> like -> 1
    end

    do
        TEST "reps-after-dislike"
        local post = exec (
            ENV_EXE .. " chain cli-reps post inline 'bad'" .. " --sign " .. KEY2
        )
        exec (
            ENV_EXE .. " chain cli-reps dislike 1 post " .. post .. " --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY
        )
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "12", "reps: " .. out) -- KEY: 15 -> like -> 13 -> dislike -> 12
    end

    do
        TEST "reps-target-disliked"

        local target = exec (
            ENV_EXE
            .. " chain cli-reps post inline 'disliked'" .. " --sign " .. KEY2
        )
        exec (
            ENV_EXE .. " chain cli-reps dislike 1 post " .. target .. " --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY2
        )
        assert(code == 0, "exit code: " .. tostring(code))
        -- KEY2: 15 - 1(post) - 1(dislike penalty) = 13
        local n = tonumber(out)
        assert(n < 14, "target should lose reps: " .. out)
    end

    exec(ENV_EXE .. " chains rem cli-reps")
end

-- MULTI-PIONEER
do
    print("==> Multi-pioneer")

    do
        TEST "reps-2-pioneers"
        exec (
            ENV_EXE .. " chains add cli-reps dir " .. GEN_2P
        )
        local out1 = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY
        )
        local out2 = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY2
        )
        assert(out1 == "15", "KEY reps: " .. out1)
        assert(out2 == "15", "KEY2 reps: " .. out2)
    end

    do
        TEST "reps-3-pioneers"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add cr7 dir " .. GEN_3P)
        local out = exec (
            ENV_EXE .. " chain cr7 reps author " .. KEY
        )
        assert(out == "10", "KEY reps: " .. out)
    end
end

print("<== ALL PASSED")
