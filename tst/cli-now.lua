#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-now/"

-- reads the signed time of action `aid` (the one source of truth)
local function TIME (aid)
    return (exec {
        cmd = "git -C " .. DIR .. " log -1 --format=%at " .. aid,
    })
end

-- NEUTRAL COMMIT DATES
do
    print("==> Neutral commit dates")

    do
        TEST "genesis envelope is neutral (identity + dates)"
        exec {
            cmd = "HOME=" .. SSH .. "home " .. ENV_EXE .. " --now=0 chains add /cli-now init --pioneer",
        }
        local ts = exec {
            cmd = "git -C " .. DIR .. " log -1 --format='%an %ae %cn %ce %at %ct'",
        }
        assert(ts == "- - - - 0 0", "genesis envelope: " .. ts)
    end

    do
        TEST "post envelope date IS the action time (--now)"
        local out = exec {
            cmd = ENV_EXE .. " --now=100 chain /cli-now post inline 'hello' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)
        local ts = exec {
            cmd = "git -C " .. DIR .. " log -1 --format='%an %ae %cn %ce %at %ct'",
        }
        assert(ts == "- - - - 100 100", "post envelope: " .. ts)
    end
end

-- ACTION TIME
do
    print("==> Action time")

    do
        TEST "post with --now=200"
        local h = exec {
            cmd = ENV_EXE .. " --now=200 chain /cli-now post inline 'world' --sign " .. KEY1,
        }
        assert(#h == 40, "hash: " .. h)
        local ts = TIME(h)
        assert(ts == "200", "post time: " .. ts)
    end

    do
        TEST "like with --now=300"
        local h = exec {
            cmd = ENV_EXE .. " --now=100 chain /cli-now post inline 'hello2' --sign " .. KEY1,
        }
        local l = exec {
            cmd = ENV_EXE .. " --now=300 chain /cli-now like 1000 action " .. h .. " --sign " .. KEY1,
        }
        local ts = TIME(l)
        assert(ts == "300", "like time: " .. ts)
    end

    do
        TEST "each post records its own --now"
        local hs = {}
        for i, now in ipairs { 0, 100, 200, 300 } do
            hs[i] = exec {
                cmd = ENV_EXE .. " --now=" .. now .. " chain /cli-now post inline t" .. i .. " --sign " .. KEY1,
            }
        end
        for i, now in ipairs { 0, 100, 200, 300 } do
            local ts = TIME(hs[i])
            assert(ts == tostring(now), "t[" .. i .. "]: " .. ts)
        end
    end
end

-- MONOTONIC TIMESTAMP VALIDATION
do
    print("==> Monotonic timestamp validation")

    do
        TEST "post within tolerance (1h backwards) passes"
        exec {
            cmd = ENV_EXE .. " --now=10000 chain /cli-now post inline 'base' --sign " .. KEY1,
        }
        local ok = exec {
            cmd = ENV_EXE .. " --now=7000 chain /cli-now post inline 'back 3000s' --sign " .. KEY1,
        }
        assert(#ok == 40, "hash: " .. ok)
    end

    do
        TEST "post beyond tolerance (>1h backwards) fails"
        exec {
            cmd = ENV_EXE .. " --now=10000 chain /cli-now post inline 'base2' --sign " .. KEY1,
        }
        FAIL {
            cmd = ENV_EXE .. " --now=5000 chain /cli-now post inline 'too far back' --sign " .. KEY1,
            err = "ERROR : chain post : too old",
        }
    end

    do
        TEST "like beyond tolerance fails"
        local h = exec {
            cmd = ENV_EXE .. " --now=10000 chain /cli-now post inline 'base3' --sign " .. KEY1,
        }
        FAIL {
            cmd = ENV_EXE .. " --now=5000 chain /cli-now like 1000 action " .. h .. " --sign " .. KEY1,
            err = "ERROR : chain like : too old",
        }
    end
end

do
    TEST "post without --now uses system clock"
    local before = os.time()
    local out = exec {
        cmd = ENV_EXE .. " chain /cli-now post inline 'no fake time' --sign " .. KEY1,
    }
    local after = os.time()
    assert(#out == 40, "hash: " .. out)
    local ts = tonumber(TIME(out))
    assert(ts>=before and ts<=after, "timestamp not in range: " .. ts)
end

print("<== ALL PASSED")
