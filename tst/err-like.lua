#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/err-sign/A/"
local ROOT_B = ROOT .. "/err-sign/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/#err-sign/"
local REPO_B = ROOT_B .. "/chains/#err-sign/"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}

-- craft an action commit by hand: `content` becomes the action file
-- (placed at its own hash), the commit signed by `key`
-- (unsigned when nil)
local function craft (repo, key, content)
    local f = io.open(repo .. "crafted.lua", "w")
    f:write(content)
    f:close()
    local aid = exec {
        cmd = "git -C " .. repo .. " hash-object crafted.lua",
    }
    exec {
        cmd = "mkdir -p " .. repo .. "actions/" .. aid:sub(1,2),
    }
    exec {
        cmd = "mv " .. repo .. "crafted.lua " ..
            repo .. "actions/" .. aid:sub(1,2) .. "/" .. aid .. ".lua",
    }
    exec {
        cmd = "git -C " .. repo .. " add actions/",
    }
    local sign = key and
        (" -c user.signingkey=" .. key .. " -c gpg.format=ssh") or ""
    local S = key and " -S" or ""
    exec {
        cmd = ENV .. " git -C " .. repo .. sign ..
            " commit" .. S .. " --allow-empty-message -m ''",
    }
end

-- a like action file: `sign` must match the envelope signature,
-- `time` is the action's own clock (dates are neutral); the
-- target line is passed raw so tests can misname or omit it
local function like_file (target, n, pub, now)
    return 'return {\n'
        .. '    ["action"] = "like",\n'
        .. (target and ('    ' .. target .. ',\n') or '')
        .. '    ["backs"] = {},\n'     -- B7 will require the real backs
        .. '    ["n"] = ' .. n .. ',\n'
        .. (pub and ('    ["sign"] = "' .. pub .. '",\n') or '')
        .. '    ["time"] = ' .. now .. ',\n'
        .. '}\n'
end

-- sync rejects unsigned like from remote

print("==> sync rejects unsigned like")

local POST

do
    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " chains add '#err-sign' init file " .. GEN_1,
    }

    TEST "A posts signed"
    POST = exec {
        cmd = EXE_A .. " chain '#err-sign' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-sign' clone " .. REPO_A,
    }
end

-- craft unsigned like directly via git (bypass freechains)
do
    TEST "A crafts unsigned like via raw git"
    local now = os.time()
    craft(REPO_A, nil, like_file('["aid"] = "' .. POST .. '"', 1000, nil, now))

    TEST "B rejects unsigned like on sync"
    FAIL {
        cmd = EXE_B .. " chain '#err-sign' sync recv " .. REPO_A,
        err = "ERROR : chain sync : malformed commit : expected signature",
    }
end

-- sync rejects a signed commit that carries no action at all
do
    print("==> sync rejects empty commit (no action file)")

    local REPO_A2 = ROOT_A .. "/chains/#err-payload/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add '#err-payload' init file " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " chain '#err-payload' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-payload' clone " .. REPO_A2,
    }

    TEST "A crafts an empty commit"
    exec {
        cmd = ENV .. " git -C " .. REPO_A2 .. " -c user.signingkey=" .. KEY1 .. " -c gpg.format=ssh" .. " commit --allow-empty -S -m 'x'",
    }

    TEST "B rejects the empty commit on sync"
    FAIL {
        cmd = EXE_B .. " chain '#err-payload' sync recv " .. REPO_A2,
        err = "ERROR : chain sync : malformed commit : expected 2-parent merge",
    }
end

-- sync rejects an action file that is not valid lua (syntax error)
do
    print("==> sync rejects bad action file (syntax error)")

    local REPO_A3 = ROOT_A .. "/chains/#err-lua/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add '#err-lua' init file " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " chain '#err-lua' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-lua' clone " .. REPO_A3,
    }

    TEST "A crafts action file with invalid lua"
    craft(REPO_A3, KEY1, "not valid lua !!!\n")

    TEST "B rejects bad lua on sync"
    FAIL {
        cmd = EXE_B .. " chain '#err-lua' sync recv " .. REPO_A3,
        err = "ERROR : chain sync : malformed commit : invalid action file",
    }
end

-- sync rejects an action file that is not a table
do
    print("==> sync rejects bad action file (not table)")

    local REPO_A4 = ROOT_A .. "/chains/#err-table/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add '#err-table' init file " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " chain '#err-table' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-table' clone " .. REPO_A4,
    }

    TEST "A crafts action file that is not a table"
    craft(REPO_A4, KEY1, "return 10\n")

    TEST "B rejects bad lua on sync"
    FAIL {
        cmd = EXE_B .. " chain '#err-table' sync recv " .. REPO_A4,
        err = "ERROR : chain sync : malformed commit : invalid action file",
    }
end

-- sync rejects like with invalid target type
do
    print("==> sync rejects like with bad target type")

    local REPO_A5 = ROOT_A .. "/chains/#err-target/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add '#err-target' init file " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain '#err-target' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-target' clone " .. REPO_A5,
    }

    TEST "A crafts like with bad target type"
    local now = os.time()
    craft(REPO_A5, KEY1, like_file('["xxx"] = "' .. post .. '"', 1000, PUB1, now))

    TEST "B rejects like with bad target type on sync"
    FAIL {
        cmd = EXE_B .. " chain '#err-target' sync recv " .. REPO_A5,
        err = "ERROR : chain sync : invalid like : invalid target : expects 'action' or 'author'",
    }
