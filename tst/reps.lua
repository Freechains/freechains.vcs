#!/usr/bin/env lua5.4
require "common"

-- PIONEER INITIALIZATION
do
    print("==> Pioneer initialization")

    do
        TEST "pioneer-single"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add p1 dir " .. GEN_1P)
        local reps = exec(ENV_EXE .. " chain p1 reps author " .. KEY)
        assert(reps == "30", "KEY reps: " .. reps)
    end

    do
        TEST "pioneer-two"
        exec(ENV_EXE .. " chains add p2 dir " .. GEN_2P)
        local r1 = exec(ENV_EXE .. " chain p2 reps author " .. KEY)
        local r2 = exec(ENV_EXE .. " chain p2 reps author " .. KEY2)
        assert(r1 == "15", "KEY reps: " .. r1)
        assert(r2 == "15", "KEY2 reps: " .. r2)
    end

    do
        TEST "no-pioneers"
        exec(ENV_EXE .. " chains add p3 dir " .. GEN)
        local reps = exec(ENV_EXE .. " chain p3 reps author " .. KEY)
        assert(reps == "0", "KEY reps: " .. reps)
    end
end

-- POST COST
do
    print("==> Post cost")

    do
        TEST "post-costs-1"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c1 dir " .. GEN_1P)
        exec(ENV_EXE .. " chain c1 post inline 'first post' --sign " .. KEY)
        local reps = exec(ENV_EXE .. " chain c1 reps author " .. KEY)
        assert(reps == "29", "KEY reps: " .. reps)
    end

    do
        TEST "post-costs-3"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c2 dir " .. GEN_1P)
        exec(ENV_EXE .. " chain c2 post inline 'post 1' --sign " .. KEY)
        exec(ENV_EXE .. " chain c2 post inline 'post 2' --sign " .. KEY)
        exec(ENV_EXE .. " chain c2 post inline 'post 3' --sign " .. KEY)
        local reps = exec(ENV_EXE .. " chain c2 reps author " .. KEY)
        assert(reps == "27", "KEY reps: " .. reps)
    end

    do
        TEST "post-blocked"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c3 dir " .. GEN_1P)
        local reps = exec(ENV_EXE .. " chain c3 reps author " .. KEY2)
        assert(reps == "0", "KEY2 should have 0 reps: " .. reps)
    end
end

-- LIKE EFFECT
do
    print("==> Like effect")

    do
        TEST "like-costs-liker"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c4 dir " .. GEN_2P)
        local target = exec (
            ENV_EXE .. " chain c4 post inline 'target post' --sign " .. KEY2
        )
        local before = exec(ENV_EXE .. " chain c4 reps author " .. KEY)
        assert(before == "15", "KEY before: " .. before)
        exec(ENV_EXE .. " chain c4 like +3 post " .. target .. " --sign " .. KEY)
        local after = exec(ENV_EXE .. " chain c4 reps author " .. KEY)
        assert(after == "14", "KEY after: " .. after)
    end

    do
        TEST "like-tracked-in-posts"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c5 dir " .. GEN_2P)
        local target = exec (
            ENV_EXE .. " chain c5 post inline 'target post' --sign " .. KEY2
        )
        exec(ENV_EXE .. " chain c5 like +3 post " .. target .. " --sign " .. KEY)
        local reps = exec(ENV_EXE .. " chain c5 reps post " .. target)
        assert(reps == "1", "post reps: " .. reps)
    end
end

-- DISLIKE EFFECT
do
    print("==> Dislike effect")

    do
        TEST "dislike-immediate"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c6 dir " .. GEN_2P)
        local target = exec (
            ENV_EXE .. " chain c6 post inline 'bad post' --sign " .. KEY2
        )
        local before = exec(ENV_EXE .. " chain c6 reps author " .. KEY2)
        exec(ENV_EXE .. " chain c6 like -3 post " .. target .. " --sign " .. KEY)
        local after = exec(ENV_EXE .. " chain c6 reps author " .. KEY2)
        assert(tonumber(after) < tonumber(before),
            "KEY2 should decrease: " .. before .. " -> " .. after)
    end

    do
        TEST "dislike-costs-disliker"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c7 dir " .. GEN_2P)
        local target = exec (
            ENV_EXE .. " chain c7 post inline 'bad post' --sign " .. KEY2
        )
        exec(ENV_EXE .. " chain c7 like -3 post " .. target .. " --sign " .. KEY)
        local reps = exec(ENV_EXE .. " chain c7 reps author " .. KEY)
        assert(reps == "14", "KEY reps: " .. reps)
    end

    do
        TEST "dislike-tracked"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c8 dir " .. GEN_2P)
        local target = exec (
            ENV_EXE .. " chain c8 post inline 'bad post' --sign " .. KEY2
        )
        exec(ENV_EXE .. " chain c8 like -3 post " .. target .. " --sign " .. KEY)
        local reps = exec(ENV_EXE .. " chain c8 reps post " .. target)
        assert(reps == "-1", "post reps: " .. reps)
    end
end

-- SELF-INTERACTIONS
do
    print("==> Self-interactions")

    do
        TEST "self-like-allowed"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c9 dir " .. GEN_1P)
        local target = exec (
            ENV_EXE .. " chain c9 post inline 'my post' --sign " .. KEY
        )
        -- 30000 - 1000 (post) - 1000 (like cost) = 28000
        -- self-like +3: delivered = 2700, author += 1350
        -- 28000 + 1350 = 29350 -> ext 29
        exec(ENV_EXE .. " chain c9 like +3 post " .. target .. " --sign " .. KEY)
        local reps = exec(ENV_EXE .. " chain c9 reps author " .. KEY)
        assert(reps == "29", "KEY reps: " .. reps)
    end

    do
        TEST "self-dislike-allowed"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c10 dir " .. GEN_1P)
        local target = exec (
            ENV_EXE .. " chain c10 post inline 'my post' --sign " .. KEY
        )
        -- 30000 - 1000 (post) - 1000 (like cost) = 28000
        -- self-dislike -3: delivered = -2700, author -= 1350
        -- 28000 - 1350 = 26650 -> ext 26
        exec(ENV_EXE .. " chain c10 like -3 post " .. target .. " --sign " .. KEY)
        local reps = exec(ENV_EXE .. " chain c10 reps author " .. KEY)
        assert(reps == "26", "KEY reps: " .. reps)
end

-- UNRATED POSTS
do
    print("==> Unrated posts")

    do
        TEST "unrated-absent"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(ENV_EXE .. " chains add c11 dir " .. GEN_1P)
        local h = exec (
            ENV_EXE .. " chain c11 post inline 'just a post' --sign " .. KEY
        )
        local reps = exec(ENV_EXE .. " chain c11 reps post " .. h)
        assert(reps == "0", "unrated post should have 0 reps: " .. reps)
    end
end

print("<== ALL PASSED")
