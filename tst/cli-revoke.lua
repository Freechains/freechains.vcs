#!/usr/bin/env lua5.4

require "tests"

-- Content revocation, two paths:
--  * community: any single net revoke (min hardcoded to 1) hides the
--    payload; reversible via unrevoke.
--  * author: self-revoke is absolute (right to be forgotten), applies
--    regardless of the community net; only the author can unrevoke it.
-- Phase 1 hides the payload only (metadata stays).

exec {
    cmd = ENV_EXE .. " chains add '#cli-revoke' init file " .. GEN_3,
}

-- KEY1 posts the target (author = KEY1)
local POST = exec {
    cmd = ENV_EXE .. " chain '#cli-revoke' post inline 'revoke-me' --sign " .. KEY1,
}

do
    print("==> Revoke: readable before")

    do
        TEST "revoke-payload-before"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "revoke-me", "payload: " .. out)
    end
end

do
    print("==> Revoke: community single revoke (min 1) + reversible")

    do
        TEST "revoke-community-hides"
        -- KEY2 is not the author: one revoke -> net 1 -> revoked
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1 " .. POST .. " --sign " .. KEY2,
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
            err = "ERROR : chain get : revoked post",
        }
    end

    do
        TEST "revoke-community-reversible"
        -- KEY2 unrevoke -> net 0 -> readable
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1 " .. POST .. " --sign " .. KEY2,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "revoke-me", "payload should read: " .. out)
    end
end

do
    print("==> Revoke: author self-revoke is absolute")

    do
        TEST "revoke-author-forgets-free"
        -- KEY1 is the author: self-revoke is FREE (right to be forgotten)
        local before = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps author '" .. PUB1 .. "'",
        }
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1 " .. POST .. " --sign " .. KEY1,
        }
        local after = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps author '" .. PUB1 .. "'",
        }
        assert(before == after, "self-revoke must be free: " .. before .. " -> " .. after)
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
            err = "ERROR : chain get : revoked post",
        }
    end

    do
        TEST "revoke-author-above-community"
        -- a community unrevoke cannot restore an author-forgotten post
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1 " .. POST .. " --sign " .. KEY2,
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
            err = "ERROR : chain get : revoked post",
        }
    end

    do
        TEST "revoke-author-unrevoke"
        -- only the author can lift their own forget
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1 " .. POST .. " --sign " .. KEY1,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "revoke-me", "payload should read again: " .. out)
    end
end

exec {
    cmd = ENV_EXE .. " chains rem '#cli-revoke'",
}

print("<== ALL PASSED")