end

-- sync rejects like with nonexistent post target
do
    print("==> sync rejects like with action not found")

    local REPO_A6 = ROOT_A .. "/chains/#err-post/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add '#err-post' init file " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " chain '#err-post' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-post' clone " .. REPO_A6,
    }

    TEST "A crafts like targeting nonexistent post"
    local now = os.time()
    craft(REPO_A6, KEY1, like_file('["aid"] = "0000000000000000000000000000000000000000"', 1000, PUB1, now))

    TEST "B rejects like with action not found on sync"
    FAIL {
        cmd = EXE_B .. " chain '#err-post' sync recv " .. REPO_A6,
        err = "ERROR : chain sync : invalid like : invalid target : action not found",
    }
end

-- sync rejects like from author with insufficient reputation
do
    print("==> sync rejects like with insufficient reputation")

    local REPO_A7 = ROOT_A .. "/chains/#err-reps/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add '#err-reps' init file " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain '#err-reps' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-reps' clone " .. REPO_A7,
    }

    TEST "A crafts like signed by non-pioneer (0 reps)"
    local now = os.time()
    craft(REPO_A7, KEY3, like_file('["aid"] = "' .. post .. '"', 1000, PUB3, now))

    TEST "B rejects like with insufficient reps on sync"
    FAIL {
        cmd = EXE_B .. " chain '#err-reps' sync recv " .. REPO_A7,
        err = "ERROR : chain sync : invalid like : insufficient reputation",
    }
end

-- sync rejects like with too big time difference
do
    print("==> sync rejects like with too big time difference")

    local REPO_A8 = ROOT_A .. "/chains/#err-time/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " --now=10000 chains add '#err-time' init file " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " --now=11000 chain '#err-time' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-time' clone " .. REPO_A8,
    }

    TEST "A crafts like with old timestamp"
    craft(REPO_A8, KEY1, like_file('["aid"] = "' .. post .. '"', 1000, PUB1, 1))

    TEST "B rejects like with old timestamp on sync"
    FAIL {
        cmd = EXE_B .. " --now=11000 chain '#err-time' sync recv " .. REPO_A8,
        err = "ERROR : chain sync : invalid like : too old",
    }
end

-- sync rejects like with fractional number
do
    print("==> sync rejects like with fractional number")

    local REPO_A9 = ROOT_A .. "/chains/#err-frac/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add '#err-frac' init file " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain '#err-frac' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-frac' clone " .. REPO_A9,
    }

    TEST "A crafts like with fractional number"
    local now = os.time()
    craft(REPO_A9, KEY1, like_file('["aid"] = "' .. post .. '"', "0.5", PUB1, now))

    TEST "B rejects like with fractional number on sync"
    FAIL {
        cmd = EXE_B .. " chain '#err-frac' sync recv " .. REPO_A9,
        err = "ERROR : chain sync : invalid like : invalid number : expects non-zero integer",
    }
end

-- sync rejects like with zero number
do
    print("==> sync rejects like with zero number")

    local REPO_A10 = ROOT_A .. "/chains/#err-zero/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add '#err-zero' init file " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain '#err-zero' post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-zero' clone " .. REPO_A10,
    }

    TEST "A crafts like with zero number"
    local now = os.time()
    craft(REPO_A10, KEY1, like_file('["aid"] = "' .. post .. '"', 0, PUB1, now))

    TEST "B rejects like with zero number on sync"
    FAIL {
        cmd = EXE_B .. " chain '#err-zero' sync recv " .. REPO_A10,
        err = "ERROR : chain sync : invalid like : invalid number : expects non-zero integer",
    }
end

-- sync rejects like with forged signature
do
    print("==> sync rejects forged signature like")

    local REPO_A11 = ROOT_A .. "/chains/#err-forge-like/"

    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#err-forge-like' init file " .. GEN_1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add '#err-forge-like' clone " .. REPO_A11,
    }

    TEST "A crafts a like with forged signature"
    exec {
        cmd = EXE_A .. " --now=2000 chain '#err-forge-like' like 1000 author '" .. PUB1 .. "' --sign " .. KEY1,
    }
    -- Tamper: append a message; tree, dates and gpgsig stay intact
    local raw = exec { trim=false,
        cmd = "git -C " .. REPO_A11 .. " cat-file commit HEAD",
    }
    local forged = raw .. "tampered\n"
    local tmpf = REPO_A11 .. ".git/forged-commit"
    local fh = io.open(tmpf, "w")
    fh:write(forged)
    fh:close()
    local new_hash = exec {
        cmd = "git -C " .. REPO_A11 .. " hash-object -t commit -w --stdin <" .. tmpf,
    }
    os.remove(tmpf)
    exec {
        cmd = "git -C " .. REPO_A11 .. " reset --hard " .. new_hash,
    }

    TEST "B rejects forged like signature on sync"
    FAIL {
        cmd = EXE_B .. " --now=2000 chain '#err-forge-like' sync recv " .. REPO_A11,
        err = "ERROR : chain sync : malformed commit : invalid signature",
    }
end

print("<== ALL PASSED")
