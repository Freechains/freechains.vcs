#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-now/"

-- GENESIS TIMESTAMP
do
    print("==> Genesis timestamp")

    do
        TEST "genesis with --now=0"
        exec(EXE .. " --now=0 chains add cli-now dir " .. GEN_1P)
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
        local out = exec(EXE .. " --now=100 chain cli-now post inline 'hello'")
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. DIR .. " log -1 --format=%at")
        assert(ts == "100", "post timestamp: " .. ts)
    end

    do
        TEST "post with --now=200"
        local out = exec(EXE .. " --now=200 chain cli-now post inline 'world'")
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. DIR .. " log -1 --format=%at")
        assert(ts == "200", "post timestamp: " .. ts)
    end

    do
        TEST "post without --now uses system clock"
        local before = os.time()
        local out = exec(EXE .. " chain cli-now post inline 'no fake time'")
        local after = os.time()
        assert(#out == 40, "hash: " .. out)
        local ts = tonumber((exec("git -C " .. DIR .. " log -1 --format=%at")))
        assert(ts>=before and ts<=after, "timestamp not in range: " .. ts)
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
        exec(EXE .. " --now=0   chain cli-now post inline 0")
        exec(EXE .. " --now=100 chain cli-now post inline 1")
        exec(EXE .. " --now=200 chain cli-now post inline 2")
        exec(EXE .. " --now=300 chain cli-now post inline 3")

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

print("<== ALL PASSED")
