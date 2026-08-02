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
        TEST "revoke-community-unrevoke-no-copy"
        -- Community revocation IS reversible by design (reps.md:287-312)
        -- and stays so: `revokes` (common.lua) drops the payload on
        -- either channel, and an unrevoked post returns via the by-hash
        -- step of the next sync -- local retention was never the
        -- restore mechanism.
        --
        -- This is a SINGLE node, so there is no peer to fetch it back
        -- from and no `--file` copy offered: the payload is gone for
        -- good and the gate refuses rather than promise a restore
        -- nobody can deliver. Not a missing feature -- the decision
        -- that a revoke with no surviving copy is permanent.
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1 " .. POST .. " --sign " .. KEY2,
            err = "ERROR : chain unrevoke : blob unavailable",
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
            err = "ERROR : chain get : revoked post",
        }
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
        TEST "revoke-author-unrevoke-blob-gone"
        -- the author's own self-revoke physically removed the
        -- payload (260721-remove-blob.md, `revokes`); even the
        -- author's own unrevoke is gated on the blob still being
        -- available (nobody else on this single-node test holds a
        -- copy), so it is correctly refused, not silently accepted
        -- into a promise nobody can keep
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1 " .. POST .. " --sign " .. KEY1,
            err = "ERROR : chain unrevoke : blob unavailable",
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
            err = "ERROR : chain get : revoked post",
        }
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
        cmd = ENV_EXE .. " chain '#cli-revoke' like 1 post " .. RP .. " --sign " .. KEY2,
    }
    local R = exec {
        cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1 " .. RP .. " --sign " .. KEY2,
    }

    do
        TEST "revoke-a-like-rejected"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1 " .. L .. " --sign " .. KEY2,
            err = "ERROR : chain revoke : invalid target : post not found",
        }
    end

    do
        TEST "revoke-a-revoke-rejected"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1 " .. R .. " --sign " .. KEY2,
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
        TEST "revoke-like-lift-no-copy"
        -- reps.md:278 -- a positive `like` also counts as an unrevoke,
        -- and is gated exactly like one. `revokes` dropped the payload
        -- and this single node has no way to get it back, so the gate
        -- refuses the like outright and the sum never moves. With a
        -- peer still serving the bytes (or `--file`) it would succeed.
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1 " .. P .. " --sign " .. KEY2,
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. P,
            err = "ERROR : chain get : revoked post",
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' like 1 post " .. P .. " --sign " .. KEY2,
            err = "ERROR : chain like : blob unavailable",
        }
    end

    -- The remaining coupling rules do not need a payload to come back,
    -- so they are still tested for real -- on posts chosen so the vote
    -- under test never has to lift a revoke.

    do
        TEST "revoke-dislike-keeps"
        -- a dislike drains the post, but never hides it: use a post that
        -- was never revoked, so nothing was dropped
        local D = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' post inline 'drained' --sign " .. KEY1,
        }
        local before = tonumber((exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps post " .. D,
        }))
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' dislike 1 post " .. D .. " --sign " .. KEY2,
        }
        local after = tonumber((exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps post " .. D,
        }))
        assert(after < before, "dislike should drain: " .. before .. " -> " .. after)
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. D,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "drained", "dislike should not hide: " .. out)
    end

    -- An AUTHOR-revoked post: the author channel keeps forcing REVOKED,
    -- so a community vote on it never flips `is_revoked` and is never
    -- gated -- which lets the reps math below be tested for real.
    local Q = exec {
        cmd = ENV_EXE .. " chain '#cli-revoke' post inline 'authored' --sign " .. KEY1,
    }
    exec {
        cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1 " .. Q .. " --sign " .. KEY1,
    }

    do
        TEST "revoke-unrevoke-no-reps"
        -- an unrevoke costs the caster, but credits nobody
        local post_1 = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps post " .. Q,
        }
        local sign_1 = tonumber((exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps author '" .. PUB3 .. "'",
        }))
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1 " .. Q .. " --sign " .. KEY3,
        }
        local post_2 = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps post " .. Q,
        }
        local sign_2 = tonumber((exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps author '" .. PUB3 .. "'",
        }))
        assert(post_1 == post_2, "unrevoke must not credit: " .. post_1 .. " -> " .. post_2)
        assert(sign_2 < sign_1, "unrevoke must cost: " .. sign_1 .. " -> " .. sign_2)
    end

    do
        TEST "revoke-self-like-keeps"
        -- the author's own like feeds the COMMUNITY channel, so it can
        -- never lift their absolute self-revoke
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' like 1 post " .. Q .. " --sign " .. KEY1,
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. Q,
            err = "ERROR : chain get : revoked post",
        }
    end

    do
        TEST "revoke-author-unrevoke-no-copy"
        -- only the author lifts their own channel -- and that lift WOULD
        -- flip the post back, so it is gated, and the payload is gone
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 1 " .. Q .. " --sign " .. KEY1,
            err = "ERROR : chain unrevoke : blob unavailable",
        }
    end

    do
        TEST "reps-revoke"
        -- Q: author -1 (the self-revoke; its unrevoke was refused),
        -- others +2 (KEY3's unrevoke + KEY1's self-like)
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps revoke " .. Q,
        }
        assert(code == 0,     "exit code: " .. tostring(code))
        assert(out == "-1 2", "channels: " .. out)
    end

    do
        TEST "reps-revokes"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps revokes",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out:find(Q .. " -1 2", 1, true), "Q not listed: " .. out)
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
