#!/usr/bin/env lua5.4

-- git as the replication layer, over git-daemon: fetches and DRY-RUN
-- merges probe the substrate directly (no HEAD move), while actual
-- convergence goes through `sync recv` (state lives in local
-- snapshots, so a raw merge alone cannot produce an operable replica)

require "tests"

local ROOT_A = ROOT .. "/repl-remote-head/A/"
local ROOT_B = ROOT .. "/repl-remote-head/B/"
local ROOT_C = ROOT .. "/repl-remote-head/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root=" .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root=" .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root=" .. ROOT_C

local REPO_A = ROOT_A .. "/chains/#test/"
local REPO_B = ROOT_B .. "/chains/#test/"
local REPO_C = ROOT_C .. "/chains/#test/"

exec {
    cmd = "mkdir -p " .. ROOT_A .. "/chains",
}
exec {
    cmd = "mkdir -p " .. ROOT_B .. "/chains",
}
exec {
    cmd = "mkdir -p " .. ROOT_C .. "/chains",
}

local PORT_A = 19418
local PORT_B = 19419
local PORT_C = 19420

local URL_A  = "git://127.0.0.1:" .. PORT_A .. "/"
local URL_B  = "git://127.0.0.1:" .. PORT_B .. "/"
local URL_C  = "git://127.0.0.1:" .. PORT_C .. "/"

local PID_A  = ROOT_A .. "/daemon.pid"
local PID_B  = ROOT_B .. "/daemon.pid"
local PID_C  = ROOT_C .. "/daemon.pid"

local function daemon_start (exe, port, pid)
    exec {
        cmd = exe .. " daemon --hub --port=" .. port .. " --" .. " --listen=127.0.0.1" .. " --pid-file=" .. pid .. " --reuseaddr" .. " --detach",
    }
end

local function daemon_stop (pid)
    local f = io.open(pid)
    if f then
        local pid = f:read("a"):match("%d+")
        f:close()
        if pid then
            os.execute("kill " .. pid .. " 2>/dev/null")
        end
    end
end

daemon_start(EXE_A, PORT_A, PID_A)
daemon_start(EXE_B, PORT_B, PID_B)
daemon_start(EXE_C, PORT_C, PID_C)
os.execute("sleep 0.3") -- starting up daemons

local _ <close> = setmetatable({}, {__close=function()
    daemon_stop(PID_A)
    daemon_stop(PID_B)
    daemon_stop(PID_C)
end})

-- HOST A: create chain + post
local CHAIN_HASH
local P1

do
    print("==> Host A: create chain + post")

    do
        TEST "chain created"
        CHAIN_HASH = exec {
            cmd = EXE_A .. " chains add '#test' init file " .. GEN_1,
        }
        assert(#CHAIN_HASH == 41, "hash: " .. CHAIN_HASH)
        assert(CHAIN_HASH:match("^#%x+$"), "not hex")
    end

    do
        TEST "post on A"
        P1 = exec {
            cmd = EXE_A .. " chain '#test' post inline 'post from A' --sign " .. KEY1,
        }
        assert(#P1 == 40, "hash: " .. P1)
        assert(P1:match("^%x+$"), "not hex")
    end
end

-- HOST B: clone chain + post
local P2

do
    print("==> Host B: clone chain + post")

    do
        TEST "clone succeeds"
        exec {
            cmd = EXE_B .. " chains add '#test' clone '" .. URL_A .. "#test/'",
        }
    end

    do
        TEST "B has same genesis"
        local gen_a = exec {
            cmd = "git -C " .. REPO_A .. " rev-list --max-parents=0 HEAD",
        }
        local gen_b = exec {
            cmd = "git -C " .. REPO_B .. " rev-list --max-parents=0 HEAD",
        }
        assert(gen_a == gen_b, "genesis mismatch")
    end

    do
        TEST "B has 2 commits (genesis + post)"
        local count = exec {
            cmd = "git -C " .. REPO_B .. " rev-list --count HEAD",
        }
        assert(count == "2", "count: " .. count)
    end

    do
        TEST "post on B"
        P2 = exec {
            cmd = EXE_B .. " chain '#test' post inline 'post from B' --sign " .. KEY1,
        }
        assert(#P2 == 40, "hash: " .. P2)
        assert(P2:match("^%x+$"), "not hex")
    end

    do
        TEST "B has 3 commits (genesis + A post + B post)"
        local count = exec {
            cmd = "git -C " .. REPO_B .. " rev-list --count HEAD",
        }
        assert(count == "3", "count: " .. count)
    end
end

-- HOST A: raw fetch probes the substrate, recv converges
do
    print("==> Host A: fetch from B + recv")

    do
        TEST "fetch from B"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " fetch '" .. URL_B .. "#test/' main",
        }
        assert(code == 0, "fetch failed")

        TEST "dry-run merge ok"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " merge --no-commit --no-ff FETCH_HEAD",
        }
        assert(code == 0, "dry-run merge failed")
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " merge --abort",
        }
        assert(code == 0, "abort failed")

        TEST "A recvs from B (fast-forward)"
        exec {
            cmd = EXE_A .. " chain '#test' sync recv '" .. URL_B .. "#test/'",
        }
    end

    do
        TEST "A has 3 commits (fast-forward)"
        local count = exec {
            cmd = "git -C " .. REPO_A .. " rev-list --count HEAD",
        }
        assert(count == "3", "count: " .. count)
    end

    do
        TEST "both payloads present in A"
        local pa = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. P1,
        }
        local pb = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. P2,
        }
        assert(pa == "post from A", "A's post missing")
        assert(pb == "post from B", "B's post missing")
    end

    do
        TEST "A and B are equal"
        local _,ok = exec { err=false,
            cmd = "diff -r --exclude=.git " .. REPO_A .. " " .. REPO_B,
        }
        assert(ok==0, "A and B differ")
    end
