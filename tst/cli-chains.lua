#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-chains"

-- ADD
do
    print("==> freechains chains add dir")

    do
        TEST "success"
        local out, code = exec (
            EXE .. " chains add cli-chains dir " .. GEN
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")

        TEST "genesis file"
        local gen = DIR .. "/.freechains/genesis.lua"
        local _, code = exec("diff -q " .. GEN .. "genesis.lua " .. gen)
        assert(code == 0, "exit code: " .. tostring(code))
        local t = dofile(gen)
        assert(type(t) == "table")
        assert(t.version and t.version[1]==1 and t.version[2]==2 and t.version[3]==3)
        assert(t.type == "#")
        assert(t.name == "A forum")

        TEST "alias -> hash"
        local lnk = exec("readlink " .. DIR)
        assert(lnk:match("^%x+/$"), "symlink target: " .. lnk)

        TEST "author/committer = dash"
        local author = exec("git -C " .. DIR .. " log --format=%an HEAD")
        assert(author == "-", "author: " .. author)
        local committer = exec("git -C " .. DIR .. " log --format=%cn HEAD")
        assert(committer == "-", "committer: " .. committer)

        TEST "empty commit message"
        local msg = exec("git -C " .. DIR .. " log --format=%B HEAD")
        assert(msg == "", "message: " .. msg)

        TEST "no parent"
        local parent = exec("git -C " .. DIR .. " log --format=%P HEAD")
        assert(parent == "", "parent: " .. parent)
    end

    do
        TEST "bad genesis file"
        local bad = "/tmp/fc-test-bad-genesis/"
        exec("mkdir -p " .. bad)
        do
            f = io.open(bad .. "genesis.lua", "w")
            f:write('return "not a table"\n')
            f:close()
        end
        local _, code = exec (true,
            EXE .. " chains add x dir " .. bad
        )
        assert(code ~= 0, "should fail")
    end

    do
        TEST "add args fails"
        local _, code = exec (true,
            EXE .. " chains add x args --type '#'"
        )
        assert(code ~= 0, "should fail")
    end

    do
        TEST "add remote fails"
        local _, code = exec (true,
            EXE .. " chains add x remote host hash"
        )
        assert(code ~= 0, "should fail")
    end
end

-- DIR
do
    print("==> freechains chains dir")

    do
        TEST "dir one chain"
        local out, code = exec(
            EXE .. " chains dir"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "cli-chains", "list: " .. out)
    end

    do
        TEST "dir two chains"
        exec (
            EXE .. " chains add other dir " .. GEN
        )
        local out, code = exec(
            EXE .. " chains dir"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "cli-chains\nother\n", "list: " .. out)
    end
end

-- REM
do
    print("==> freechains chains rem")

    do
        TEST "rem success"
        local _, code = exec (
            EXE .. " chains rem cli-chains"
        )
        assert(code == 0, "exit code: " .. tostring(code))

        TEST "dir removed"
        local _, code = exec (true,
            "test -d " .. ROOT .. "/chains/cli-chains"
        )
        assert(code ~= 0, "dir should not exist")

        TEST "symlink removed"
        local _, code = exec (true,
            "test -L " .. ROOT .. "/chains/cli-chains"
        )
        assert(code ~= 0, "symlink should not exist")
    end

    do
        TEST "rem nonexistent fails"
        local _, code = exec (true,
            EXE .. " chains rem nonexistent"
        )
        assert(code ~= 0, "should fail")
    end

    do
        TEST "rem other"
        local _, code = exec (
            EXE .. " chains rem other"
        )
        assert(code == 0, "exit code: " .. tostring(code))
    end

    do
        TEST "dir empty after rem"
        local out, code = exec (
            EXE .. " chains dir"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "", "list should be empty: " .. out)
    end
end

print("<== ALL PASSED")
