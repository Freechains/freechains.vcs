#!/usr/bin/env lua5.4

require "tests"

-- `daemon start` serves the local chains; `daemon stop` kills the
-- daemon on that port. The pid file is written by `git daemon`
-- itself (`--pid-file`), and lives at `<root>/daemon.pid`.
-- `start` blocks, so it runs backgrounded here, as scripts do.

local ROOT_A = ROOT .. "/cli-daemon/A/"
local ROOT_B = ROOT .. "/cli-daemon/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_B = ROOT_B .. "/chains/#cli-daemon/"

local PORT = 18330
local PID  = ROOT_A .. "/daemon.pid"

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
        cmd = EXE_A .. " chains add '#cli-daemon' init " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain '#cli-daemon' post inline 'served' --sign " .. KEY1,
    }

    TEST "start serves in the background"
    exec {
        cmd = EXE_A .. " daemon start --port=" .. PORT .. XTRA ..
            " >/dev/null 2>&1 &",
    }
    exec {
        cmd = "sleep 1",
    }

    TEST "the pid file exists and holds a live pid"
    local f = io.open(PID)
    assert(f, "no pid file at " .. PID)
    local pid = f:read("a"):match("^%s*(%d+)")
    f:close()
    assert(pid, "pid file holds no number")
    local ok = exec { err=false, stderr=false,
        cmd = "kill -0 " .. pid,
    }
    assert(ok ~= false, "pid " .. pid .. " is not alive")

    TEST "B clones through the daemon (it really serves)"
    exec {
        cmd = EXE_B .. " chains add '#cli-daemon' clone localhost:" .. PORT,
    }
    local O = ORDER(EXE_B, "#cli-daemon")
    assert(#O == 1 and O[1] == post, "B did not receive the post")

    TEST "B sends to a daemon without --hub -> not a hub"
    -- the daemon serves fetches only, so `git daemon` refuses the
    -- push before the hook ever runs: the reason must be ours, not
    -- git's "access denied or repository not exported"
    exec {
        cmd = EXE_B .. " chain '#cli-daemon' post inline 'pushed'"
            .. " --sign " .. KEY1,
    }
    FAIL {
        cmd = EXE_B .. " chain '#cli-daemon' sync send localhost:" .. PORT,
        err = "ERROR : chain sync : remote refused push : daemon without --hub",
    }

    TEST "B sends to a chain the daemon does not have -> no such chain"
    FAIL {
        cmd = EXE_B .. " chain '#cli-daemon' sync send localhost:" .. PORT .. "/#none",
        err = "ERROR : chain sync : remote refused push : no such chain",
    }

    TEST "A kept none of it"
    local OA = ORDER(EXE_A, "#cli-daemon")
    assert(#OA == 1 and OA[1] == post, "A is not untouched")

    TEST "stop prints the pid it killed and removes the file"
    local killed = exec {
        cmd = EXE_A .. " daemon stop",
    }
    assert(killed == pid, "stopped " .. killed .. ", expected " .. pid)
    assert(not io.open(PID), "pid file still there")

    TEST "the daemon is really gone"
    exec {
        cmd = "sleep 1",
    }
    local alive = exec { err=false, stderr=false,
        cmd = "kill -0 " .. pid,
    }
    assert(alive == false, "pid " .. pid .. " still alive")
end

print("==> daemon --hub")

do
    local HUB = PORT + 1

    TEST "A serves as a hub"
    exec {
        cmd = EXE_A .. " daemon start --hub --port=" .. HUB .. XTRA ..
            " >/dev/null 2>&1 &",
    }
    exec {
        cmd = "sleep 1",
    }

    TEST "B sends the post the plain daemon refused"
    exec {
        cmd = EXE_B .. " chain '#cli-daemon' sync send localhost:" .. HUB,
    }
    local OA = ORDER(EXE_A, "#cli-daemon")
    assert(#OA == 2, "A did not receive B's post")

    TEST "a hub whose own recv fails is not a refused push"
    -- the hook's `recv` fetches back from the url I advertise: point it
    -- at a chain the hub does not have and it fails QUOTING git's own
    -- "no such repository", which must not read as my push being
    -- refused -- the sender needs the hook's reason, verbatim
    local url = exec {
        cmd = "git -C " .. REPO_B .. " config freechains.url",
    }
    exec {
        cmd = "git -C " .. REPO_B .. " config freechains.url"
            .. " 'git://localhost:" .. HUB .. "/#none'",
    }
    exec {
        cmd = EXE_B .. " chain '#cli-daemon' post inline 'again'"
            .. " --sign " .. KEY1,
    }
    local err = FAIL {
        cmd = EXE_B .. " chain '#cli-daemon' sync send localhost:" .. HUB,
    }
    assert (
        err and err:find("ERROR : chain sync : fetch failed", 1, true),
        "hub recv failure : unexpected stderr: " .. tostring(err)
    )
    exec {
        cmd = "git -C " .. REPO_B .. " config freechains.url '" .. url .. "'",
    }

    TEST "the hub stops"
    exec {
        cmd = EXE_A .. " daemon stop",
    }
end

print("==> daemon stop errors")

do
    TEST "stop with no daemon running"
    FAIL {
        cmd = EXE_A .. " daemon stop",
        err = "ERROR : daemon stop : not running",
    }

    TEST "stop on a dead pid reports not running"
    -- the file outlives the process it names
    local f = io.open(PID, "w")
    f:write("2147483646\n")
    f:close()
    FAIL {
        cmd = EXE_A .. " daemon stop",
        err = "ERROR : daemon stop : not running",
    }
    assert(not io.open(PID), "pid file should be gone")
end

print("<== ALL PASSED")
