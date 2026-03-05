#!/usr/bin/env lua5.4

local EXE = "./src/freechains"

local TMP  = "/tmp/freechains/"
local GEN  = TMP .. "/genesis.lua"
local ROOT = TMP .. "/root/"

function exec (cmd)
    --print(cmd)
    local h = io.popen(cmd .. " 2>&1")
    local out = h:read("a"):match("^%s*(.-)%s*$")
    local ok, _, code = h:close()
    return out, (ok and 0 or code)
end

function TEST (name)
    print("  - " .. name .. "... ")
end

-- setup
local f = io.open(GEN, "w")
f:write [[
    return {
        version = {1, 2, 3},
        type    = "#",
        app     = "free form",
    }
]]
f:close()

-- ADD
do
    print("==> freechains chains add lua")

    do
        TEST "success"
        local out, code = exec (
            EXE .. " --root " .. ROOT .. " chains add mychain lua " .. GEN
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")

        local REPO = ROOT .. "/chains/mychain"

        TEST "genesis file"
        local gen = REPO .. "/.genesis.lua"
        local _, code = exec("diff -q " .. GEN .. " " .. gen)
        assert(code == 0, "exit code: " .. tostring(code))
        local t = dofile(gen)
        assert(type(t) == "table")
        assert(t.version and t.version[1]==1 and t.version[2]==2 and t.version[3]==3)
        assert(t.type == "#")
        assert(t.app == "free form")

        TEST "alias -> hash"
        local lnk = exec("readlink " .. REPO)
        assert(lnk:match("^%x+/$"), "symlink target: " .. lnk)

        TEST "author/committer = dash"
        local author = exec("git -C " .. REPO .. " log --format=%an HEAD")
        assert(author == "-", "author: " .. author)
        local committer = exec("git -C " .. REPO .. " log --format=%cn HEAD")
        assert(committer == "-", "committer: " .. committer)

        TEST "empty commit message"
        local msg = exec("git -C " .. REPO .. " log --format=%B HEAD")
        assert(msg == "", "message: " .. msg)

        TEST "no parent"
        local parent = exec("git -C " .. REPO .. " log --format=%P HEAD")
        assert(parent == "", "parent: " .. parent)
    end

    do
        TEST "bad genesis file"
        local bad = "/tmp/fc-test-bad-genesis.lua"
        do
            f = io.open(bad, "w")
            f:write('return "not a table"\n')
            f:close()
        end
        local _, code = exec (
            EXE .. " --root " .. ROOT .. " chains add x lua " .. bad
        )
        assert(code ~= 0, "should fail")
    end

    do
        TEST "add args fails"
        local _, code = exec (
            EXE .. " --root " .. ROOT .. " chains add x args --type '#'"
        )
        assert(code ~= 0, "should fail")
    end

    do
        TEST "add remote fails"
        local _, code = exec (
            EXE .. " --root " .. ROOT .. " chains add x remote host hash"
        )
        assert(code ~= 0, "should fail")
    end
end

-- LIST
do
    print("==> freechains chains list")

    do
        TEST "list one chain"
        local out, code = exec(
            EXE .. " --root " .. ROOT .. " chains list"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "mychain", "list: " .. out)
    end

    do
        TEST "list two chains"
        exec(
            EXE .. " --root " .. ROOT
            .. " chains add other lua " .. GEN
        )
        local out, code = exec(
            EXE .. " --root " .. ROOT .. " chains list"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "mychain\nother", "list: " .. out)
    end
end

-- REM
do
    print("==> freechains chains rem")

    do
        TEST "rem success"
        local _, code = exec (
            EXE .. " --root " .. ROOT .. " chains rem mychain"
        )
        assert(code == 0, "exit code: " .. tostring(code))

        TEST "dir removed"
        local _, code = exec(
            "test -d " .. ROOT .. "/chains/mychain"
        )
        assert(code ~= 0, "dir should not exist")

        TEST "symlink removed"
        local _, code = exec(
            "test -L " .. ROOT .. "/chains/mychain"
        )
        assert(code ~= 0, "symlink should not exist")
    end

    do
        TEST "rem nonexistent fails"
        local _, code = exec (
            EXE .. " --root " .. ROOT .. " chains rem nonexistent"
        )
        assert(code ~= 0, "should fail")
    end

    do
        TEST "rem other"
        local _, code = exec(
            EXE .. " --root " .. ROOT
            .. " chains rem other"
        )
        assert(code == 0, "exit code: " .. tostring(code))
    end

    do
        TEST "list empty after rem"
        local out, code = exec(
            EXE .. " --root " .. ROOT .. " chains list"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "", "list should be empty: " .. out)
    end
end

print("<== ALL PASSED")
