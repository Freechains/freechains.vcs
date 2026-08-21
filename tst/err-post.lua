#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/err-post/A/"
local ROOT_B = ROOT .. "/err-post/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}

-- craft a post action commit by hand: proper aid path, signed
-- commit; the file IS the time source (dates are neutral)
local function craft (repo, key, pub, now, back)
    -- positional post with an all-zero payload blob; time is the
    -- commit DATE; sign/backs are structural (gpgsig/parent)
    COMMIT(repo, {
        msg  = "post\n0000000000000000000000000000000000000000\n",
        date = now,
        sign = key,
    })
end

-- sync rejects post from author with insufficient reputation
do
    print("==> sync rejects post with insufficient reputation")

    local REPO_A1 = ROOT_A .. "/chains/#err-reps/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#err-reps' init " .. GEN_1,
    }
    local legit = exec {
        cmd = EXE_A .. " --now=2000 chain '#err-reps' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-reps' clone " .. REPO_A1,
    }

    TEST "A crafts post signed by non-pioneer (0 reps)"
    craft(REPO_A1, KEY3, PUB3, 3000, legit)

    TEST "B rejects post with insufficient reps on sync"
    FAIL {
        cmd = EXE_B .. " --now=3000 chain '#err-reps' sync recv " .. REPO_A1,
        err = "ERROR : chain sync : invalid post : insufficient reputation",
    }
end

-- sync rejects post with too big time difference
do
    print("==> sync rejects post with too old timestamp")

    local REPO_A2 = ROOT_A .. "/chains/#err-time/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " --now=10000 chains add '#err-time' init " .. GEN_1,
    }
    local legit = exec {
        cmd = EXE_A .. " --now=11000 chain '#err-time' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-time' clone " .. REPO_A2,
    }

    TEST "A crafts post with old timestamp"
    craft(REPO_A2, KEY1, PUB1, 1, legit)

    TEST "B rejects post with old timestamp on sync"
    FAIL {
        cmd = EXE_B .. " --now=11000 chain '#err-time' sync recv " .. REPO_A2,
        err = "ERROR : chain sync : invalid post : too old",
    }
end

-- sync rejects a post stamped beyond the receiver's own clock:
-- `too old` is DAG-derived, but nothing bounds a time from above
-- except the receiver. `--now` is all an attacker needs
do
    print("==> sync rejects post with future timestamp")

    local REPO_A5 = ROOT_A .. "/chains/#err-future/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " --now=10000 chains add '#err-future' init " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " --now=11000 chain '#err-future' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-future' clone " .. REPO_A5,
    }

    TEST "A posts far in the future (its own clock, its own rule)"
    exec {
        cmd = EXE_A .. " --now=99999999 chain '#err-future' post inline 'ahead' --sign " .. KEY1,
    }

    TEST "B rejects the future post on sync"
    FAIL {
        cmd = EXE_B .. " --now=12000 chain '#err-future' sync recv " .. REPO_A5,
        err = "ERROR : chain sync : invalid post : too new",
    }
end

-- sync rejects post with forged signature
do
    print("==> sync rejects forged signature post")

    local REPO_A3 = ROOT_A .. "/chains/#err-forge/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#err-forge' init " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " --now=2000 chain '#err-forge' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-forge' clone " .. REPO_A3,
    }

    TEST "A crafts a post with forged signature"
    exec {
        cmd = EXE_A .. " --now=3000 chain '#err-forge' post inline 'original content' --sign " .. KEY1,
    }
    -- Tamper the SIGNED action (the message): flip the time digit
    -- so the body still parses but the ssh signature no longer
    -- matches. gpgsig header stays intact -> caught as forged
    local raw = exec { trim=false,
        cmd = "git -C " .. REPO_A3 .. " cat-file commit HEAD",
    }
    local forged = raw:gsub('\n(author [^\n]* )3000( )', '\n%13001%2', 1)
    local tmpf = REPO_A3 .. "forged-commit"
    local fh = io.open(tmpf, "w")
    fh:write(forged)
    fh:close()
    local new_hash = exec {
        cmd = "git -C " .. REPO_A3 .. " hash-object -t commit -w --stdin <" .. tmpf,
    }
    os.remove(tmpf)
    exec {
        cmd = "git -C " .. REPO_A3 .. " update-ref HEAD " .. new_hash,
    }

    TEST "B rejects forged signature on sync"
    FAIL {
        cmd = EXE_B .. " --now=3000 chain '#err-forge' sync recv " .. REPO_A3,
        err = "ERROR : chain sync : malformed commit : invalid signature",
    }
end

-- sync fetch failed
do
    print("==> sync fetch failed")

    TEST "sync recv from nonexistent remote"
    local err = FAIL {
        cmd = EXE_A .. " chain '#err-forge' sync recv /nonexistent/repo",
    }
    assert(err == [[
ERROR : chain sync : fetch failed
>>>
fatal: '/nonexistent/repo/#err-forge' does not appear to be a git repository
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
<<<
]])
end

print("<== ALL PASSED")
