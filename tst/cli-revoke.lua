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
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. POST .. " --sign " .. KEY2,
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
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1000 " .. POST .. " --sign " .. KEY2,
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
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. POST .. " --sign " .. KEY1,
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
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1000 " .. POST .. " --sign " .. KEY2,
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
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1000 " .. POST .. " --sign " .. KEY1,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "revoke-me", "payload should read again: " .. out)
    end
end

do
    print("==> Revoke: votes (like/revoke) are not posts")

    -- a throwaway post + its like and revoke commits, to target;
    -- revoking those vote commits must fail (they are not posts)
    local RP = exec {
        cmd = ENV_EXE .. " chain '#cli-revoke' post inline 'aux' --sign " .. KEY1,
    }
    local L = exec {
        cmd = ENV_EXE .. " chain '#cli-revoke' like 1000 post " .. RP .. " --sign " .. KEY2,
    }
    local R = exec {
        cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. RP .. " --sign " .. KEY2,
    }

    do
        TEST "revoke-a-like-rejected"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. L .. " --sign " .. KEY2,
            err = "ERROR : chain revoke : invalid target : post not found",
        }
    end

    do
        TEST "revoke-a-revoke-rejected"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. R .. " --sign " .. KEY2,
            err = "ERROR : chain revoke : invalid target : post not found",
        }
    end
end

do
    print("==> Revoke: coupling with the reputation axis")

    -- a `like` also unrevokes, a `revoke` also dislikes;
    -- the converses are false (`dislike` never hides, `unrevoke`
    -- never credits)
    local P = exec {
        cmd = ENV_EXE .. " chain '#cli-revoke' post inline 'coupled' --sign " .. KEY1,
    }

    do
        TEST "revoke-like-lifts"
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. P .. " --sign " .. KEY2,
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. P,
            err = "ERROR : chain get : revoked post",
        }
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' like 1000 post " .. P .. " --sign " .. KEY2,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. P,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "coupled", "like should lift the revoke: " .. out)
    end

    do
        TEST "revoke-dislike-keeps"
        -- a dislike drains the post, but never hides it
        local before = tonumber((exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps post " .. P,
        }))
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' dislike 1000 post " .. P .. " --sign " .. KEY2,
        }
        local after = tonumber((exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps post " .. P,
        }))
        assert(after < before, "dislike should drain: " .. before .. " -> " .. after)
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. P,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "coupled", "dislike should not hide: " .. out)
    end

    do
        TEST "revoke-unrevoke-no-reps"
        -- an unrevoke costs the caster, but credits nobody
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. P .. " --sign " .. KEY3,
        }
        local post_1 = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps post " .. P,
        }
        local sign_1 = tonumber((exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps author '" .. PUB3 .. "'",
        }))
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1000 " .. P .. " --sign " .. KEY3,
        }
        local post_2 = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps post " .. P,
        }
        local sign_2 = tonumber((exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps author '" .. PUB3 .. "'",
        }))
        assert(post_1 == post_2, "unrevoke must not credit: " .. post_1 .. " -> " .. post_2)
        assert(sign_2 < sign_1, "unrevoke must cost: " .. sign_1 .. " -> " .. sign_2)
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. P,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "coupled", "unrevoke should restore: " .. out)
    end

    do
        TEST "revoke-self-like-keeps"
        -- the author's own like feeds the community channel, so it
        -- cannot lift their absolute self-revoke
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. P .. " --sign " .. KEY1,
        }
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' like 1000 post " .. P .. " --sign " .. KEY1,
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. P,
            err = "ERROR : chain get : revoked post",
        }
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1000 " .. P .. " --sign " .. KEY1,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. P,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "coupled", "author unrevoke should restore: " .. out)
    end

    do
        TEST "reps-revoke"
        -- author channel is back to 0, community is +1000 (the two likes
        -- and the unrevoke net against the two revokes)
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps revoke " .. P,
        }
        assert(code == 0,    "exit code: " .. tostring(code))
        assert(out == "0 1000", "channels: " .. out)
    end

    do
        TEST "reps-revokes"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps revokes",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out:find(P .. " 0 1", 1, true), "P not listed: " .. out)
    end

    do
        TEST "reps-revoke-no-hash"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps revoke",
            err = "ERROR : chain reps : revoke requires a hash",
        }
    end
end

exec {
    cmd = ENV_EXE .. " chains rem '#cli-revoke'",
}

print("<== ALL PASSED")
