#!/usr/bin/env lua5.4
require "common"

-- setup: create chain
exec(EXE .. " --root " .. ROOT
    .. " chains add mychain lua " .. GEN)

local REPO = ROOT .. "/chains/mychain"

-- POST FILE
do
    print("==> freechains chain post file")

    do
        TEST "post file success"
        local tmp = TMP .. "/hello.txt"
        local f = io.open(tmp, "w")
        f:write("hello world\n")
        f:close()
        local out, code = exec (
            EXE .. " --root " .. ROOT
            .. " chain mychain post file " .. tmp
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")
    end

    do
        TEST "posted file in tree"
        local content = exec("cat " .. REPO .. "/hello.txt")
        assert(content == "hello world",
            "content: " .. content)
    end

    do
        TEST "genesis still in tree"
        local _, code = exec (
            "test -f " .. REPO .. "/.genesis.lua"
        )
        assert(code == 0, ".genesis.lua missing")
    end

    do
        TEST "post same file again, different hash"
        local hash1 = exec (
            "git -C " .. REPO .. " rev-parse HEAD"
        )
        local tmp = TMP .. "/hello.txt"
        local f = io.open(tmp, "w")
        f:write("hello world updated\n")
        f:close()
        local hash2, code = exec (
            EXE .. " --root " .. ROOT
            .. " chain mychain post file " .. tmp
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
            EXE .. " --root " .. ROOT
            .. " chain mychain post file " .. tmp
        )
        local _, code1 = exec (
            "test -f " .. REPO .. "/hello.txt"
        )
        local _, code2 = exec (
            "test -f " .. REPO .. "/second.txt"
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
            EXE .. " --root " .. ROOT
            .. " chain mychain post inline 'Quick note'"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        local h = io.popen(
            "ls " .. REPO .. "/*-*.txt 2>/dev/null"
        )
        local files = h:read("a")
        h:close()
        assert(files ~= "", "auto-named file missing")
    end

    do
        TEST "inline --file creates file"
        local _, code = exec (
            EXE .. " --root " .. ROOT
            .. " chain mychain post inline 'Line 1'"
            .. " --file log.txt"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        local content = exec("cat " .. REPO .. "/log.txt")
        assert(content == "Line 1",
            "content: " .. content)
    end

    do
        TEST "inline --file appends"
        local _, code = exec (
            EXE .. " --root " .. ROOT
            .. " chain mychain post inline 'Line 2'"
            .. " --file log.txt"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        local content = exec("cat " .. REPO .. "/log.txt")
        assert(content == "Line 1\nLine 2",
            "content: " .. content)
    end
end

-- POST errors
do
    print("==> freechains chain post errors")

    do
        TEST "post to nonexistent chain fails"
        local tmp = TMP .. "/hello.txt"
        local _, code = exec (
            EXE .. " --root " .. ROOT
            .. " chain nochain post file " .. tmp
        )
        assert(code ~= 0, "should fail")
    end
end

print("<== ALL PASSED")
