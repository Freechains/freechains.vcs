#!/usr/bin/env lua5.4
require "common"

local ROOT_A = ROOT
local ROOT_B = TMP .. "/root-B/"
local EXE_A  = ENV_EXE
local EXE_B  = ENV .. " ../src/freechains --root " .. ROOT_B

local REPO_A = ROOT_A .. "/chains/repl-local/"

-- SETUP: host B root
exec("mkdir -p " .. ROOT_B .. "/chains")

-- HOST A: create chain + signed post
local CHAIN_HASH

do
    print("==> Host A: create chain + signed post")

    os.execute("sleep 1")
    do
        TEST "chain created"
        CHAIN_HASH = exec (
            EXE_A .. " chains add repl-local lua " .. GEN
        )
        assert(#CHAIN_HASH == 40, "hash: " .. CHAIN_HASH)
        assert(CHAIN_HASH:match("^%x+$"), "not hex")
    end

    do
        TEST "signed post on A"
        local out = exec(
            EXE_A
            .. " chain repl-local post inline 'post from A'"
            .. " --sign " .. KEY
        )
        assert(#out == 40, "hash: " .. out)
        assert(out:match("^%x+$"), "not hex")
    end
end

-- HOST B: clone chain from A + signed post
local REPO_B = ROOT_B .. "/chains/" .. CHAIN_HASH .. "/"

do
    print("==> Host B: clone chain + signed post")

    do
        TEST "clone succeeds"
        exec("git clone " .. REPO_A .. " " .. REPO_B)
        exec(
            "ln -s " .. CHAIN_HASH .. "/ "
            .. ROOT_B .. "/chains/repl-local"
        )
    end

    do
        TEST "B has same genesis"
        local gen_a = exec(
            "git -C " .. REPO_A
            .. " rev-list --max-parents=0 HEAD"
        )
        local gen_b = exec(
            "git -C " .. REPO_B
            .. " rev-list --max-parents=0 HEAD"
        )
        assert(gen_a == gen_b, "genesis mismatch")
    end

    do
        TEST "B has 2 commits (genesis + A's post)"
        local count = exec(
            "git -C " .. REPO_B
            .. " rev-list --count HEAD"
        )
        assert(count == "2", "count: " .. count)
    end

    do
        TEST "signed post on B"
        local out = exec(
            EXE_B
            .. " chain repl-local post inline 'post from B'"
            .. " --sign " .. KEY
        )
        assert(#out == 40, "hash: " .. out)
        assert(out:match("^%x+$"), "not hex")
    end

    do
        TEST "B has 3 commits (genesis + A + B)"
        local count = exec(
            "git -C " .. REPO_B
            .. " rev-list --count HEAD"
        )
        assert(count == "3", "count: " .. count)
    end
end

-- HOST A: pull from B
do
    print("==> Host A: pull from B")

    do
        TEST "add remote + pull"
        exec(
            "git -C " .. REPO_A
            .. " remote add hostB " .. REPO_B
        )
        local branch = exec(
            "git -C " .. REPO_A
            .. " rev-parse --abbrev-ref HEAD"
        )
        exec(
            "git -C " .. REPO_A
            .. " -c user.name='-' -c user.email='-'"
            .. " pull --no-edit hostB " .. branch
        )
    end

    do
        TEST "A has 3 commits (genesis + A + B, fast-forward)"
        local count = exec(
            "git -C " .. REPO_A
            .. " rev-list --count HEAD"
        )
        assert(count == "3", "count: " .. count)
    end

    do
        TEST "both post files present in A"
        local found_a, found_b = false, false
        local h = io.popen("cat " .. REPO_A .. "/*.txt")
        local all = h:read("a")
        h:close()
        found_a = all:match("post from A") ~= nil
        found_b = all:match("post from B") ~= nil
        assert(found_a, "A's post content missing")
        assert(found_b, "B's post content missing")
    end
end

-- VERIFY SIGNATURES
do
    print("==> Verify signatures")

    do
        TEST "2 signed commits verified"
        local h = io.popen(
            "git -C " .. REPO_A
            .. " rev-list --all 2>/dev/null"
        )
        local log = h:read("a")
        h:close()
        local signed = 0
        for hash in log:gmatch("[%x]+") do
            if #hash == 40 then
                local raw = exec(
                    "git -C " .. REPO_A
                    .. " cat-file commit " .. hash
                )
                if raw:match("gpgsig") then
                    local _, code = exec(
                        ENV .. " git -C " .. REPO_A
                        .. " verify-commit "
                        .. hash, true
                    )
                    assert(
                        code == 0,
                        "verify failed: " .. hash
                    )
                    signed = signed + 1
                end
            end
        end
        assert(
            signed == 2,
            "expected 2 signed, got: " .. signed
        )
    end
end

-- TEARDOWN
exec("rm -rf " .. GPG)

print("<== ALL PASSED")
