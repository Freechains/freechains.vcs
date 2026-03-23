#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-chains"

-- ADD
do
    print("==> freechains chains add config")

    do
        TEST "success"
        local out, code = exec (
            EXE .. " chains add cli-chains config " .. GEN_0
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")

        TEST "genesis file"
        local gen = DIR .. "/.freechains/genesis.lua"
        local _, code = exec("diff -q " .. GEN_0 .. " " .. gen)
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

        TEST "state trailer"
        local trailer = exec (
            "git -C " .. DIR .. " log -1 --format='%(trailers:key=Freechains,valueonly)' HEAD"
        )
        trailer = trailer:match("(%S+)") or ""
        assert(trailer == "state", "trailer: " .. trailer)

        TEST "no parent"
        local parent = exec("git -C " .. DIR .. " log --format=%P HEAD")
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
        local _, Q, err = exec (true,
            EXE .. " chains add x config " .. bad
        )
        assert (
            Q~=0 and err=="ERROR : chains add : file must return a table"
            , "should fail: " .. tostring(err)
        )
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
            EXE .. " chains add other config " .. GEN_0
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
        local _, Q, err = exec (true,
            EXE .. " chains rem nonexistent"
        )
        assert (
            Q~=0 and err:match("ERROR : chains rem : not found: nonexistent")
            , "should fail: " .. tostring(err)
        )
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
