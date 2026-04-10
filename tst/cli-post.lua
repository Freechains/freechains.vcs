#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-post/"

exec(ENV_EXE .. " chains add cli-post init " .. GEN_1)

-- POST FILE
do
    print("==> freechains chain post file")

    do
        TEST "post file success"
        local out, code = exec (
            ENV_EXE .. " chain cli-post post file hello.txt --sign " .. KEY1
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")
    end

    do
        TEST "posted file in tree"
        local v = io.open(DIR .. "/hello.txt"):read'*a'
        assert(v=="Hello World!\n", "content: " .. v)
    end

    do
        TEST "genesis still in tree"
        local _, code = exec (
            "test -f " .. DIR .. "/.freechains/genesis.lua"
        )
        assert(code == 0, ".freechains/genesis.lua missing")
    end

    do
        TEST "post same file again, different hash"
        local hash1 = exec (
            "git -C " .. DIR .. " rev-parse HEAD"
        )
        local tmp = TMP .. "/hello.txt"
        local f = io.open(tmp, "w")
        f:write("hello world updated\n")
        f:close()
        local hash2, code = exec (
            ENV_EXE .. " chain cli-post post file " .. tmp .. " --sign " .. KEY1
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(hash1 ~= hash2, "hashes should differ")
    end

    do
        TEST "post second file, both in tree"
        local tmp = TMP .. "/second.txt"
        local f = io.open(tmp, "w")
        f:write("second file\n")
        f:close()
        exec (
            ENV_EXE .. " chain cli-post post file " .. tmp .. " --sign " .. KEY1
        )
        local _, code1 = exec (
            "test -f " .. DIR .. "/hello.txt"
        )
        local _, code2 = exec (
            "test -f " .. DIR .. "/second.txt"
        )
        assert(code1 == 0, "hello.txt missing")
        assert(code2 == 0, "second.txt missing")
    end
end

-- POST INLINE
do
    print("==> freechains chain post inline")

    do
        TEST "inline auto-name"
        local out, code = exec (
            ENV_EXE .. " chain cli-post post inline 'Quick note' --sign " .. KEY1
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        local files = exec("ls " .. DIR .. "/*-*.txt")
        assert(files ~= "", "auto-named file missing")

        do
            TEST "inline auto-name - filename format"
            local f1 = files:match("[^/]+$")
            assert(f1:match("^post%-%d+%-%d+%.txt$"), "bad format: " .. f1)
        end
    end

    do
        TEST "inline --file creates file"
        local _, code = exec (
            ENV_EXE .. " chain cli-post post inline 'Line 1'"
            .. " --file log.txt --sign " .. KEY1
        )
        assert(code == 0, "exit code: " .. tostring(code))
        local content = exec("cat " .. DIR .. "/log.txt")
        assert(content == "Line 1", "content: " .. content)
    end

    do
        TEST "inline --file appends"
        local _, code = exec (
            ENV_EXE .. " chain cli-post post inline 'Line 2'"
            .. " --file log.txt --sign " .. KEY1
        )
        assert(code == 0, "exit code: " .. tostring(code))
        local content = exec("cat " .. DIR .. "/log.txt")
        assert(content == "Line 1\nLine 2\n", "content: " .. content)
    end
end

-- POST --why
do
    print("==> freechains chain post --why")

    do
        TEST "inline --why sets commit message"
        exec (
            ENV_EXE .. " chain cli-post post inline 'some text' --sign " .. KEY1
            .. " --why 'reason for posting'"
        )
        local msg = exec("git -C " .. DIR .. " log -1 --format=%s HEAD~1")
        assert(msg == "reason for posting", "commit message: " .. msg)
    end

    do
        TEST "file --why sets commit message"
        local tmp = TMP .. "/why-test.txt"
        local f = io.open(tmp, "w")
        f:write("why test content\n")
        f:close()
        exec (
            ENV_EXE .. " chain cli-post post file " .. tmp .. " --sign " .. KEY1
            .. " --why 'file reason'"
        )
        local msg = exec("git -C " .. DIR .. " log -1 --format=%s HEAD~1")
        assert(msg == "file reason", "commit message: " .. msg)
    end

    do
        TEST "post without --why has empty message"
        exec(ENV_EXE .. " chain cli-post post inline 'no reason' --sign " .. KEY1)
        local msg = exec("git -C " .. DIR .. " log -1 --format=%s HEAD~1")
        assert(msg == "(empty message)", "commit message should be empty: " .. msg)
    end
end

-- POST errors
do
    print("==> freechains chain post errors")

    do
        TEST "post to nonexistent chain fails"
        local tmp = TMP .. "/hello.txt"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain nochain post file " .. tmp .. " --sign " .. KEY1
        )
        assert (
            Q~=0 and err=="ERROR : chain nochain : not found"
            , "should fail: " .. tostring(err)
        )
    end
end

print("<== ALL PASSED")
