#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-now/"

-- GENESIS TIMESTAMP
do
    print("==> Genesis timestamp")

    do
        TEST "genesis with --now=0"
        exec(ENV_EXE .. " --now=0 chains add cli-now config " .. GEN_1)
        local ts = exec("git -C " .. DIR .. " log -1 --format=%at")
        assert(ts == "0", "genesis timestamp: " .. ts)
    end

    do
        TEST "committer date also set"
        local ts = exec("git -C " .. DIR .. " log -1 --format=%ct")
        assert(ts == "0", "committer timestamp: " .. ts)
    end
end

-- POST TIMESTAMP
do
    print("==> Post timestamp")

    do
        TEST "post with --now=100"
        local out = exec(ENV_EXE .. " --now=100 chain cli-now post inline 'hello' --sign " .. KEY)
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. DIR .. " log -1 --format=%at")
        assert(ts == "100", "post timestamp: " .. ts)
    end

    do
        TEST "post with --now=200"
        local out = exec(ENV_EXE .. " --now=200 chain cli-now post inline 'world' --sign " .. KEY)
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. DIR .. " log -1 --format=%at")
        assert(ts == "200", "post timestamp: " .. ts)
    end
end

-- LIKE TIMESTAMP
do
    print("==> Like timestamp")

    do
        TEST "like with --now=300"
        local h = exec (
            ENV_EXE .. " --now=100 chain cli-now post inline 'hello' --sign " .. KEY
        )
        exec (
            ENV_EXE .. " --now=300 chain cli-now like 1 post " .. h .. " --sign " .. KEY
        )
        local ts = exec("git -C " .. DIR .. " log -1 --format=%at")
        assert(ts == "300", "like timestamp: " .. ts)
    end
end

-- INCREASING TIMESTAMPS
do
    print("==> Increasing timestamps in log")

    do
        TEST "all commits have expected timestamps"
        exec(ENV_EXE .. " --now=0   chain cli-now post inline 0 --sign " .. KEY)
        exec(ENV_EXE .. " --now=100 chain cli-now post inline 1 --sign " .. KEY)
        exec(ENV_EXE .. " --now=200 chain cli-now post inline 2 --sign " .. KEY)
        exec(ENV_EXE .. " --now=300 chain cli-now post inline 3 --sign " .. KEY)

        -- newest first
        local logs = exec("git -C " .. DIR .. " log --format=%at")
        local ts = {}
        for t in logs:gmatch("%d+") do
            ts[#ts+1] = tonumber(t)
            if #ts == 4 then
                break
            end
        end
        assert(#ts == 4, "expected 4 commits: " .. #ts)
        assert(ts[1] == 300, "t[1]: " .. ts[1])
        assert(ts[2] == 200, "t[2]: " .. ts[2])
        assert(ts[3] == 100, "t[3]: " .. ts[3])
        assert(ts[4] == 0,   "t[4]: " .. ts[4])
    end
end

-- MONOTONIC TIMESTAMP VALIDATION
do
    print("==> Monotonic timestamp validation")

    do
        TEST "post within tolerance (1h backwards) passes"
        exec (
            ENV_EXE .. " --now=10000 chain cli-now post inline 'base' --sign " .. KEY
        )
        local ok = exec (
            ENV_EXE .. " --now=7000 chain cli-now post inline 'back 3000s' --sign " .. KEY
        )
        assert(#ok == 40, "hash: " .. ok)
    end

    do
        TEST "post beyond tolerance (>1h backwards) fails"
        exec (
            ENV_EXE .. " --now=10000 chain cli-now post inline 'base2' --sign " .. KEY
        )
        local ok, code, msg = exec (true,
            ENV_EXE .. " --now=5000 chain cli-now post inline 'too far back' --sign " .. KEY
        )
        local err = "ERROR : chain post : cannot be older than parent"
        assert(ok==false and msg==err, "should fail: " .. tostring(ok))
    end

    do
        TEST "like beyond tolerance fails"
        local h = exec(ENV_EXE .. " --now=10000 chain cli-now post inline 'base3' --sign " .. KEY)
        local ok, code = exec(true,
            ENV_EXE .. " --now=5000 chain cli-now like 1 post " .. h .. " --sign " .. KEY
        )
        assert(ok == false, "should fail: " .. tostring(ok))
    end
end

do
    TEST "post without --now uses system clock"
    local before = os.time()
    local out = exec(ENV_EXE .. " chain cli-now post inline 'no fake time' --sign " .. KEY)
    local after = os.time()
    assert(#out == 40, "hash: " .. out)
    local ts = tonumber((exec("git -C " .. DIR .. " log -1 --format=%at")))
    assert(ts>=before and ts<=after, "timestamp not in range: " .. ts)
end

print("<== ALL PASSED")
