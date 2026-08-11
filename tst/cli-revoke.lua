#!/usr/bin/env lua5.4

require "tests"

-- Content revocation, two paths:
--  * community: any negative net hides the payload, but a vote on the
--    axis weighs at least 1000; reversible via unrevoke.
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
    print("==> Revoke: community single revoke (min 1000) + reversible")

    do
        TEST "revoke-floor"
        -- dust may not bury a post: the axis weighs in units
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1 " .. POST .. " --sign " .. KEY2,
            err = "ERROR : chain revoke : invalid number : expects at least 1000",
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' unrevoke 999 " .. POST .. " --sign " .. KEY2,
            err = "ERROR : chain unrevoke : invalid number : expects at least 1000",
        }
        -- a like/dislike carries no floor (it is not a revoke), so
        -- nothing here changes the state: both commands died
    end

    do
        TEST "revoke-community-hides"
        -- KEY2 is not the author: one revoke -> net -1000 -> revoked
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. POST .. " --sign " .. KEY2,
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. POST,
            err = "ERROR : chain get : revoked payload",
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
            err = "ERROR : chain get : revoked payload",
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
            err = "ERROR : chain get : revoked payload",
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
    print("==> Revoke: a vote's why is a payload too")

    -- a `--why` is user-authored text with its own blob, so it is
    -- revokable exactly like a post's content: the target of the
    -- axis is any ACTION, not just a post
    local RP = exec {
        cmd = ENV_EXE .. " chain '#cli-revoke' post inline 'aux' --sign " .. KEY1,
    }
    local L = exec {
        cmd = ENV_EXE .. " chain '#cli-revoke' like 1000 post " .. RP ..
            " --why 'abusive text' --sign " .. KEY2,
    }

    do
        TEST "revoke-vote-why-readable"
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. L,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "abusive text", "why: " .. out)
    end

    do
        TEST "revoke-a-vote-hides-its-why"
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. L .. " --sign " .. KEY3,
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' get payload " .. L,
            err = "ERROR : chain get : revoked payload",
        }
    end

    do
        TEST "revoke-vote-moves-only-the-axis"
        -- a vote has no score of its own, so nothing was credited
        assert(exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps revoke " .. L,
        } == "0 -1000")
        assert(exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps post " .. L,
        } == "0")
    end

    do
        TEST "revoke-vote-author-channel"
        -- the signer forgetting their own why is free and absolute
        local before = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps author '" .. PUB2 .. "'",
        }
        exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " .. L .. " --sign " .. KEY2,
        }
        local after = exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps author '" .. PUB2 .. "'",
        }
        assert(before == after, "self-revoke must be free: " .. before .. " -> " .. after)
        assert(exec {
            cmd = ENV_EXE .. " chain '#cli-revoke' reps revoke " .. L,
        } == "-1000 -1000")
    end

    do
        TEST "revoke-unknown-action-rejected"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-revoke' revoke 1000 " ..
                string.rep("0", 40) .. " --sign " .. KEY3,
            err = "ERROR : chain revoke : invalid target : action not found",
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
            err = "ERROR : chain get : revoked payload",
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
            err = "ERROR : chain get : revoked payload",
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

-- REMOVAL: crossing into REVOKED drops the payload anchor
do
    print("==> Removal on revoke")

    exec {
        cmd = ENV_EXE .. " chains add '#removal' init file " .. GEN_2,
    }
    local DIR = ROOT .. "/chains/#removal/"
    local POST = exec {
        cmd = ENV_EXE .. " chain '#removal' post inline 'bytes' --sign " .. KEY1,
    }

    do
        TEST "the payload is anchored while the post stands"
        local _, code = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR .. " rev-parse refs/payloads/" .. POST,
        }
        assert(code == 0, "anchor should exist")
    end

    do
        TEST "revoking drops the anchor"
        exec {
            cmd = ENV_EXE .. " chain '#removal' revoke 1000 " .. POST .. " --sign " .. KEY2,
        }
        local _, code = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR .. " rev-parse refs/payloads/" .. POST,
        }
        assert(code ~= 0, "anchor should be gone")
    end

    do
        TEST "unrevoking re-anchors it"
        exec {
            cmd = ENV_EXE .. " chain '#removal' unrevoke 1000 " .. POST .. " --sign " .. KEY2,
        }
        local pay = exec {
            cmd = ENV_EXE .. " chain '#removal' get payload " .. POST,
        }
        assert(pay == "bytes", "payload: " .. pay)
        -- a standing post keeps its anchor, or the next gc eats it
        local _, code = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR .. " rev-parse refs/payloads/" .. POST,
        }
        assert(code == 0, "anchor should be back")
    end
end

-- GATED UNREVOKE: a post leaves REVOKED only with its bytes
do
    print("==> Gated unrevoke")

    exec {
        cmd = ENV_EXE .. " chains add '#gated' init file " .. GEN_2,
    }
    local POST = exec {
        cmd = ENV_EXE .. " chain '#gated' post inline 'precious' --sign " .. KEY1,
    }
    exec {
        cmd = ENV_EXE .. " chain '#gated' revoke 1000 " .. POST .. " --sign " .. KEY2,
    }

    do
        TEST "a wrong --file is caught even with the bytes here"
        -- the revoke above dropped the ANCHOR, not the object: the
        -- fallback is redundant now, which is no excuse to trust it
        local tmp = TMP .. "/wrong-present.txt"
        local f = io.open(tmp, "w")
        f:write("not the original\n")
        f:close()
        FAIL {
            cmd = ENV_EXE .. " chain '#gated' unrevoke 1000 " .. POST ..
                " --file " .. tmp .. " --sign " .. KEY2,
            err = "ERROR : chain unrevoke : blob mismatch",
        }
    end

    -- drop the bytes the way `abandon` or a sweep would
    local DIR = ROOT .. "/chains/#gated/"
    exec {
        cmd = "git -C " .. DIR .. " update-ref -d refs/payloads/" .. POST,
    }
    exec {
        cmd = "git -C " .. DIR .. " gc --prune=now --quiet",
    }

    do
        TEST "unrevoke without the bytes is refused"
        FAIL {
            cmd = ENV_EXE .. " chain '#gated' unrevoke 1000 " .. POST .. " --sign " .. KEY2,
            err = "ERROR : chain unrevoke : expected --file",
        }
    end

    do
        TEST "a wrong --file does not match the pinned hash"
        local tmp = TMP .. "/wrong.txt"
        local f = io.open(tmp, "w")
        f:write("not the original\n")
        f:close()
        FAIL {
            cmd = ENV_EXE .. " chain '#gated' unrevoke 1000 " .. POST ..
                " --file " .. tmp .. " --sign " .. KEY2,
            err = "ERROR : chain unrevoke : blob mismatch",
        }
    end

    do
        TEST "a lifting LIKE is gated too"
        -- a positive like counts as an unrevoke, so it may not
        -- lift a post whose bytes nobody holds
        FAIL {
            cmd = ENV_EXE .. " chain '#gated' like 1000 post " .. POST .. " --sign " .. KEY2,
            err = "ERROR : chain like : expected --file",
        }
    end

    do
        TEST "the right --file restores the payload"
        local tmp = TMP .. "/right.txt"
        local f = io.open(tmp, "w")
        f:write("precious")
        f:close()
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#gated' unrevoke 1000 " .. POST ..
                " --file " .. tmp .. " --sign " .. KEY2,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        local pay = exec {
            cmd = ENV_EXE .. " chain '#gated' get payload " .. POST,
        }
        assert(pay == "precious", "payload: " .. pay)
    end
end

print("<== ALL PASSED")
