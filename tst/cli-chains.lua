#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/#cli-chains"

-- ADD
do
    print("==> freechains chains add init")

    do
        TEST "success"
        local out, code = exec {
            cmd = EXE .. " chains add '#cli-chains' init file " .. GEN_0,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 41, "hash length: " .. #out)
        assert(out:match("^#%x+$"), "hash is hex")

        TEST "genesis file"
        local gen = DIR .. "/.freechains/genesis.lua"
        local _, code = exec {
            cmd = "diff -q " .. GEN_0 .. " " .. gen,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local t = dofile(gen)
        assert(type(t) == "table")
        assert(t.version and t.version[1]==1 and t.version[2]==2 and t.version[3]==3)
        assert(t.type == "#")
        assert(t.name == "A forum")

        TEST "alias -> hash"
        local lnk = exec {
            cmd = "readlink " .. DIR,
        }
        assert(lnk:match("^#%x+/$"), "symlink target: " .. lnk)

        TEST "author/committer = dash"
        local author = exec {
            cmd = "git -C " .. DIR .. " log --format=%an HEAD",
        }
        assert(author == "-", "author: " .. author)
        local committer = exec {
            cmd = "git -C " .. DIR .. " log --format=%cn HEAD",
        }
        assert(committer == "-", "committer: " .. committer)

        TEST "state trailer"
        local trailer = exec {
            cmd = "git -C " .. DIR .. " log -1 --format='%(trailers:key=Freechains,valueonly)' HEAD",
        }
        trailer = trailer:match("(%S+)") or ""
        assert(trailer == "state", "trailer: " .. trailer)

        TEST "no parent"
        local parent = exec {
            cmd = "git -C " .. DIR .. " log --format=%P HEAD",
        }
        assert(parent == "", "parent: " .. parent)

        TEST "freechains.url points to own repo"
        local url  = exec {
            cmd = "git -C " .. DIR .. " config freechains.url",
        }
        local real = exec {
            cmd = "realpath '" .. url .. "'",
        }
        local want = exec {
            cmd = "realpath " .. DIR,
        }
        assert(real == want, "url mismatch: " .. real .. " vs " .. want)
    end

    do
        TEST "duplicate alias fails"
        FAIL {
            cmd = EXE .. " chains add '#cli-chains' init file " .. GEN_0,
            err = "ERROR : chains add : alias already exists",
        }
    end

    do
        TEST "bad genesis file"
        local bad = "/tmp/fc-test-bad-genesis.lua"
        do
            f = io.open(bad, "w")
            f:write('return "not a table"\n')
            f:close()
        end
        FAIL {
            cmd = EXE .. " chains add '#x' init file " .. bad,
            err = "ERROR : chains add : invalid genesis",
        }
    end

    do
        TEST "genesis file not found"
        FAIL {
            cmd = EXE .. " chains add '#x' init file /nonexistent/genesis.lua",
            err = "ERROR : chains add : invalid genesis",
        }
    end

    do
        TEST "init missing subcommand fails"
        local err = FAIL {
            cmd = EXE .. " chains add '#x' init",
        }
        assert(err and
            err:match("Error: a command is required"), "should fail with TODO: " .. tostring(err))
    end

    do
        TEST "init invalid subcommand fails"
        local err = FAIL {
            cmd = EXE .. " chains add '#x' init bogus",
        }
        assert(err and
            err:match("Error: unknown command 'bogus'"), "should fail with TODO: " .. tostring(err))
    end

    do
        TEST "git init failed"
        FAIL {
            cmd = ENV .. " ../src/freechains.lua --root /dev/null chains add '#x' init file " .. GEN_0,
            err = "ERROR : chains add : init failed",
        }
    end

    do
        TEST "git clone failed"
        FAIL {
            cmd = EXE .. " chains add '#x' clone /nonexistent/repo",
            err = "ERROR : chains add : clone failed",
        }
    end

    do
        TEST "clone existing chain fails"
        FAIL {
            cmd = EXE .. " chains add '#clone-dup' clone " .. ROOT .. "/chains/#cli-chains",
            err = "ERROR : chains add : clone failed",
        }
    end

    do
        TEST "add args fails"
        FAIL {
            cmd = EXE .. " chains add '#x' args --type '#'",
        }
    end

    do
        TEST "add remote fails"
        FAIL {
            cmd = EXE .. " chains add '#x' remote host hash",
        }
    end
end

-- DIR
do
    print("==> freechains chains dir")

    do
        TEST "dir one chain"
        local out, code = exec {
            cmd = EXE .. " chains dir",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "#cli-chains", "list: " .. out)
    end

    do
        TEST "dir two chains"
        exec {
            cmd = EXE .. " chains add '#other' init file " .. GEN_0,
        }
        local out, code = exec {
            cmd = EXE .. " chains dir",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "#cli-chains\n#other\n", "list: " .. out)
    end
end

-- REM
do
    print("==> freechains chains rem")

    do
        TEST "rem success"
        local _, code = exec {
            cmd = EXE .. " chains rem '#cli-chains'",
        }
        assert(code == 0, "exit code: " .. tostring(code))

        TEST "dir removed"
        FAIL {
            cmd = "test -d " .. ROOT .. "/chains/#cli-chains",
        }

        TEST "symlink removed"
        FAIL {
            cmd = "test -L " .. ROOT .. "/chains/#cli-chains",
        }
    end

    do
        TEST "rem nonexistent fails"
        FAIL {
            cmd = EXE .. " chains rem '#nonexistent'",
            err = "ERROR : chains rem : invalid chain",
        }
    end

    do
        TEST "rem other"
        local _, code = exec {
            cmd = EXE .. " chains rem '#other'",
        }
        assert(code == 0, "exit code: " .. tostring(code))
    end

    do
        TEST "dir empty after rem"
        local out, code = exec {
            cmd = EXE .. " chains dir",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "", "list should be empty: " .. out)
    end
end

-- ADD INIT INLINE
do
    print("==> freechains chains add init inline")

    do
        TEST "inline creates chain"
        local out, code = exec {
            cmd = EXE .. " chains add '#inl-chat' init inline --sign " .. KEY1,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 41, "hash length: " .. #out)
        assert(out:match("^#%x+$"), "hash is hex")

        TEST "inline genesis"
        local gen = ROOT .. "/chains/#inl-chat/.freechains/genesis.lua"
        local t = dofile(gen)
        assert(t.type == "#", "type: " .. tostring(t.type))
        assert(t.name == "#inl-chat", "name: " .. tostring(t.name))
        assert (
            t.pioneers and t.pioneers[1] == PUB1
            , "pioneers[1]: " .. tostring(t.pioneers and t.pioneers[1])
        )
        assert (
            t.version and t.version[1]==0 and t.version[2]==20 and t.version[3]==0
            , "version mismatch"
        )
    end

    do
        TEST "inline uses default --sign at $HOME/.ssh/id_ed25519"
        local out, code = exec {
            cmd = "HOME=" .. SSH .. "home " .. EXE .. " chains add '#inl-default' init inline --sign",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 41, "hash length: " .. #out)

        local gen = ROOT .. "/chains/#inl-default/.freechains/genesis.lua"
        local t = dofile(gen)
        assert (
            t.pioneers and t.pioneers[1] == PUB1
            , "pioneers[1]: " .. tostring(t.pioneers and t.pioneers[1])
        )
    end

    do
        TEST "inline with bad --sign fails"
        FAIL {
            cmd = EXE .. " chains add '#inl-badkey' init inline --sign /nonexistent/key",
            err = "ERROR : chains add : invalid sign key",
        }
    end
end

print("<== ALL PASSED")
