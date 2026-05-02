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

-- GET BLOCK
do
    print("==> freechains chain get block")

    do
        TEST "block of post"
        local out, code = exec (
            ENV_EXE .. " chain cli-get get block " .. POST
        )
        assert(code == 0, "exit code: " .. tostring(code))
        local T = load(out, "block", "t", {})()
        assert(T.hash == POST, "hash: " .. tostring(T.hash))
        assert(math.type(T.time) == "integer", "time: " .. tostring(T.time))
        assert(T.post.hash:match("^%x+$"), "pay.hash: " .. tostring(T.post.hash))
        assert(T.like == false, "like: " .. tostring(T.like))
        assert(type(T.sign) == "string", "sign type: " .. type(T.sign))
        assert(T.sign:match("^ssh%-ed25519 "), "sign: " .. tostring(T.sign))
        assert(type(T.backs) == "table", "backs type: " .. type(T.backs))
        assert(#T.backs == 1, "backs len: " .. #T.backs)
    end

    do
        TEST "block of like"
        local out, code = exec (
            ENV_EXE .. " chain cli-get get block " .. LIKE
        )
        assert(code == 0, "exit code: " .. tostring(code))
        local T = load(out, "block", "t", {})()
        assert(T.hash == LIKE, "hash: " .. tostring(T.hash))
        assert(type(T.like) == "table", "like type: " .. type(T.like))
        assert(T.like.target == "post", "like.target: " .. tostring(T.like.target))
        assert(T.like.id == POST, "like.id: " .. tostring(T.like.id))
        assert(math.type(T.like.n) == "integer", "like.n: " .. tostring(T.like.n))
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
