#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/cli-get/"
local UNKNOWN = "0000000000000000000000000000000000000000"

exec(ENV_EXE .. " chains add cli-get init file " .. GEN_2)
local POST = exec (
    ENV_EXE .. " chain cli-get post inline 'hello world' --sign " .. KEY1
)
local LIKE = exec (
    ENV_EXE .. " chain cli-get like 1 post " .. POST .. " --sign " .. KEY2
)
local STATE   = exec("git -C " .. DIR .. " rev-parse HEAD")
local GENESIS = exec("git -C " .. DIR .. " rev-list --max-parents=0 HEAD")

-- GET PAYLOAD
do
    print("==> freechains chain get payload")

    do
        TEST "payload of post"
        local out, code = exec (
            ENV_EXE .. " chain cli-get get payload " .. POST
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "hello world", "content: " .. out)
    end

    do
        TEST "payload of like"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-get get payload " .. LIKE
        )
        assert (
            Q ~= 0 and err == "ERROR : chain get : unknown post"
            , "should fail: " .. tostring(err)
        )
    end

    do
        TEST "payload of state"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-get get payload " .. STATE
        )
        assert (
            Q ~= 0 and err == "ERROR : chain get : unknown post"
            , "should fail: " .. tostring(err)
        )
    end

    do
        TEST "payload of genesis"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-get get payload " .. GENESIS
        )
        assert (
            Q ~= 0 and err == "ERROR : chain get : unknown post"
            , "should fail: " .. tostring(err)
        )
    end

    do
        TEST "payload of unknown"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-get get payload " .. UNKNOWN
        )
        assert (
            Q ~= 0 and err == "ERROR : chain get : unknown post"
            , "should fail: " .. tostring(err)
        )
    end
end

-- GET BLOCK (deferred — asserts TODO error or unknown post)
do
    print("==> freechains chain get block")

    do
        TEST "block of post"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-get get block " .. POST
        )
        assert (
            Q ~= 0 and err == "ERROR : chain get : TODO block"
            , "should fail: " .. tostring(err)
        )
    end

    do
        TEST "block of like"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-get get block " .. LIKE
        )
        assert (
            Q ~= 0 and err == "ERROR : chain get : TODO block"
            , "should fail: " .. tostring(err)
        )
    end

    do
        TEST "block of state"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-get get block " .. STATE
        )
        assert (
            Q ~= 0 and err == "ERROR : chain get : unknown post"
            , "should fail: " .. tostring(err)
        )
    end

    do
        TEST "block of genesis"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-get get block " .. GENESIS
        )
        assert (
            Q ~= 0 and err == "ERROR : chain get : unknown post"
            , "should fail: " .. tostring(err)
        )
    end

    do
        TEST "block of unknown"
        local _, Q, err = exec (true,
            ENV_EXE .. " chain cli-get get block " .. UNKNOWN
        )
        assert (
            Q ~= 0 and err == "ERROR : chain get : unknown post"
            , "should fail: " .. tostring(err)
        )
    end
end

print("<== ALL PASSED")
