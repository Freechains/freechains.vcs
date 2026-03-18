#!/usr/bin/env lua5.4
require "tests"

exec(ENV_EXE .. " --now=0 chains add cli-time config " .. GEN_1)

-- DISCOUNT
do
    print("==> Discount")

    do
        TEST "time-discount-instant"

        exec (  -- 30 -> 29 (post)
            ENV_EXE .. " --now=0 chain cli-time post inline 'p1' --sign " .. KEY
        )
        local out = exec(ENV_EXE .. " --now=0 chain cli-time reps author " .. KEY)
        assert(out == "29", "reps: " .. out)

        exec (  -- 29 -> 30 (refund) -> 29 (post)
            ENV_EXE .. " --now=0 chain cli-time post inline 'p2' --sign " .. KEY
        )
        local out = exec(ENV_EXE .. " --now=0 chain cli-time reps author " .. KEY)
        assert(out == "29", "reps: " .. out)
    end
end

exec(ENV_EXE .. " chains rem cli-time")

-- CONSOLIDATION
do
    print("==> Consolidation")

    exec(ENV_EXE .. " --now=0 chains add cli-time config " .. GEN_1)

    do
        TEST "time-consolidation-24h"

        exec (  -- 30 -> 29 (post)
            ENV_EXE .. " --now=0 chain cli-time post inline 'p1' --sign " .. KEY
        )
        local out = exec(ENV_EXE .. " --now=0 chain cli-time reps author " .. KEY)
        assert(out == "29", "reps: " .. out)

        exec (  -- refund P1 + consolidate P1 + cost P2 → 30
            ENV_EXE .. " --now=86400 chain cli-time post inline 'p2' --sign " .. KEY
        )
        local out = exec(ENV_EXE .. " --now=86400 chain cli-time reps author " .. KEY)
        assert(out == "30", "reps: " .. out)
    end

    exec(ENV_EXE .. " chains rem cli-time")

    exec(ENV_EXE .. " --now=0 chains add cli-time config " .. GEN_1)

    do
        TEST "time-consolidation-1-per-day"

        exec (  -- 30 -> 29
            ENV_EXE .. " --now=0 chain cli-time post inline 'p1' --sign " .. KEY
        )
        exec (  -- refund P1 + cost P2 → 29
            ENV_EXE .. " --now=0 chain cli-time post inline 'p2' --sign " .. KEY
        )
        exec (  -- refund P2 + cost P3 → 29
            ENV_EXE .. " --now=0 chain cli-time post inline 'p3' --sign " .. KEY
        )
        local out = exec(ENV_EXE .. " --now=0 chain cli-time reps author " .. KEY)
        assert(out == "29", "reps: " .. out)

        exec (  -- refund P3 + consolidate P1 only + cost P4 → 30
            ENV_EXE .. " --now=86400 chain cli-time post inline 'p4' --sign " .. KEY
        )
        local out = exec(ENV_EXE .. " --now=86400 chain cli-time reps author " .. KEY)
        assert(out == "30", "reps: " .. out)
    end

    exec(ENV_EXE .. " chains rem cli-time")
end

-- REPS QUERY WITH TIME SIMULATION
do
    print("==> Reps query")

    exec(ENV_EXE .. " --now=0 chains add cli-time config " .. GEN_1)

    do
        TEST "time-reps-query-simulates"

        exec (  -- 30 -> 29 (post)
            ENV_EXE .. " --now=0 chain cli-time post inline 'p1' --sign " .. KEY
        )
        -- query at now=0: still in discount → 29
        local out = exec(ENV_EXE .. " --now=0 chain cli-time reps author " .. KEY)
        assert(out == "29", "reps at now=0: " .. out)

        -- query at now=86400: refund + consolidation → 30
        local out = exec(ENV_EXE .. " --now=86400 chain cli-time reps author " .. KEY)
        assert(out == "30", "reps at now=86400: " .. out)
    end

    exec(ENV_EXE .. " chains rem cli-time")
end

print("<== ALL PASSED")
