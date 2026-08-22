#!/usr/bin/env lua5.4

require "tests"

local DIR = ROOT .. "/chains/#cli-get/"
local UNKNOWN = "0000000000000000000000000000000000000000"

exec {
    cmd = ENV_EXE .. " chains add '#cli-get' init " .. GEN_2,
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
        local T = META(out)
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
        local T = META(out)
        assert(T.action == "post", "action: " .. tostring(T.action))
        assert(math.type(T.time) == "integer", "time: " .. tostring(T.time))
        assert(type(T.blob) == "string" and #T.blob == 40, "blob: " .. tostring(T.blob))
        assert(T.cid == nil, "post metadata has no cid key: " .. tostring(T.cid))
        assert(T.n == nil, "post metadata has no n key: " .. tostring(T.n))
        assert(type(T.sign) == "string", "sign type: " .. type(T.sign))
        assert(T.sign:match("^ssh%-ed25519 "), "sign: " .. tostring(T.sign))
        assert(T.id == POST, "id: " .. tostring(T.id))
        -- backs are STRUCTURAL (walked from the parents): the
        -- first post backs only the genesis, which is no action
        assert(#T.backs == 0, "backs: " .. #T.backs)
    end

    do
        TEST "metadata of like"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. LIKE,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local T = META(out)
        assert(T.action == "like", "action: " .. tostring(T.action))
        assert(T.cid == POST, "cid: " .. tostring(T.cid))
        assert(T.author == nil, "author should be unset")
        assert(math.type(T.n) == "integer", "n: " .. tostring(T.n))
        assert(T.backs[1] == POST, "back should be POST")
        -- backs are structural: the like's parent commit IS the post
        local up = exec {
            cmd = "git -C " .. DIR .. " rev-parse " .. LIKE .. "^1",
        }
        assert(up == POST, "parent should be POST: " .. up)
    end

    do
        TEST "metadata of revoke"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-get' get metadata " .. REVOKE,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local T = META(out)
        assert(T.action == "revoke", "action: " .. tostring(T.action))
        assert(T.cid == RPOST, "cid: " .. tostring(T.cid))
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
        local T = META(out)
        assert(T.sign == nil, "sign: " .. tostring(T.sign))
        assert(T.action == "post", "action: " .. tostring(T.action))
        -- backs are structural: the unsigned post's parent is LIKE
        local up = exec {
            cmd = "git -C " .. DIR .. " rev-parse " .. UNSIGNED .. "^1",
        }
        assert(up == LIKE, "parent should be LIKE: " .. up)
    end

    do
        TEST "merge-like (beg merge): TWO structural parents"
        local ps = exec {
            cmd = "git -C " .. DIR .. " rev-list --parents -n 1 " .. MERGE_LIKE,
        }
        local s = {}
        for h in ps:gmatch("%x+") do
            s[h] = true
        end
        s[MERGE_LIKE] = nil
        assert(s[LIKE],     "parents should contain LIKE: "     .. ps)
        assert(s[UNSIGNED], "parents should contain UNSIGNED: " .. ps)
    end
end

print("<== ALL PASSED")
