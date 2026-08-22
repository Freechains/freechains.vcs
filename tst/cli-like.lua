#!/usr/bin/env lua5.4

require "tests"
local ssh = require "freechains.chain.ssh"

exec {
    cmd = ENV_EXE .. " chains add '#cli-like' init " .. GEN_2,
}
local DIR = ROOT .. "/chains/#cli-like/"

-- Pioneer posts a target block
local POST

do
    print("==> freechains post")
    POST = exec {
        cmd = ENV_EXE .. " chain '#cli-like' post inline 'target post' --sign " .. KEY1,
    }
    assert(#POST == 40, "target hash: " .. POST)

    print("==> freechains: post action")
    do
        TEST "post-is-action"
        local out = exec {
            cmd = ENV_EXE .. " chain '#cli-like' get metadata " .. POST,
        }
        local T = load(out, "metadata", "t", {})()
        assert(T.action == "post", "action: " .. tostring(T.action))
    end
end

-- LIKE COMMAND (+)
do
    print("==> freechains chain like (+1)")

    local LIKE
    do
        TEST "like-success"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 action " .. POST .. " --sign " .. KEY2,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
        LIKE = out
    end

    do
        TEST "like-triggers-discount-refund"
        local k1 = exec {
            cmd = ENV_EXE .. " chain '#cli-like' reps author '" .. PUB1 .. "'",
        }
        -- KEY1: 25000 - 500 (post) + 500 (discount refund) + 450 (self-back) = 25450
        assert(k1 == "25450", "KEY1 reps after like: " .. k1)
    end

    do
        TEST "like-is-action"
        local out = exec {
            cmd = ENV_EXE .. " chain '#cli-like' get metadata " .. LIKE,
        }
        local T = load(out, "metadata", "t", {})()
        assert(T.action == "like", "action: " .. tostring(T.action))
    end

    do
        TEST "like-commit-is-the-action (message, empty tree)"
        local msg = exec { trim=false,
            cmd = "git -C " .. DIR .. " log -1 --format=%B " .. LIKE,
        }
        -- positional: `like <n>` then the target line
        assert(msg:match("^like 1000\naction %x+\n"),
            "message is the like: " .. msg)
        local files = exec { trim=false,
            cmd = "git -C " .. DIR .. " ls-tree --name-only " .. LIKE,
        }
        assert(files == "", "tree must be empty: " .. files)
    end

    do
        TEST "like accepts a SHORT target id"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 action " .. POST:sub(1, 7) .. " --sign " .. KEY2,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local T = load(exec {
            cmd = ENV_EXE .. " chain '#cli-like' get metadata " .. out,
        }, "metadata", "t", {})()
        assert(T.cid == POST, "target should be the full id: " .. tostring(T.cid))
    end

    do
        TEST "like-is-signed"
        local hash = exec {
            cmd = "git -C " .. DIR .. " rev-parse HEAD",
        }
        local key = ssh.verify(DIR, hash)
        assert(key == PUB2, "verify failed: " .. tostring(key))
    end

    do
        TEST "like-ancestor-is-post"
        local _, code = exec { err=false,
            cmd = "git -C " .. DIR .. " merge-base --is-ancestor " .. CID(DIR, POST) .. " HEAD",
        }
        assert(code == 0, "post should be ancestor of HEAD")
    end
end

