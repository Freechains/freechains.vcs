#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/err-sign/A/"
local ROOT_B = ROOT .. "/err-sign/B/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/err-sign/"
local REPO_B = ROOT_B .. "/chains/err-sign/"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}

-- craft an action commit by hand: `content` becomes the action file
-- (placed at its own hash), the commit signed by `key`
-- (unsigned when nil)
local function craft (repo, key, content, date)
    COMMIT(repo, {
        msg  = content,
        sign = key,
        date = date,
    })
end

-- a positional like message: `like <n>` + the target line; the
-- target is passed raw so tests can misname or omit it. `pub` is
-- unused (sign = gpgsig) and `now` becomes the craft's DATE (the
-- caller threads it to COMMIT); both kept for caller symmetry
local function like_file (target, n, pub, now, backs)
    return 'like ' .. n .. '\n'
        .. (target and (target .. '\n') or '')
end

-- sync rejects unsigned like from remote

print("==> sync rejects unsigned like")

local POST

do
    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " chains add /err-sign init " .. GEN_1,
    }

    TEST "A posts signed"
    POST = exec {
        cmd = EXE_A .. " chain /err-sign post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-sign clone " .. REPO_A,
    }
end

-- craft unsigned like directly via git (bypass freechains)
do
    TEST "A crafts unsigned like via raw git"
    local now = os.time()
    craft(REPO_A, nil, like_file('action ' .. POST, 1000, nil, now), now)

    TEST "B rejects unsigned like on sync"
    FAIL {
        cmd = EXE_B .. " chain /err-sign sync recv " .. REPO_A,
        err = "ERROR : chain sync : malformed commit : expected signature",
    }
end

-- sync rejects a signed commit that carries no action at all
do
    print("==> sync rejects empty commit (no action file)")

    local REPO_A2 = ROOT_A .. "/chains/err-payload/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add /err-payload init " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " chain /err-payload post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-payload clone " .. REPO_A2,
    }

    TEST "A crafts a 1-parent commit whose message is not an action"
    COMMIT(REPO_A2, { sign = KEY1, msg = "x" })

    TEST "B rejects it on sync (not a valid action)"
    FAIL {
        cmd = EXE_B .. " chain /err-payload sync recv " .. REPO_A2,
        err = "ERROR : chain sync : malformed commit : invalid action",
    }
end

-- sync rejects an action file that is not valid lua (syntax error)
do
    print("==> sync rejects bad action file (syntax error)")

    local REPO_A3 = ROOT_A .. "/chains/err-lua/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add /err-lua init " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " chain /err-lua post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-lua clone " .. REPO_A3,
    }

    TEST "A crafts action file with invalid lua"
    craft(REPO_A3, KEY1, "not valid lua !!!\n")

    TEST "B rejects bad lua on sync"
    FAIL {
        cmd = EXE_B .. " chain /err-lua sync recv " .. REPO_A3,
        err = "ERROR : chain sync : malformed commit : invalid action",
    }
end

-- sync rejects an action file that is not a table
do
    print("==> sync rejects bad action file (not table)")

    local REPO_A4 = ROOT_A .. "/chains/err-table/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add /err-table init " .. GEN_1,
    }
    exec {
        cmd = EXE_A .. " chain /err-table post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-table clone " .. REPO_A4,
    }

    TEST "A crafts action file that is not a table"
    craft(REPO_A4, KEY1, "return 10\n")

    TEST "B rejects bad lua on sync"
    FAIL {
        cmd = EXE_B .. " chain /err-table sync recv " .. REPO_A4,
        err = "ERROR : chain sync : malformed commit : invalid action",
    }
end

-- sync rejects like with invalid target type
do
    print("==> sync rejects like with bad target type")

    local REPO_A5 = ROOT_A .. "/chains/err-target/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add /err-target init " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain /err-target post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-target clone " .. REPO_A5,
    }

    TEST "A crafts like with bad target type"
    local now = os.time()
    craft(REPO_A5, KEY1, like_file('xxx ' .. post, 1000, PUB1, now), now)

    TEST "B rejects like with bad target type on sync"
    -- a bad target word cannot even PARSE as an action now
    FAIL {
        cmd = EXE_B .. " chain /err-target sync recv " .. REPO_A5,
        err = "ERROR : chain sync : malformed commit : invalid action",
    }
end

-- sync rejects like with nonexistent post target
do
    print("==> sync rejects like with action not found")

    local REPO_A6 = ROOT_A .. "/chains/err-post/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add /err-post init " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain /err-post post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-post clone " .. REPO_A6,
    }

    TEST "A crafts like targeting nonexistent post"
    local now = os.time()
    craft(REPO_A6, KEY1, like_file('action 0000000000000000000000000000000000000000', 1000, PUB1, now), now)

    TEST "B rejects like with action not found on sync"
    FAIL {
        cmd = EXE_B .. " chain /err-post sync recv " .. REPO_A6,
        err = "ERROR : chain sync : invalid like : invalid target : action not found",
    }
