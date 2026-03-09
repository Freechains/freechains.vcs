#!/usr/bin/env lua5.4
require "tests"

-- BASIC QUERY
do
    print("==> Basic query")

    exec(ENV_EXE .. " chains add cli-reps dir " .. GEN_1P)

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
            ENV_EXE .. " chain cli-reps post inline 'p1'"
            .. " --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY
        )
        assert(code == 0,
            "exit code: " .. tostring(code))
        assert(out == "29", "reps: " .. out)
    end

    do
        TEST "reps-after-3-posts"
        exec (
            ENV_EXE .. " chain cli-reps post inline 'p2'"
            .. " --sign " .. KEY
        )
        exec (
            ENV_EXE .. " chain cli-reps post inline 'p3'"
            .. " --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cli-reps reps author " .. KEY
        )
        assert(code == 0,
            "exit code: " .. tostring(code))
        assert(out == "27", "reps: " .. out)
    end
end

-- AFTER LIKE/DISLIKE
do
    print("==> After like/dislike")

    exec("rm -rf " .. TMP)
    exec("mkdir -p " .. ROOT)

    exec(ENV_EXE .. " chains add cr3 dir " .. GEN_2P)

    do
        TEST "reps-liker-after-like"
        local target = exec (
            ENV_EXE .. " chain cr3 post inline 'target'"
            .. " --sign " .. KEY2
        )
        exec (
            ENV_EXE .. " chain cr3 like 1 post " .. target
            .. " --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cr3 reps author " .. KEY
        )
        assert(code == 0,
            "exit code: " .. tostring(code))
        -- KEY started at 15, like costs 1 → 14
        assert(out == "14", "reps: " .. out)
    end

    do
        TEST "reps-after-dislike"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec (
            ENV_EXE .. " chains add cr4 dir " .. GEN_2P
        )
        local target = exec (
            ENV_EXE .. " chain cr4 post inline 'bad'"
            .. " --sign " .. KEY2
        )
        exec (
            ENV_EXE .. " chain cr4 dislike 1 post " .. target
            .. " --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cr4 reps author " .. KEY
        )
        assert(code == 0,
            "exit code: " .. tostring(code))
        -- KEY started at 15, dislike costs 1 → 14
        assert(out == "14", "reps: " .. out)
    end

    do
        TEST "reps-target-disliked"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec (
            ENV_EXE .. " chains add cr5 dir " .. GEN_2P
        )
        local target = exec (
            ENV_EXE
            .. " chain cr5 post inline 'disliked'"
            .. " --sign " .. KEY2
        )
        exec (
            ENV_EXE .. " chain cr5 dislike 1 post " .. target
            .. " --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cr5 reps author " .. KEY2
        )
        assert(code == 0,
            "exit code: " .. tostring(code))
        -- KEY2: 15 - 1(post) - 1(dislike penalty) = 13
        local n = tonumber(out)
        assert(n < 14,
            "target should lose reps: " .. out)
    end
end

-- MULTI-PIONEER
do
    print("==> Multi-pioneer")

    do
        TEST "reps-2-pioneers"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec (
            ENV_EXE .. " chains add cr6 dir " .. GEN_2P
        )
        local out1 = exec (
            ENV_EXE .. " chain cr6 reps author " .. KEY
        )
        local out2 = exec (
            ENV_EXE .. " chain cr6 reps author " .. KEY2
        )
        assert(out1 == "15", "KEY reps: " .. out1)
        assert(out2 == "15", "KEY2 reps: " .. out2)
    end

    do
        TEST "reps-3-pioneers"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)

        -- Create a 3-pioneer genesis directory
        local gen3 = TMP .. "/genesis-3p/"
        exec("mkdir -p " .. gen3)
        exec("cp " .. GEN .. "genesis.lua " .. gen3)
        exec("mkdir -p " .. gen3 .. "reps")
        local f = io.open(gen3 .. "reps/authors.lua", "w")
        f:write('return {\n')
        f:write('    ["' .. KEY .. '"] = 10000,\n')
        f:write('    ["' .. KEY2 .. '"] = 10000,\n')
        f:write('    ["FAKE_KEY_FOR_TEST"] = 10000,\n')
        f:write('}\n')
        f:close()

        exec (
            ENV_EXE .. " chains add cr7 dir " .. gen3
        )
        local out = exec (
            ENV_EXE .. " chain cr7 reps author " .. KEY
        )
        assert(out == "10", "KEY reps: " .. out)
    end
end

print("<== ALL PASSED")
