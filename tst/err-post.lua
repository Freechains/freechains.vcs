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
local function craft (repo, key, pub, now)
    local f = io.open(repo .. "forged.lua", "w")
    f:write('return {\n'
        .. '    ["action"] = "post",\n'
        .. '    ["backs"] = {},\n'     -- B7 will require the real backs
        .. '    ["sign"] = "' .. pub .. '",\n'
        .. '    ["time"] = ' .. now .. ',\n'
        .. '}\n')
    f:close()
    local aid = exec {
        cmd = "git -C " .. repo .. " hash-object forged.lua",
    }
    exec {
        cmd = "mkdir -p " .. repo .. "actions/" .. aid:sub(1,2),
    }
    exec {
        cmd = "mv " .. repo .. "forged.lua " ..
            repo .. "actions/" .. aid:sub(1,2) .. "/" .. aid .. ".lua",
    }
    exec {
        cmd = "git -C " .. repo .. " add actions/",
    }
    exec {
        cmd = ENV .. " git -C " .. repo ..
            " -c user.signingkey=" .. key .. " -c gpg.format=ssh" ..
            " commit -S --allow-empty-message -m ''",
    }
end

-- sync rejects post from author with insufficient reputation
do
    print("==> sync rejects post with insufficient reputation")

    local REPO_A1 = ROOT_A .. "/chains/#err-reps/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#err-reps' init file " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " --now=2000 chain '#err-reps' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-reps' clone " .. REPO_A1,
    }

    TEST "A crafts post signed by non-pioneer (0 reps)"
    craft(REPO_A1, KEY3, PUB3, 3000)

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
        cmd = EXE_A .. " --now=10000 chains add '#err-time' init file " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " --now=11000 chain '#err-time' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-time' clone " .. REPO_A2,
    }

    TEST "A crafts post with old timestamp"
    craft(REPO_A2, KEY1, PUB1, 1)

    TEST "B rejects post with old timestamp on sync"
    FAIL {
        cmd = EXE_B .. " --now=11000 chain '#err-time' sync recv " .. REPO_A2,
        err = "ERROR : chain sync : invalid post : too old",
    }
end

-- sync rejects post with forged signature
do
    print("==> sync rejects forged signature post")

    local REPO_A3 = ROOT_A .. "/chains/#err-forge/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#err-forge' init file " .. GEN_1,
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
    -- Tamper: append a message; tree, dates and gpgsig stay intact
    local raw = exec { trim=false,
        cmd = "git -C " .. REPO_A3 .. " cat-file commit HEAD",
    }
    local forged = raw .. "tampered\n"
    local tmpf = REPO_A3 .. ".git/forged-commit"
    local fh = io.open(tmpf, "w")
    fh:write(forged)
    fh:close()
    local new_hash = exec {
        cmd = "git -C " .. REPO_A3 .. " hash-object -t commit -w --stdin <" .. tmpf,
    }
    os.remove(tmpf)
    exec {
        cmd = "git -C " .. REPO_A3 .. " reset --hard " .. new_hash,
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