end

-- sync rejects like from author with insufficient reputation
do
    print("==> sync rejects like with insufficient reputation")

    local REPO_A7 = ROOT_A .. "/chains/err-reps/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add /err-reps init " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain /err-reps post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-reps clone " .. REPO_A7,
    }

    TEST "A crafts like signed by non-pioneer (0 reps)"
    local now = os.time()
    craft(REPO_A7, KEY3, like_file('action ' .. post, 1000, PUB3, now), now)

    TEST "B rejects like with insufficient reps on sync"
    FAIL {
        cmd = EXE_B .. " chain /err-reps sync recv " .. REPO_A7,
        err = "ERROR : chain sync : invalid like : insufficient reputation",
    }
end

-- sync rejects like with too big time difference
do
    print("==> sync rejects like with too big time difference")

    local REPO_A8 = ROOT_A .. "/chains/err-time/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " --now=10000 chains add /err-time init " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " --now=11000 chain /err-time post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-time clone " .. REPO_A8,
    }

    TEST "A crafts like with old timestamp"
    craft(REPO_A8, KEY1, like_file('action ' .. post, 1000, PUB1, 1), 1)

    TEST "B rejects like with old timestamp on sync"
    FAIL {
        cmd = EXE_B .. " --now=11000 chain /err-time sync recv " .. REPO_A8,
        err = "ERROR : chain sync : invalid like : too old",
    }
end

-- sync rejects like with fractional number
do
    print("==> sync rejects like with fractional number")

    local REPO_A9 = ROOT_A .. "/chains/err-frac/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add /err-frac init " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain /err-frac post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-frac clone " .. REPO_A9,
    }

    TEST "A crafts like with fractional number"
    local now = os.time()
    craft(REPO_A9, KEY1, like_file('action ' .. post, "0.5", PUB1, now), now)

    TEST "B rejects like with fractional number on sync"
    -- a fractional n cannot even PARSE as an action now
    FAIL {
        cmd = EXE_B .. " chain /err-frac sync recv " .. REPO_A9,
        err = "ERROR : chain sync : malformed commit : invalid action",
    }
end

-- sync rejects like with zero number
do
    print("==> sync rejects like with zero number")

    local REPO_A10 = ROOT_A .. "/chains/err-zero/"

    TEST "A creates chain + post"
    exec {
        cmd = EXE_A .. " chains add /err-zero init " .. GEN_1,
    }
    local post = exec {
        cmd = EXE_A .. " chain /err-zero post inline 'legit' --sign " .. KEY1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-zero clone " .. REPO_A10,
    }

    TEST "A crafts like with zero number"
    local now = os.time()
    craft(REPO_A10, KEY1, like_file('action ' .. post, 0, PUB1, now), now)

    TEST "B rejects like with zero number on sync"
    FAIL {
        cmd = EXE_B .. " chain /err-zero sync recv " .. REPO_A10,
        err = "ERROR : chain sync : invalid like : invalid number : expects non-zero integer",
    }
end

-- (removed) "lying backs" test: backs are STRUCTURAL now (the
-- commit's parents, aid == cid) -- there is no backs field to lie
-- about, so the whole class is gone by construction (B7 dissolved)

-- sync rejects like with forged signature
do
    print("==> sync rejects forged signature like")

    local REPO_A11 = ROOT_A .. "/chains/err-forge-like/"

    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " --now=1000 chains add /err-forge-like init " .. GEN_1,
    }

    TEST "B clones from A"
    exec {
        cmd = EXE_B .. " chains add /err-forge-like clone " .. REPO_A11,
    }

    TEST "A crafts a like with forged signature"
    exec {
        cmd = EXE_A .. " --now=2000 chain /err-forge-like like 1000 author '" .. PUB1 .. "' --sign " .. KEY1,
    }
    -- Tamper the SIGNED action (the message): flip the n value so
    -- the body still parses but the ssh signature no longer matches
    local raw = exec { trim=false,
        cmd = "git -C " .. REPO_A11 .. " cat-file commit HEAD",
    }
    local forged = raw:gsub('\nlike 1000\n', '\nlike 999\n', 1)
    local tmpf = REPO_A11 .. "forged-commit"
    local fh = io.open(tmpf, "w")
    fh:write(forged)
    fh:close()
    local new_hash = exec {
        cmd = "git -C " .. REPO_A11 .. " hash-object -t commit -w --stdin <" .. tmpf,
    }
    os.remove(tmpf)
    exec {
        cmd = "git -C " .. REPO_A11 .. " update-ref HEAD " .. new_hash,
    }

    TEST "B rejects forged like signature on sync"
    FAIL {
        cmd = EXE_B .. " --now=2000 chain /err-forge-like sync recv " .. REPO_A11,
        err = "ERROR : chain sync : malformed commit : invalid signature",
    }
end

print("<== ALL PASSED")
