#!/usr/bin/env lua5.4
require "tests"

exec {
    cmd = ENV_EXE .. " --now=0 chains add /cli-time init " .. GEN_1,
}

-- DISCOUNT
do
    print("==> Discount")

    do
        TEST "time-discount-instant"

        exec { -- 50000 -> 49500 (post)
            cmd = ENV_EXE .. " --now=0 chain /cli-time post inline 'p1' --sign " .. KEY1,
        }
        local out = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-time reps author '" .. PUB1 .. "'",
        }
        assert(out == "49500", "reps: " .. out)

        exec { -- 49500 -> 50000 (refund) -> 49500 (post)
            cmd = ENV_EXE .. " --now=0 chain /cli-time post inline 'p2' --sign " .. KEY1,
        }
        local out = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-time reps author '" .. PUB1 .. "'",
        }
        assert(out == "49500", "reps: " .. out)
    end
end

exec {
    cmd = ENV_EXE .. " chains rem /cli-time",
}

-- CONSOLIDATION
do
    print("==> Consolidation")

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-time init " .. GEN_1,
    }

    do
        TEST "time-consolidation-24h"

        exec { -- 50000 -> 49500 (post)
            cmd = ENV_EXE .. " --now=0 chain /cli-time post inline 'p1' --sign " .. KEY1,
        }
        local out = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-time reps author '" .. PUB1 .. "'",
        }
        assert(out == "49500", "reps: " .. out)

        exec { -- refund P1 + consolidate P1 (capped) + cost P2 -> 50000
            cmd = ENV_EXE .. " --now=86400 chain /cli-time post inline 'p2' --sign " .. KEY1,
        }
        local out = exec {
            cmd = ENV_EXE .. " --now=86400 chain /cli-time reps author '" .. PUB1 .. "'",
        }
        assert(out == "50000", "reps: " .. out)
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-time",
    }

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-time init " .. GEN_1,
    }

    do
        TEST "time-consolidation-1-per-day"

        exec { -- 30 -> 29
            cmd = ENV_EXE .. " --now=0 chain /cli-time post inline 'p1' --sign " .. KEY1,
        }
        exec { -- refund P1 + cost P2 → 29
            cmd = ENV_EXE .. " --now=0 chain /cli-time post inline 'p2' --sign " .. KEY1,
        }
        exec { -- refund P2 + cost P3 -> 49500
            cmd = ENV_EXE .. " --now=0 chain /cli-time post inline 'p3' --sign " .. KEY1,
        }
        local out = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-time reps author '" .. PUB1 .. "'",
        }
        assert(out == "49500", "reps: " .. out)

        exec { -- refund P3 + consolidate P1 only (capped) + cost P4 -> 50000
            cmd = ENV_EXE .. " --now=86400 chain /cli-time post inline 'p4' --sign " .. KEY1,
        }
        local out = exec {
            cmd = ENV_EXE .. " --now=86400 chain /cli-time reps author '" .. PUB1 .. "'",
        }
        assert(out == "50000", "reps: " .. out)
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-time",
    }
end

-- REPS QUERY WITH TIME SIMULATION
do
    print("==> Reps query")

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /cli-time init " .. GEN_1,
    }

    do
        TEST "time-reps-query-simulates"

        exec { -- 50000 -> 49500 (post)
            cmd = ENV_EXE .. " --now=0 chain /cli-time post inline 'p1' --sign " .. KEY1,
        }
        -- query at now=0: still in discount -> 49500
        local out = exec {
            cmd = ENV_EXE .. " --now=0 chain /cli-time reps author '" .. PUB1 .. "'",
        }
        assert(out == "49500", "reps at now=0: " .. out)

        -- query at now=86400: refund + consolidation -> 50000
        local out = exec {
            cmd = ENV_EXE .. " --now=86400 chain /cli-time reps author '" .. PUB1 .. "'",
        }
        assert(out == "50000", "reps at now=86400: " .. out)
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-time",
    }
end

print("<== ALL PASSED")
