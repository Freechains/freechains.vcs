#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-chains"

-- ADD
do
    print("==> freechains chains add init")

    do
        TEST "success"
        local out, code = exec (
            EXE .. " chains add cli-chains init " .. GEN_0
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
        TEST "duplicate alias fails"
        local _,Q,err = exec(true, EXE .. " chains add cli-chains init " .. GEN_0)
        assert(Q~=0 and err=="ERROR : chains add : alias already exists", "should fail: " .. tostring(err))
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
            EXE .. " chains add x init " .. bad
        )
        assert (
            Q~=0 and err=="ERROR : chains add : invalid genesis"
            , "should fail: " .. tostring(err)
        )
    end

    do
        TEST "genesis file not found"
        local _,Q,err = exec(true, EXE .. " chains add x init /nonexistent/genesis.lua")
        assert(Q~=0 and err=="ERROR : chains add : invalid genesis")
    end

    do
        TEST "git init failed"
        local _,Q,err = exec(true, ENV .. " ../src/freechains.lua --root /dev/null chains add x init " .. GEN_0)
        assert(Q~=0 and err=="ERROR : chains add : init failed", "should fail: " .. tostring(err))
    end

    do
        TEST "git clone failed"
        local _,Q,err = exec(true, EXE .. " chains add x clone /nonexistent/repo")
        assert(Q~=0 and err=="ERROR : chains add : clone failed")
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
            EXE .. " chains add other init " .. GEN_0
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
            Q~=0 and err=="ERROR : chains rem : invalid chain"
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
