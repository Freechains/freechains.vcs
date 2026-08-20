#!/usr/bin/env lua5.4

-- A command samples `CMD.now = os.time()` at startup, applies with it,
-- and writes it into `state/now.lua`. The commit itself is stamped
-- LATER, by git, at wall clock. Without `--now` the two are unpinned:
-- a second ticking between `os.time()` and `git commit` leaves the
-- state one second below its own commit.
--
-- The receiver then rejects the HONEST chain: `commit` (sync.lua)
-- checks every state commit with
--
--     PEAK(hash) == PEAKS(parents(hash))    -- %at vs recorded now
--
-- where `PEAKS` reads the post's `%at` (wall clock) and `PEAK` reads
-- the recorded `now.lua` (os.time()) -- off by one, so
-- "invalid state : now" for a chain nobody forged.
--
-- Every test passes `--now`, which pins GIT_AUTHOR_DATE and
-- GIT_COMMITTER_DATE to CMD.now, so the bug never shows there.
--
-- Reproduced deterministically, no sleeps: without `--now`, `CMD.git`
-- is empty, so git honors EXTERNAL date env vars. Setting them ahead
-- of the clock emulates exactly the tick between `os.time()` and the
-- commit. The fix -- always pin the dates from `CMD.now` -- overrides
-- this env and makes the skew impossible.

require "tests"

local ROOT_A = ROOT .. "/bug-now-skew/A/"
local ROOT_X = ROOT .. "/bug-now-skew/X/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_X  = ENV .. " ../src/freechains.lua --root " .. ROOT_X

local REPO_A = ROOT_A .. "chains/#ns/"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_X,
}

do
    print("==> Test: 1s clock skew must not poison an honest chain")

    -- everything runs on the REAL clock: no --now anywhere
    TEST "A creates chain + seeds s.txt"
    exec {
        cmd = EXE_A .. " chains add '#ns' init file " .. GEN_2,
    }
    exec {
        cmd = EXE_A .. " chain '#ns' post inline 'seed\n' --sign " .. KEY1,
    }

    TEST "X clones ns"
    exec {
        cmd = EXE_X .. " chains add '#ns' clone " .. REPO_A,
    }

    -- the tick: git stamps the commit 60s after os.time(); the state
    -- still records os.time(). Same shape as a 1s tick, just certain.
    TEST "A posts skew with the clock ticking mid-command"
    do
        local future = os.time() + 60
        exec {
            cmd = "GIT_AUTHOR_DATE='@" .. future .. " +0000'" ..
                " GIT_COMMITTER_DATE='@" .. future .. " +0000' " ..
                EXE_A .. " chain '#ns' post inline 'skew\n' --sign " .. KEY1,
        }
    end

    -- nothing was forged: real content, real signature, honest state.
    -- The receiver must accept it. Today it fails with
    -- "invalid state : now", punishing A for its own clock.
    TEST "X recvs A: the honest chain must be accepted"
    exec {
        cmd = EXE_X .. " chain '#ns' sync recv " .. REPO_A,
    }

    TEST "X has both posts (seed + skew)"
    do
        local out = exec {
            cmd = EXE_X .. " chain '#ns' list order",
        }
        local n = 0
        for _ in out:gmatch("[^\n]+") do n = n + 1 end
        assert(n == 2, "expected 2 entries, got " .. n)
    end
end

print("<== ALL PASSED")
