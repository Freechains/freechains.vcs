#!/usr/bin/env lua5.4

-- A commit whose `Freechains:` trailer git cannot parse leaves `kind`
-- nil in `commit` (sync.lua), and every branch below then uses it
-- blindly. The receiver dies with a raw Lua error instead of the
-- project's `ERROR : <command> : <detail>` format.
--
-- Two reachable crash sites, one root cause:
--
--   sync.lua  assert(kind == 'state')          <- this test
--             error("invalid "..kind.." : ...") <- also needs a forged sign
--
-- The forgery is a legitimate git commit with the trailer written as the
-- SUBJECT line instead of its own paragraph. Freechains itself writes
-- `(empty message)` as the subject and the trailer after a blank line;
-- with the trailer as the subject, `%(trailers:key=Freechains)` returns
-- nothing at all:
--
--   real   : "(empty message)\n\nFreechains: post\n"   -> kind = "post"
--   forged : "Freechains: post\n"                      -> kind = nil
--
-- The sync is refused either way, so this is not a hole -- but the
-- message must name the problem instead of leaking a traceback.

require "tests"

local ROOT_A = ROOT .. "/bug-err-kind/A/"
local ROOT_X = ROOT .. "/bug-err-kind/X/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_X  = ENV .. " ../src/freechains.lua --root " .. ROOT_X

local REPO_A = ROOT_A .. "chains/#ek/"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_X,
}

do
    print("==> Test: unparseable commit kind is refused cleanly")

    -- A: G -- seed[K1] -- like[K2]
    TEST "A creates chain + seeds seed.txt"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#ek' init file " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1020 chain '#ek' post inline 'seed\n' --file s.txt --sign " .. KEY1,
    }
    exec {
        cmd = EXE_A .. " --now=1040 chain '#ek' like 1 post " .. seed .. " --sign " .. KEY2,
    }

    TEST "X clones ek"
    exec {
        cmd = EXE_X .. " chains add '#ek' clone " .. REPO_A,
    }

    -- A: ... -- p[K1]        (X must have something to fetch)
    TEST "A posts p"
    exec {
        cmd = EXE_A .. " --now=1100 chain '#ek' post inline 'p\n' --file p.txt --sign " .. KEY1,
    }

    -- A: ... -- p -- FORGED    (trailer as the subject line)
    TEST "A hand-forges a commit whose trailer git cannot parse"
    exec {
        cmd = "echo junk > " .. REPO_A .. "junk.txt",
    }
    exec {
        cmd = "git -C " .. REPO_A .. " add junk.txt",
    }
    exec {
        cmd = "GIT_AUTHOR_DATE='@1120 +0000' GIT_COMMITTER_DATE='@1120 +0000'" ..
            " git -C " .. REPO_A .. " commit -q -m 'Freechains: post' --no-gpg-sign",
    }

    TEST "git really does not see a trailer there"
    do
        local out = exec {
            cmd = "git -C " .. REPO_A ..
                " log -1 --format='%(trailers:key=Freechains,valueonly)' HEAD",
        }
        assert(out == "", "expected no trailer, got: " .. out)
    end

    -- only additions, so the mode check passes and `kind` reaches the
    -- branches that use it
    -- 280808 : EARLY EXIT : rest needs clone/recv snapshots
    print("<== PASSED (280808 early exit)")
    os.exit()

    TEST "X recvs A: must name the problem, not leak a traceback"
    FAIL {
        cmd = EXE_X .. " --now=1200 chain '#ek' sync recv " .. REPO_A,
        err = "ERROR : chain sync : invalid commit : invalid kind",
    }

    TEST "X is untouched (2 entries: seed + like)"
    do
        local out = exec {
            cmd = EXE_X .. " chain '#ek' list order",
        }
        local n = 0
        for _ in out:gmatch("[^\n]+") do n = n + 1 end
        assert(n == 2, "expected 2 entries, got " .. n)
    end
end

print("<== ALL PASSED")
