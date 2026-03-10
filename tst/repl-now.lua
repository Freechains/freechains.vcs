#!/usr/bin/env lua5.4

require "tests"

-- LOCAL REPLICATION
do
    print("==> --now: local replication")

    local ROOT_A = ROOT .. "/repl-now/A/"
    local ROOT_B = ROOT .. "/repl-now/B/"
    local EXE_A  = ENV .. " ../src/freechains --root " .. ROOT_A
    local EXE_B  = ENV .. " ../src/freechains --root " .. ROOT_B
    local REPO_A = ROOT_A .. "/chains/now/"
    local REPO_B = ROOT_B .. "/chains/now/"

    exec("rm -rf " .. TMP)
    exec("mkdir -p " .. ROOT_A)
    exec("mkdir -p " .. ROOT_B)

    do
        TEST "genesis with --now=0"
        exec(EXE_A .. " --now=0 chains add now dir " .. GEN)
        local ts = exec("git -C " .. REPO_A .. " log -1 --format=%at")
        assert(ts == "0", "genesis timestamp: " .. ts)
    end

    do
        TEST "post with --now=100"
        local out = exec(EXE_A .. " --now=100 chain now post inline 'hello'")
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. REPO_A .. " log -1 --format=%at")
        assert(ts == "100", "post timestamp: " .. ts)
    end

    do
        TEST "timestamps survive local clone"
        exec("mkdir -p " .. ROOT_B .. "/chains")
        local tmp = ROOT_B .. "/chains/_tmp"
        exec("git clone " .. REPO_A .. " " .. tmp)
        local hash = exec("git -C " .. tmp .. " rev-list --max-parents=0 HEAD")
        exec("mv " .. tmp .. " " .. ROOT_B .. "/chains/" .. hash)
        exec("ln -s " .. hash .. " " .. ROOT_B .. "/chains/now")
        git_config(REPO_B)

        local ts = exec("git -C " .. REPO_B .. " log -1 --format=%at")
        assert(ts == "100", "cloned post timestamp: " .. ts)
        local gen_ts = exec("git -C " .. REPO_B .. " log -1 --format=%at " .. hash)
        assert(gen_ts == "0", "cloned genesis timestamp: " .. gen_ts)
    end

    do
        TEST "post on B with --now=200"
        local out = exec(EXE_B .. " --now=200 chain now post inline 'world'")
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. REPO_B .. " log -1 --format=%at")
        assert(ts == "200", "B post timestamp: " .. ts)
    end

    do
        TEST "timestamps survive local fetch+merge"
        local branch = exec("git -C " .. REPO_A .. " rev-parse --abbrev-ref HEAD")
        exec("git -C " .. REPO_A .. " fetch " .. REPO_B .. " " .. branch)
        exec("git -C " .. REPO_A .. " merge --no-edit FETCH_HEAD")

        local logs = exec("git -C " .. REPO_A .. " log --format=%at --all")
        assert(logs:match("200"), "t=200 not found in log")
        assert(logs:match("100"), "t=100 not found in log")
        assert(logs:match("0"), "t=0 not found in log")
    end
end

-- REMOTE REPLICATION
do
    print("==> --now: remote replication")

    local ROOT_A = ROOT .. "/repl-now-remote/A/"
    local ROOT_B = ROOT .. "/repl-now-remote/B/"
    local EXE_A  = ENV .. " ../src/freechains --root " .. ROOT_A
    local EXE_B  = ENV .. " ../src/freechains --root " .. ROOT_B
    local REPO_A = ROOT_A .. "/chains/now/"
    local REPO_B = ROOT_B .. "/chains/now/"

    local PORT_A = 19421
    local PORT_B = 19422
    local URL_A  = "git://127.0.0.1:" .. PORT_A .. "/"
    local URL_B  = "git://127.0.0.1:" .. PORT_B .. "/"
    local PID_A  = ROOT_A .. "/daemon.pid"
    local PID_B  = ROOT_B .. "/daemon.pid"

    exec("mkdir -p " .. ROOT_A .. "/chains")
    exec("mkdir -p " .. ROOT_B .. "/chains")

    do
        TEST "genesis with --now=0 (remote)"
        exec(EXE_A .. " --now=0 chains add now dir " .. GEN)
        local ts = exec("git -C " .. REPO_A .. " log -1 --format=%at")
        assert(ts == "0", "genesis timestamp: " .. ts)
    end

    do
        TEST "post with --now=100 (remote)"
        local out = exec(EXE_A .. " --now=100 chain now post inline 'hello'")
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. REPO_A .. " log -1 --format=%at")
        assert(ts == "100", "post timestamp: " .. ts)
    end

    daemon_start(PORT_A, PID_A, ROOT_A .. "/chains/")
    daemon_start(PORT_B, PID_B, ROOT_B .. "/chains/")
    os.execute("sleep 0.3")

    local _ <close> = setmetatable({}, {__close=function()
        daemon_stop(PID_A)
        daemon_stop(PID_B)
    end})

    do
        TEST "timestamps survive clone via git://"
        local tmp = ROOT_B .. "/chains/_tmp"
        exec("git clone " .. URL_A .. "now/ " .. tmp)
        local hash = exec("git -C " .. tmp .. " rev-list --max-parents=0 HEAD")
        exec("mv " .. tmp .. " " .. ROOT_B .. "/chains/" .. hash)
        exec("ln -s " .. hash .. " " .. ROOT_B .. "/chains/now")
        git_config(REPO_B)

        local ts = exec("git -C " .. REPO_B .. " log -1 --format=%at")
        assert(ts == "100", "cloned post timestamp: " .. ts)
        local gen_ts = exec("git -C " .. REPO_B .. " log -1 --format=%at " .. hash)
        assert(gen_ts == "0", "cloned genesis timestamp: " .. gen_ts)
    end

    do
        TEST "post on B with --now=200 (remote)"
        local out = exec(EXE_B .. " --now=200 chain now post inline 'world'")
        assert(#out == 40, "hash: " .. out)
        local ts = exec("git -C " .. REPO_B .. " log -1 --format=%at")
        assert(ts == "200", "B post timestamp: " .. ts)
    end

    do
        TEST "timestamps survive fetch+merge via git://"
        local branch = exec("git -C " .. REPO_A .. " rev-parse --abbrev-ref HEAD")
        exec("git -C " .. REPO_A .. " fetch " .. URL_B .. "now/ " .. branch)
        exec("git -C " .. REPO_A .. " merge --no-edit FETCH_HEAD")

        local logs = exec("git -C " .. REPO_A .. " log --format=%at --all")
        assert(logs:match("200"), "t=200 not found in log")
        assert(logs:match("100"), "t=100 not found in log")
        assert(logs:match("0"), "t=0 not found in log")
    end
end

print("<== ALL PASSED")
