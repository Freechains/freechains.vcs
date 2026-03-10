#!/usr/bin/env lua5.4

require "tests"

local EXE  = ENV .. " ../src/freechains --root " .. ROOT
local REPO = ROOT .. "/chains/now/"

exec("rm -rf " .. TMP)
exec("mkdir -p " .. ROOT)

-- GENESIS TIMESTAMP
do
    print("==> Genesis timestamp")

    do
        TEST "genesis with --now=0"
        exec(EXE .. " --now=0 chains add now dir " .. GEN)
        local ts = exec("git -C " .. REPO .. " log -1 --format=%at")
        assert(ts == "0", "genesis timestamp: " .. ts)
    end

    do
        TEST "committer date also set"
        local ts = exec("git -C " .. REPO .. " log -1 --format=%ct")
        assert(ts == "0", "committer timestamp: " .. ts)
    end
end

-- POST TIMESTAMP
do
    print("==> Post timestamp")

    do
        TEST "post with --now=100"
        local out = exec(EXE .. " --now=100 chain now post inline 'hello'")
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. REPO .. " log -1 --format=%at")
        assert(ts == "100", "post timestamp: " .. ts)
    end

    do
        TEST "post with --now=200"
        local out = exec(EXE .. " --now=200 chain now post inline 'world'")
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. REPO .. " log -1 --format=%at")
        assert(ts == "200", "post timestamp: " .. ts)
    end

    do
        TEST "post without --now uses system clock"
        local before = os.time()
        local out = exec(EXE .. " chain now post inline 'no fake time'")
        local after = os.time()
        assert(#out == 40, "hash: " .. out)
        local ts = tonumber((exec("git -C " .. REPO .. " log -1 --format=%at")))
        assert(ts >= before and ts <= after, "timestamp not in range: " .. ts)
    end
end

-- LIKE TIMESTAMP
do
    print("==> Like timestamp")

    do
        TEST "like with --now=300"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(EXE .. " --now=0 chains add now dir " .. GEN_1P)
        local target = exec(EXE .. " --now=100 chain now post inline 'target' --sign " .. KEY)
        exec(EXE .. " --now=300 chain now like +1 post " .. target .. " --sign " .. KEY)
        local ts = exec("git -C " .. REPO .. " log -1 --format=%at")
        assert(ts == "300", "like timestamp: " .. ts)
    end
end

-- INCREASING TIMESTAMPS
do
    print("==> Increasing timestamps in log")

    do
        TEST "all commits have expected timestamps"
        exec("rm -rf " .. TMP)
        exec("mkdir -p " .. ROOT)
        exec(EXE .. " --now=0 chains add now dir " .. GEN)
        exec(EXE .. " --now=100 chain now post inline 'first'")
        exec(EXE .. " --now=200 chain now post inline 'second'")
        exec(EXE .. " --now=300 chain now post inline 'third'")

        -- newest first
        local logs = exec("git -C " .. REPO .. " log --format=%at")
        local times = {}
        for t in logs:gmatch("%d+") do
            times[#times+1] = tonumber(t)
        end
        assert(#times == 4, "expected 4 commits: " .. #times)
        assert(times[1] == 300, "t[1]: " .. times[1])
        assert(times[2] == 200, "t[2]: " .. times[2])
        assert(times[3] == 100, "t[3]: " .. times[3])
        assert(times[4] == 0,   "t[4]: " .. times[4])
    end
end

print("<== ALL PASSED")
