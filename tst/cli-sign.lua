#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-sign/"

exec(ENV_EXE .. " chains add cli-sign config " .. GEN_1)

-- SIGNED POST
do
    print("==> freechains chain post --sign")

    do
        TEST "signed post succeeds"
        local out, code = exec (
            ENV_EXE .. " chain cli-sign post file hello.txt --sign " .. KEY
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")
    end

    do
        TEST "git verify-commit passes"
        local out, code = exec (
            ENV .. " git -C " .. DIR .. " verify-commit HEAD~1"
        )
        assert(code == 0, "verify-commit failed")
        assert(out:match('Good signature from "test <test@freechains>"'))
    end

    do
        TEST "gpgsig header present"
        local out = exec (
            "git -C " .. DIR .. " cat-file commit HEAD~1"
        )
        assert(out:match("gpgsig"), "gpgsig header missing")
    end
end

-- UNSIGNED POST (--beg)
do
    print("==> freechains chain post --beg")

    do
        TEST "beg post succeeds"
        local out, code = exec (
            ENV_EXE .. " chain cli-sign post inline unsigned --beg"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        local BEG = out

        TEST "beg commit has no gpgsig"
        local out = exec (
            "git -C " .. DIR .. " cat-file commit " .. BEG
        )
        assert(not out:match("gpgsig"), "gpgsig should be absent")
    end
end

-- ERROR: no --sign and no --beg
do
    print("==> freechains chain post errors")

    do
        TEST "post without --sign or --beg fails"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-sign post inline 'no auth'"
        )
        assert (
            Q~=0 and err=="ERROR : chain post : requires --sign or --beg"
            , "should fail: " .. tostring(err)
        )
    end
end

-- ERROR: post with invalid GPG key
do
    print("==> freechains chain post --sign bad key")

    do
        TEST "post with invalid GPG key fails"
        local _,Q,err = exec (true,
            ENV_EXE .. " chain cli-sign post inline 'bad key' --sign bad-key"
        )
        assert (
            Q~=0 and err=="ERROR : chain post : invalid sign key"
            , "should fail: " .. tostring(err)
        )
    end
end

print("<== ALL PASSED")