end

-- BIDIRECTIONAL SYNC: both post, A recvs B, B recvs A
do
    print("==> Bidirectional sync")

    do
        TEST "A posts again"
        local out = exec {
            cmd = EXE_A .. " chain '#test' post inline 'second from A' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)

        TEST "B posts again"
        local out = exec {
            cmd = EXE_B .. " chain '#test' post inline 'second from B' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "A fetches from B"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " fetch '" .. URL_B .. "#test/' main",
        }
        assert(code == 0, "fetch failed")

        TEST "A dry-run merge ok"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " merge --no-commit --no-ff FETCH_HEAD",
        }
        assert(code == 0, "dry-run merge failed")
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " merge --abort",
        }
        assert(code == 0, "abort failed")

        TEST "A recvs B (true merge)"
        exec {
            cmd = EXE_A .. " chain '#test' sync recv '" .. URL_B .. "#test/'",
        }

        TEST "A has 6 commits (3 shared + 2 posts + merge)"
        local count = exec {
            cmd = "git -C " .. REPO_A .. " rev-list --count HEAD",
        }
        assert(count == "6", "count: " .. count)
    end

    do
        TEST "B recvs A (fast-forward)"
        exec {
            cmd = EXE_B .. " chain '#test' sync recv '" .. URL_A .. "#test/'",
        }

        TEST "B has 6 commits"
        local count = exec {
            cmd = "git -C " .. REPO_B .. " rev-list --count HEAD",
        }
        assert(count == "6", "count: " .. count)
    end

    do
        TEST "A and B are equal after bidirectional sync"
        local _, ok = exec { err=false,
            cmd = "diff -r --exclude=.git " .. REPO_A .. " " .. REPO_B,
        }
        assert(ok == 0, "A and B differ")
    end
end

-- UNRELATED HISTORIES: independent chain creation must fail sync
do
    print("==> Unrelated histories rejected")

    local h = exec {
        cmd = EXE_C .. " chains add '#test' init file " .. GEN_1,
    }
    assert(h ~= CHAIN_HASH, "should differ")

    do
        TEST "fetch from unrelated chain succeeds"
        local _, code = exec {
            cmd = "git -C " .. REPO_C .. " fetch '" .. URL_A .. "#test/' main",
        }
        assert(code == 0, "fetch should succeed")

        TEST "dry-run merge from unrelated chain fails"
        FAIL {
            cmd = "git -C " .. REPO_C .. " merge --no-commit --no-ff FETCH_HEAD",
        }
    end
end

-- NO CONFLICT: payloads live outside the tree, so concurrent posts
-- can never collide on a path (the old shared-file conflict is gone)
do
    print("==> Concurrent posts do not conflict")

    local PA, PB

    do
        TEST "A posts concurrently"
        PA = exec {
            cmd = EXE_A .. " chain '#test' post" .. " inline 'from A\n' --sign " .. KEY1,
        }
        assert(#PA == 40, "hash: " .. PA)
    end

    do
        TEST "B posts concurrently"
        PB = exec {
            cmd = EXE_B .. " chain '#test' post" .. " inline 'from B\n' --sign " .. KEY1,
        }
        assert(#PB == 40, "hash: " .. PB)
    end

    do
        TEST "fetch succeeds"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " fetch '" .. URL_B .. "#test/' main",
        }
        assert(code == 0, "fetch should succeed")

        TEST "dry-run merge succeeds (no shared paths)"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " merge --no-commit --no-ff FETCH_HEAD",
        }
        assert(code == 0, "merge should not conflict")
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " merge --abort",
        }
        assert(code == 0, "abort failed")

        TEST "A recvs B (converges)"
        exec {
            cmd = EXE_A .. " chain '#test' sync recv '" .. URL_B .. "#test/'",
        }
    end

    do
        TEST "A holds both concurrent payloads"
        local pa = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. PA,
        }
        local pb = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. PB,
        }
        assert(pa == "from A", "A's payload missing")
        assert(pb == "from B", "B's payload missing")
    end
end

print("<== ALL PASSED")
