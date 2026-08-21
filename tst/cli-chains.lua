#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/#cli-chains"

-- ADD
do
    print("==> freechains chains add init")

    do
        TEST "success"
        local out, code = exec {
            cmd = EXE .. " chains add '#cli-chains' init " .. GEN_0,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 41, "hash length: " .. #out)
        assert(out:match("^#%x+$"), "hash is hex")

        TEST "genesis file"
        -- always generated: version and pioneers, nothing else
        local t = GENESIS(DIR)
        assert(type(t) == "table")
        assert (
            t.version and t.version[1]==0 and t.version[2]==20 and t.version[3]==0
            , "version mismatch"
        )
        assert(t.pioneers and #t.pioneers == 0, "no pioneers")
        assert(t.type == nil and t.name == nil, "no dead fields")

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

        TEST "no trailer"
        local trailer = exec {
            cmd = "git -C " .. DIR .. " log -1 --format='%(trailers:key=Freechains,valueonly)' HEAD",
        }
        trailer = trailer:match("(%S+)") or ""
        assert(trailer == "", "trailer: " .. trailer)

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
            cmd = EXE .. " chains add '#cli-chains' init " .. GEN_0,
            err = "ERROR : chains add : alias already exists",
        }
    end

    do
        TEST "pioneer file is not a key"
        local bad = "/tmp/fc-test-bad-key"
        do
            local f = io.open(bad, "w")
            f:write("not a key\n")
            f:close()
            exec { cmd = "chmod 600 " .. bad }
        end
        FAIL {
            cmd = EXE .. " chains add '#x' init --pioneer=" .. bad,
            err = "ERROR : chains add : invalid pioneer : " .. bad,
        }
    end

    do
        TEST "pioneer string is truncated"
        -- starts with `ssh-`, so never looked up as a file
        FAIL {
            cmd = EXE .. " chains add '#x' init --pioneer='ssh-ed25519'",
            err = "ERROR : chains add : invalid pioneer : ssh-ed25519",
        }
    end

    do
        TEST "init takes no subcommand"
        local err = FAIL {
            cmd = EXE .. " chains add '#x' init bogus",
        }
        assert(err and
            err:match("Error: too many arguments"), "should fail with TODO: " .. tostring(err))
    end

    do
        TEST "git init failed"
        -- the error carries git's own detail (>>> ... <<<)
        local err = FAIL {
            cmd = ENV .. " ../src/freechains.lua --root /dev/null chains add '#x' init " .. GEN_0,
        }
        err = err:gsub("tmp%-%d+", "tmp-N")     -- random suffix
        assert(err == [[
ERROR : chains add : git init failed
>>>
fatal: cannot mkdir /dev/null/chains//tmp-N/: File exists
<<<
]])
    end

    do
        TEST "git clone failed"
        -- the error carries git's own detail (>>> ... <<<)
        local err = FAIL {
            cmd = EXE .. " chains add '#x' clone /nonexistent/repo",
        }
        assert(err == [[
ERROR : chains add : clone failed
>>>
fatal: '/nonexistent/repo/#x' does not appear to be a git repository
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
<<<
]])
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
            cmd = EXE .. " chains add '#other' init " .. GEN_0,
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

-- ADD INIT --pioneer
do
    print("==> freechains chains add init --pioneer")

    do
        TEST "pioneer key file creates chain"
        local out, code = exec {
            cmd = EXE .. " chains add '#inl-chat' init --pioneer=" .. KEY1,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 41, "hash length: " .. #out)
        assert(out:match("^#%x+$"), "hash is hex")

        TEST "pioneer in genesis"
        local t = GENESIS(ROOT .. "/chains/#inl-chat")
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
        TEST "bare --pioneer is $HOME/.ssh/id_ed25519"
        local out, code = exec {
            cmd = "HOME=" .. SSH .. "home " .. EXE .. " chains add '#inl-default' init --pioneer",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 41, "hash length: " .. #out)

        local t = GENESIS(ROOT .. "/chains/#inl-default")
        assert (
            t.pioneers and t.pioneers[1] == PUB1
            , "pioneers[1]: " .. tostring(t.pioneers and t.pioneers[1])
        )
    end

    do
        TEST "pioneer pub file and key string agree with pvt file"
        exec {
            cmd = EXE .. " chains add '#inl-pub' init --pioneer=" .. KEY1 .. ".pub",
        }
        local t1 = dofile(ROOT .. "/chains/#inl-pub/genesis.lua")
        assert(t1.pioneers[1] == PUB1, "pub-file form")
        exec {
            cmd = EXE .. " chains add '#inl-str' init --pioneer='" .. PUB1 .. "'",
        }
        local t2 = dofile(ROOT .. "/chains/#inl-str/genesis.lua")
        assert(t2.pioneers[1] == PUB1, "string form")
    end

    do
        TEST "pioneer file not found"
        FAIL {
            cmd = EXE .. " chains add '#inl-badkey' init --pioneer=/nonexistent/key",
            err = "ERROR : chains add : invalid pioneer : /nonexistent/key",
        }
    end
end

-- PIONEER LIMIT
do
    print("==> Pioneer limit")

    -- n distinct fake keys, one --pioneer each
    local function PIOS (n)
        local t = {}
        for i = 1, n do
            local body = string.format("%043d", i)
            t[#t+1] = "--pioneer='ssh-ed25519 " .. body .. "'"
        end
        return table.concat(t, " ")
    end

    do
        TEST "too many pioneers rejects"
        -- 101 keys: 50000/101 = 495, below the 500 post cost
        FAIL {
            cmd = ENV_EXE .. " chains add '#many' init " .. PIOS(101),
            err = "ERROR : chains add : too many pioneers",
        }
    end

    do
        TEST "the limit itself is accepted"
        local out, code = exec {
            cmd = ENV_EXE .. " chains add '#limit' init " .. PIOS(100),
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out:match("^#%x+$"), "chain id: " .. out)
    end
end

print("<== ALL PASSED")
