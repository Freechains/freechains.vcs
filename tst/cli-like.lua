#!/usr/bin/env lua5.4
require "common"

exec("rm -rf " .. TMP)
exec("mkdir -p " .. ROOT)
os.execute("sleep 1")
exec(ENV_EXE .. " chains add cl dir " .. GEN_1P)
local DIR = ROOT .. "/chains/cl/"

-- Pioneer posts a target block
local TARGET = exec (
    ENV_EXE .. " chain cl post inline 'target post' --sign " .. KEY
)
assert(#TARGET == 40, "target hash: " .. TARGET)

-- LIKE COMMAND
do
    print("==> freechains chain like (+1)")

    do
        TEST "like-success"
        local out, code = exec (
            ENV_EXE .. " chain cl like +1 " .. TARGET .. " --sign " .. KEY2
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
    end

    do
        TEST "like-empty-tree"
        local tree = exec("git -C " .. DIR .. " rev-parse HEAD^{tree}")
        assert(
            tree == "4b825dc642cb6eb9a060e54bf899d69ff964f6d9",
            "tree: " .. tree
        )
    end

    do
        TEST "like-extra-header"
        local raw = exec("git -C " .. DIR .. " cat-file commit HEAD")
        assert(
            raw:match("freechains%-like: %+1 " .. TARGET),
            "missing freechains-like header"
        )
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
        assert(parent == TARGET,
            "parent: " .. parent .. " expected: " .. TARGET)
    end
end

-- DISLIKE (like -1)
do
    print("==> freechains chain like (-1)")

    local TARGET2 = exec (
        ENV_EXE .. " chain cl post inline 'another post' --sign " .. KEY
    )

    do
        TEST "dislike-success"
        local out, code = exec (
            ENV_EXE .. " chain cl like -1 " .. TARGET2 .. " --sign " .. KEY2
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
    end

    do
        TEST "dislike-extra-header"
        local raw = exec("git -C " .. DIR .. " cat-file commit HEAD")
        assert(
            raw:match("freechains%-like: %-1 " .. TARGET2),
            "missing freechains-like header"
        )
    end

    do
        TEST "dislike-with-why"
        local TARGET3 = exec (
            ENV_EXE .. " chain cl post inline 'bad content' --sign " .. KEY
        )
        local out, code = exec (
            ENV_EXE .. " chain cl like -1 " .. TARGET3
            .. " --sign " .. KEY2 .. " --why 'spam content'"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        local raw = exec("git -C " .. DIR .. " cat-file commit HEAD")
        assert(raw:match("spam content"), "reason not recorded")
    end
end

-- ERROR CASES
do
    print("==> Error cases")

    do
        TEST "like-nonexistent"
        local fake = "0000000000000000000000000000000000000000"
        local _, code = exec (
            ENV_EXE .. " chain cl like +1 " .. fake .. " --sign " .. KEY2
        )
        assert(code ~= 0, "should fail")
    end

    do
        TEST "self-like-rejected"
        local self_target = exec (
            ENV_EXE .. " chain cl post inline 'self target' --sign " .. KEY
        )
        local _, code = exec (
            ENV_EXE .. " chain cl like +1 " .. self_target .. " --sign " .. KEY
        )
        assert(code ~= 0, "self-like should fail")
    end

    do
        TEST "self-dislike-works"
        local self_target = exec (
            ENV_EXE .. " chain cl post inline 'self dislike' --sign " .. KEY
        )
        local _, code = exec (
            ENV_EXE .. " chain cl like -1 " .. self_target .. " --sign " .. KEY
        )
        assert(code == 0, "self-dislike should succeed")
    end

    do
        TEST "like-requires-sign"
        local _, code = exec (
            ENV_EXE .. " chain cl like +1 " .. TARGET
        )
        assert(code ~= 0, "like without --sign should fail")
    end
end

print("<== ALL PASSED")
