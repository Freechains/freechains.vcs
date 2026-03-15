#!/usr/bin/env lua5.4
require "tests"

exec(ENV_EXE .. " --now=0 chains add cli-time dir " .. GEN_1P)

-- DISCOUNT
do
    print("==> Discount")

    do
        TEST "time-discount-instant"

        exec (  -- 30 -> 29 (post)
            ENV_EXE .. " --now=0 chain cli-time post inline 'p1' --sign " .. KEY
        )
        local out = exec(ENV_EXE .. " chain cli-time reps author " .. KEY)
        assert(out == "29", "reps: " .. out)

        exec (  -- 29 -> 30 (refund) -> 29 (post)
            ENV_EXE .. " --now=0 chain cli-time post inline 'p2' --sign " .. KEY
        )
        local out = exec(ENV_EXE .. " chain cli-time reps author " .. KEY)
        assert(out == "29", "reps: " .. out)
    end
end

exec(ENV_EXE .. " chains rem cli-time")

print("<== ALL PASSED")
