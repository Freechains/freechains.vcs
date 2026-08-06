#!/usr/bin/env lua5.4

-- Trailers are gone (S11a): the tree classifies. A commit that adds a
-- payload but NO action file cannot be an action, and with one parent
-- it cannot be a merge either -- refused by shape, with the project's
-- `ERROR : <command> : <detail>` format, never a raw Lua traceback.
--
-- The forged commit here claims to be a post via its MESSAGE alone
-- ("Freechains: post" as the subject); classification never reads the
-- message, so the claim is inert and the shape decides.

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
    print("==> Test: action-less commit is refused by shape")

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
    TEST "A hand-forges a payload-only commit (message claims post)"
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

    TEST "the message-only claim is inert"
    do
        local out = exec {
            cmd = "git -C " .. REPO_A ..
                " log -1 --format='%(trailers:key=Freechains,valueonly)' HEAD",
        }
        assert(out == "", "expected no trailer, got: " .. out)
    end

    -- payload-only, 1 parent: not an action, not a merge
    TEST "X recvs A: must name the problem, not leak a traceback"
    FAIL {
        cmd = EXE_X .. " --now=1200 chain '#ek' sync recv " .. REPO_A,
        err = "ERROR : chain sync : invalid commit : expects one action file",
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
