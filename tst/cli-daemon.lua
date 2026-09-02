#!/usr/bin/env lua5.4

require "tests"

-- `daemon start` serves the local chains; `daemon stop` kills
-- every process holding the port (the listener AND its `--serve`
-- children, which inherit the listen socket).
-- `start` blocks, so it runs backgrounded here, as scripts do.

local ROOT_A = ROOT .. "/cli-daemon/A/"
local ROOT_B = ROOT .. "/cli-daemon/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local PORT = 18330

-- IPv4 only: a dual-stack [::] bind reserves the port, then fails
-- its own 0.0.0.0 bind
local XTRA = " -- --listen=127.0.0.1 --reuseaddr"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}

print("==> daemon start / stop")

do
    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add /cli-daemon init " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain /cli-daemon post inline 'served' --sign " .. KEY1,
    }

    TEST "start serves in the background"
    exec {
        cmd = EXE_A .. " daemon start --port=" .. PORT .. XTRA ..
            " >/dev/null 2>&1 &",
    }
    exec {
        cmd = "sleep 1",
    }

    TEST "the port is being served"
    local ok = exec { err=false, stderr=false,
        cmd = "ss -ltn | grep -q ':" .. PORT .. " '",
    }
    assert(ok ~= false, "nothing listens on " .. PORT)

    TEST "B clones through the daemon (it really serves)"
    exec {
        cmd = EXE_B .. " chains add /cli-daemon clone localhost:" .. PORT,
    }
    local O = ORDER(EXE_B, "/cli-daemon")
    assert(#O == 1 and O[1] == post, "B did not receive the post")

    TEST "stop prints the pids it killed"
    local killed = exec {
        cmd = EXE_A .. " daemon stop --port=" .. PORT,
    }
    assert(killed:match("^%d+"), "expected pids: " .. killed)

    TEST "the daemon is really gone"
    exec {
        cmd = "sleep 1",
    }
    local pid = killed:match("%d+")
    local alive = exec { err=false, stderr=false,
        cmd = "kill -0 " .. pid,
    }
    assert(alive == false, "pid " .. pid .. " still alive")
    local ok = exec { err=false, stderr=false,
        cmd = "ss -ltn | grep -q ':" .. PORT .. " '",
    }
    assert(ok == false, "port " .. PORT .. " still bound")
end

print("==> daemon stop errors")

do
    TEST "stop with no daemon running"
    FAIL {
        cmd = EXE_A .. " daemon stop --port=" .. PORT,
        err = "ERROR : daemon stop : not running",
    }

end

print("<== ALL PASSED")
