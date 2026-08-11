#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/#cli-get/"
local UNKNOWN = "0000000000000000000000000000000000000000"

exec {
    cmd = ENV_EXE .. " chains add '#cli-get' init file " .. GEN_2,
}
local POST = exec {
    cmd = ENV_EXE .. " chain '#cli-get' post inline 'hello world' --sign " .. KEY1,
}
local LIKE = exec {
    cmd = ENV_EXE .. " chain '#cli-get' like 1000 action " .. POST .. " --sign " .. KEY2,
}
local GENESIS = exec {
    cmd = "git -C " .. DIR .. " rev-list --max-parents=0 HEAD",
}

-- unsigned post: --beg stores it in refs/begs/, then a like merges it
-- back into the main chain so it becomes reachable from HEAD
local UNSIGNED = exec {
    cmd = ENV_EXE .. " chain '#cli-get' post inline 'unsigned content' --beg",
}
local MERGE_LIKE = exec {
    cmd = ENV_EXE .. " chain '#cli-get' like 1000 action " .. UNSIGNED .. " --sign " .. KEY2,
}

-- a separate post + a community revoke of it, to exercise the revoke
-- kind (revoking POST would hide it and break the payload test above)
local RPOST = exec {
    cmd = ENV_EXE .. " chain '#cli-get' post inline 'to be revoked' --sign " .. KEY1,
}
local REVOKE = exec {
    cmd = ENV_EXE .. " chain '#cli-get' revoke 1000 " .. RPOST .. " --sign " .. KEY2,
}

-- GET PAYLOAD
do
    print("==> freechains chain get payload")

    do
        TEST "payload of post"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get payload " .. POST,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "hello world", "content: " .. out)
    end

    do
        TEST "payload of like (no --why): empty"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get payload " .. LIKE,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "", "content: " .. out)
    end

    do
        TEST "payload of revoke (no --why): empty"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get payload " .. REVOKE,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "", "content: " .. out)
    end

    do
        TEST "payload of a SHORT id"
        -- ids are printed abbreviated (`list dag`), so a prefix must
        -- resolve, like git does with commit hashes
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get payload " .. POST:sub(1, 7),
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "hello world", "content: " .. out)
    end

    do
        TEST "payload of a TOO SHORT id"
        -- one char cannot even name the bucket
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-get' get payload " .. POST:sub(1, 1),
            err = "ERROR : chain get : unknown post",
        }
    end

    do
        TEST "metadata of a SHORT id"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. POST:sub(1, 7),
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local T = load(out, "metadata", "t", {})()
        assert(T.action == "post", "action: " .. tostring(T.action))
    end

    do
        TEST "payload of genesis"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-get' get payload " .. GENESIS,
            err = "ERROR : chain get : unknown post",
        }
    end

    do
        TEST "payload of unknown"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-get' get payload " .. UNKNOWN,
            err = "ERROR : chain get : unknown post",
        }
    end
end

-- GET METADATA
do
    print("==> freechains chain get metadata")

    do
        TEST "metadata of post"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. POST,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local T = load(out, "metadata", "t", {})()
        assert(T.action == "post", "action: " .. tostring(T.action))
        assert(math.type(T.time) == "integer", "time: " .. tostring(T.time))
        assert(type(T.blob) == "string" and #T.blob == 40, "blob: " .. tostring(T.blob))
        assert(T.aid == nil, "post metadata has no aid key: " .. tostring(T.aid))
        assert(T.n == nil, "post metadata has no n key: " .. tostring(T.n))
        assert(type(T.sign) == "string", "sign type: " .. type(T.sign))
        assert(T.sign:match("^ssh%-ed25519 "), "sign: " .. tostring(T.sign))
        assert(type(T.backs) == "table", "backs type: " .. type(T.backs))
        assert(#T.backs == 0, "POST is the first post; expected 0 backs, got: " .. #T.backs)
    end

    do
        TEST "metadata of like"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. LIKE,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local T = load(out, "metadata", "t", {})()
        assert(T.action == "like", "action: " .. tostring(T.action))
        assert(T.aid == POST, "aid: " .. tostring(T.aid))
        assert(T.author == nil, "author should be unset")
        assert(math.type(T.n) == "integer", "n: " .. tostring(T.n))
        assert(#T.backs == 1, "expected 1 back, got: " .. #T.backs)
        assert(T.backs[1] == POST, "back should be POST: " .. tostring(T.backs[1]))
    end

    do
        TEST "metadata of revoke"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. REVOKE,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local T = load(out, "metadata", "t", {})()
        assert(T.action == "revoke", "action: " .. tostring(T.action))
        assert(T.aid == RPOST, "aid: " .. tostring(T.aid))
        assert(math.type(T.n) == "integer", "n: " .. tostring(T.n))
        assert(T.n < 0, "n should be negative: " .. tostring(T.n))
    end

    do
        TEST "metadata of genesis"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. GENESIS,
            err = "ERROR : chain get : unknown post",
        }
    end

    do
        TEST "metadata of unknown"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. UNKNOWN,
            err = "ERROR : chain get : unknown post",
        }
    end

    do
        TEST "metadata of unsigned post"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. UNSIGNED,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local T = load(out, "metadata", "t", {})()
        assert(T.sign == nil, "sign: " .. tostring(T.sign))
        assert(T.action == "post", "action: " .. tostring(T.action))
        assert(#T.backs == 1, "expected 1 back, got: " .. #T.backs)
        assert(T.backs[1] == LIKE, "back should be LIKE: " .. tostring(T.backs[1]))
    end

    do
        TEST "metadata of merge-like (beg merge, 2 backs)"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. MERGE_LIKE,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local T = load(out, "metadata", "t", {})()
        assert(#T.backs == 2, "expected 2 backs, got: " .. #T.backs)
        local s = { [T.backs[1]] = true, [T.backs[2]] = true }
        assert(s[LIKE],     "backs should contain LIKE: "     .. table.concat(T.backs, " "))
        assert(s[UNSIGNED], "backs should contain UNSIGNED: " .. table.concat(T.backs, " "))
    end
end

print("<== ALL PASSED")