-- DISLIKE (like -1)
do
    print("==> freechains chain like (-1)")

    local TARGET2 = exec {
        cmd = ENV_EXE .. " chain '#cli-like' post inline 'another post' --sign " .. KEY1,
    }

    local DISLIKE
    do
        TEST "dislike-success"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-like' dislike 1000 action " .. TARGET2 .. " --sign " .. KEY2,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex: " .. out)
        DISLIKE = out
    end

    do
        TEST "dislike-is-like-action"
        local out = exec { trim=false,
            cmd = "git -C " .. DIR .. " log -1 --format=%B " .. DISLIKE,
        }
        -- a dislike is a `like` with negative n
        assert(out:match("^like %-1000\n"), "message: " .. out)
    end

    do
        TEST "dislike-with-why"
        local TARGET3 = exec {
            cmd = ENV_EXE .. " chain '#cli-like' post inline 'bad content' --sign " .. KEY1,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-like' dislike 1000 action " .. TARGET3 .. " --sign " .. KEY2 .. " --why 'spam content'",
        }
        assert(code == 0, "exit code: " .. tostring(code))

        TEST "why is the vote's payload"
        local why = exec {
            cmd = ENV_EXE .. " chain '#cli-like' get payload " .. out,
        }
        assert(why == "spam content", "why: " .. why)

        TEST "the why is NOT in the message (payload blob only)"
        local msg = exec { trim=false,
            cmd = "git -C " .. DIR .. " log -1 --format=%B HEAD",
        }
        assert(not msg:find("spam content", 1, true),
            "why must stay out of the action: " .. msg)
    end

    do
        TEST "vote without why has empty payload"
        local pay, code = exec {
            cmd = ENV_EXE .. " chain '#cli-like' get payload " .. DISLIKE,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(pay == "", "payload should be empty: " .. pay)
    end
end

-- LIKE AUTHOR (fresh chain)
exec {
    cmd = ENV_EXE .. " chains rem '#cli-like'",
}
exec {
    cmd = ENV_EXE .. " chains add '#cli-like' init " .. GEN_2,
}
do
    print("==> freechains chain like author")

    -- KEY1=15, KEY2=15
    do
        TEST "like-author-success"
        -- cli.md "Keys:": the author may be a key FILE (resolves to
        -- PUB2), not only the key string
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 author " .. KEY2 .. ".pub --sign " .. KEY1,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
    end

    do
        TEST "like-author-liker-cost"
        -- KEY1: 25000 - 1000 (like cost) = 24000
        local out = exec {
            cmd = ENV_EXE .. " chain '#cli-like' reps author '" .. PUB1 .. "'",
        }
        assert(out == "24000", "liker reps: " .. out)

        TEST "like-author-target-gains"
        -- KEY2: 25000 + 900 = 25900
        local out = exec {
            cmd = ENV_EXE .. " chain '#cli-like' reps author '" .. PUB2 .. "'",
        }
        assert(out == "25900", "target reps: " .. out)
    end

    do
        TEST "like-author-2-transfer"
        -- like 2000: KEY1 pays 2000 cost, KEY2 gets 2000*90%=1800
        exec {
            cmd = ENV_EXE .. " chain '#cli-like' like 2000 author '" .. PUB2 .. "'" .. " --sign " .. KEY1,
        }
        local k1 = exec {
            cmd = ENV_EXE .. " chain '#cli-like' reps author '" .. PUB1 .. "'",
        }
        local k2 = exec {
            cmd = ENV_EXE .. " chain '#cli-like' reps author '" .. PUB2 .. "'",
        }
        -- KEY1: 24000 - 2000 = 22000
        -- KEY2: 25900 + 1800 = 27700
        assert(k1 == "22000", "liker reps: " .. k1)
        assert(k2 == "27700", "target reps: " .. k2)
    end

    do
        TEST "dislike-author"
        exec {
            cmd = ENV_EXE .. " chain '#cli-like' dislike 1000 author '" .. PUB2 .. "'" .. " --sign " .. KEY1,
        }
        local k1 = exec {
            cmd = ENV_EXE .. " chain '#cli-like' reps author '" .. PUB1 .. "'",
        }
        local k2 = exec {
            cmd = ENV_EXE .. " chain '#cli-like' reps author '" .. PUB2 .. "'",
        }
        -- KEY1: 22000 - 1000 = 21000
        -- KEY2: 27700 - 900 = 26800
        assert(k1 == "21000", "liker reps: " .. k1)
        assert(k2 == "26800", "target reps: " .. k2)
    end
end

-- WHITESPACE TRIM
do
    print("==> Whitespace trim")

    do
        TEST "like-author-whitespace"
        local before_s = exec {
            cmd = ENV_EXE .. " chain '#cli-like' reps author '" .. PUB2 .. "'",
        }
        exec {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 author ' " .. PUB2 .. " \n' --sign " .. KEY1,
        }
        local after_s = exec {
            cmd = ENV_EXE .. " chain '#cli-like' reps author '" .. PUB2 .. "'",
        }
        local before, after = tonumber(before_s), tonumber(after_s)
        assert(after > before, "expected reps gain, got " .. before .. " -> " .. after)
    end
end

-- ERROR CASES
do
    print("==> Error cases")

    POST = exec {
        cmd = ENV_EXE .. " chain '#cli-like' post inline 'target post' --sign " .. KEY1,
    }

    do
        TEST "like-nonexistent-post"
        local fake = "0000000000000000000000000000000000000000"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 action " .. fake .. " --sign " .. KEY2,
            -- an unknown hash fails at resolution (ACTION.full),
            -- before the rules' "action not found"
            err = "ERROR : chain like : invalid target",
        }
    end

    do
        TEST "self-like-allowed"
        local self_target = exec {
            cmd = ENV_EXE .. " chain '#cli-like' post inline 'self target' --sign " .. KEY1,
        }
        local _, code = exec {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 action " .. self_target .. " --sign " .. KEY1,
        }
        assert(code == 0, "self-like should succeed")
    end

    do
        TEST "self-dislike-allowed"
        local self_target = exec {
            cmd = ENV_EXE .. " chain '#cli-like' post inline 'self dislike' --sign " .. KEY1,
        }
        local _, code = exec {
            cmd = ENV_EXE .. " chain '#cli-like' dislike 1000 action " .. self_target .. " --sign " .. KEY1,
        }
        assert(code == 0, "self-dislike should succeed")
    end

    do
        TEST "like-requires-sign"
        local err = FAIL {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 action " .. POST,
        }
        assert(err and err:match("missing option '%-%-sign'"), "should fail: " .. tostring(err))
    end

    do
        TEST "like-zero-number"
        local err = FAIL {
            cmd = ENV_EXE .. " chain '#cli-like' like 0 action " .. POST .. " --sign " .. KEY1,
        }
        assert(err:match("Error: expected positive integer : got '0'"), "like with 0 should fail")
        TEST "like-non-numeric"
        local err = FAIL {
            cmd = ENV_EXE .. " chain '#cli-like' like abc action " .. POST .. " --sign " .. KEY1,
        }
        assert(err:match("Error: expected positive integer : got 'abc'"), "should fail with non-numeric number")
    end

    do
        TEST "like-bad-target-type"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 foo " .. POST .. " --sign " .. KEY1,
            err = "ERROR : chain like : invalid target",
        }
    end

    do
        TEST "like with invalid sign key fails"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 action " .. POST .. " --sign bad-key",
            err = "ERROR : chain like : invalid sign key",
        }
    end

    do
        TEST "like with invalid author key fails"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 author bad-key --sign " .. KEY1,
            err = "ERROR : chain like : invalid author key",
        }
    end

    do
        TEST "like-author-only-whitespace"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-like' like 1000 author '   ' --sign " .. KEY1,
            err = "ERROR : chain like : invalid author key",
        }
    end
end

print("<== ALL PASSED")
