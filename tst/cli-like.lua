#!/usr/bin/env lua5.4

require "tests"

exec(ENV_EXE .. " chains add cli-like dir " .. GEN_1P)
local DIR = ROOT .. "/chains/cli-like/"

-- Pioneer posts a target block
local POST

do
    POST = exec (
        ENV_EXE .. " chain cli-like post inline 'target post' --sign " .. KEY
    )
    assert(#POST == 40, "target hash: " .. POST)

    print("==> freechains: post trailer")
    do
        TEST "post-has-trailer"
        local raw = exec("git -C " .. DIR .. " cat-file commit HEAD")
        assert(raw:match("freechains: post"), "missing freechains: post trailer")
    end
end

-- LIKE COMMAND (+)
do
    print("==> freechains chain like (+1)")

    do
        TEST "like-success"
        local out, code = exec (
            ENV_EXE .. " chain cli-like like +1 post " .. POST .. " --sign " .. KEY2
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
    end

    do
        TEST "like-has-trailer"
        local raw = exec("git -C " .. DIR .. " cat-file commit HEAD")
        assert(raw:match("freechains: like"), "missing freechains: like trailer")
    end

    do
        TEST "like-payload-file"
        local files = exec("ls " .. DIR .. "/*-*.lua 2>/dev/null")
        assert(files ~= "", "like payload file missing")
        local path = files:match("[^\n]+")
        local tbl = dofile(path)
        assert(tbl.target == "post", "target: " .. tostring(tbl.target))
print(POST)
        assert(tbl.id == POST, "id: " .. tostring(tbl.id))
        assert(tbl.number == 1, "number: " .. tostring(tbl.number))
    end

    do
        TEST "like-is-signed"
        local _, code = exec (
            ENV .. " git -C " .. DIR .. " verify-commit HEAD", true
        )
        assert(code == 0, "verify-commit failed")
    end

    do
        TEST "like-parent"
        local parent = exec("git -C " .. DIR .. " rev-parse HEAD~1")
        assert(parent == POST,
            "parent: " .. parent .. " expected: " .. POST)
    end
end

-- DISLIKE (like -1)
do
    print("==> freechains chain like (-1)")

    local TARGET2 = exec (
        ENV_EXE .. " chain cli-like post inline 'another post' --sign " .. KEY
    )

    do
        TEST "dislike-success"
        local out, code = exec (
            ENV_EXE .. " chain cli-like like -1 post " .. TARGET2 .. " --sign " .. KEY2
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
    end

    do
        TEST "dislike-payload"
        local raw = exec("git -C " .. DIR .. " cat-file commit HEAD")
        assert(raw:match("freechains: like"), "missing freechains: like trailer")
    end

    do
        TEST "dislike-with-why"
        local TARGET3 = exec (
            ENV_EXE .. " chain cli-like post inline 'bad content' --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cli-like like -1 post " .. TARGET3
            .. " --sign " .. KEY2 .. " --why 'spam content'"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        local msg = exec("git -C " .. DIR .. " log -1 --format=%s")
        assert(msg:match("spam content"), "reason not recorded")
    end
end

-- LIKE AUTHOR
do
    print("==> freechains chain like author")

    do
        TEST "like-author-success"
        local out, code = exec (
            ENV_EXE .. " chain cli-like like +1 author " .. KEY2 .. " --sign " .. KEY
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
    end
end

-- ERROR CASES
do
    print("==> Error cases")

    do
        TEST "like-nonexistent-post"
        local fake = "0000000000000000000000000000000000000000"
        local _, code = exec (
            ENV_EXE .. " chain cli-like like +1 post " .. fake .. " --sign " .. KEY2
        )
        assert(code ~= 0, "should fail")
    end

    do
        TEST "self-like-allowed"
        local self_target = exec (
            ENV_EXE .. " chain cli-like post inline 'self target' --sign " .. KEY
        )
        local _, code = exec (
            ENV_EXE .. " chain cli-like like +1 post " .. self_target .. " --sign " .. KEY
        )
        assert(code == 0, "self-like should succeed")
    end

    do
        TEST "self-dislike-allowed"
        local self_target = exec (
            ENV_EXE .. " chain cli-like post inline 'self dislike' --sign " .. KEY
        )
        local _, code = exec (
            ENV_EXE .. " chain cli-like like -1 post " .. self_target .. " --sign " .. KEY
        )
        assert(code == 0, "self-dislike should succeed")
    end

    do
        TEST "like-requires-sign"
        local _, code = exec (
            ENV_EXE .. " chain cli-like like +1 post " .. POST
        )
        assert(code ~= 0, "like without --sign should fail")
    end

    do
        TEST "like-bad-target-type"
        local _, code = exec (
            ENV_EXE .. " chain cli-like like +1 foo " .. POST .. " --sign " .. KEY
        )
        assert(code ~= 0, "bad target type should fail")
    end
end

print("<== ALL PASSED")
