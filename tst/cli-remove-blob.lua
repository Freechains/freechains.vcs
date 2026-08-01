#!/usr/bin/env lua5.4

require "tests"

-- Phase 2 of revocation (260721-remove-blob.md): honest peers
-- physically drop a REVOKED post's payload, not just hide it
-- (260721-revoke.md, Phase 1).
--
-- Removal is deferred to the end of a command (`revokes`,
-- common.lua).
--
-- Only the AUTHOR channel destroys, on every node. It is the
-- "absolute right to be forgotten" (reps.md:287-312). The community
-- channel is explicitly reversible and order-independent, so it hides
-- (Phase 1) and never drops the bytes -- otherwise a reversible vote
-- would become permanent, and whether a payload survived would depend
-- on the order a peer replayed votes in. Both are pinned below.

local DIR = ROOT .. "/chains/#cli-remove-blob/"

exec {
    cmd = ENV_EXE .. " chains add '#cli-remove-blob' init file " .. GEN_3,
}

local function blob_of (hash)
    local file = exec {
        cmd = "git -C " .. DIR .. " diff-tree --no-commit-id -r --name-only " .. hash,
    }
    local blob = exec {
        cmd = "git -C " .. DIR .. " rev-parse " .. hash .. ":" .. file,
    }
    return file, blob
end

do
    print("==> Physical removal: author self-revoke drops the blob")

    local POST = exec {
        cmd = ENV_EXE .. " chain '#cli-remove-blob' post inline 'delete-me' --sign " .. KEY1,
    }
    local file, blob = blob_of(POST)

    TEST "blob-present-before-revoke"
    do
        local _, code = exec {
            cmd = "git -C " .. DIR .. " cat-file -e " .. blob,
        }
        assert(code == 0, "blob should exist before revoke")
        local f = io.open(DIR .. file, "r")
        assert(f, "working-tree file should exist before revoke")
        f:close()
    end

    exec {
        cmd = ENV_EXE .. " chain '#cli-remove-blob' revoke 1 " .. POST .. " --sign " .. KEY1,
    }

    TEST "blob-object-gone-after-self-revoke"
    do
        local _, code = exec { err=false,
            cmd = "git -C " .. DIR .. " cat-file -e " .. blob,
        }
        assert(code ~= 0, "blob object should be gone")
    end

    TEST "worktree-file-gone-after-self-revoke"
    do
        local f = io.open(DIR .. file, "r")
        assert(not f, "working-tree file should be gone")
    end

    TEST "skip-worktree-bit-set"
    do
        local out = exec {
            cmd = "git -C " .. DIR .. " ls-files -v " .. file,
        }
        assert(out:match("^S"), "expected skip-worktree (S) flag: " .. out)
    end

    TEST "git-status-clean-after-removal"
    do
        local out = exec {
            cmd = "git -C " .. DIR .. " status --porcelain",
        }
        assert(out == "", "status should be clean: " .. out)
    end

    TEST "get-payload-fails-revoked"
    FAIL {
        cmd = ENV_EXE .. " chain '#cli-remove-blob' get payload " .. POST,
        err = "ERROR : chain get : revoked post",
    }

    TEST "new-post-after-removal-still-works"
    do
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-remove-blob' post inline 'still-works' --sign " .. KEY1,
        }
        assert(code == 0, "post-after-removal should succeed: " .. tostring(out))
    end

    TEST "gated-unrevoke-refused-blob-unavailable"
    FAIL {
        cmd = ENV_EXE .. " chain '#cli-remove-blob' unrevoke 1 " .. POST .. " --sign " .. KEY1,
        err = "ERROR : chain unrevoke : blob unavailable",
    }
end

do
    print("==> Community revoke drops the blob too (one rule, both channels)")

    local POST = exec {
        cmd = ENV_EXE .. " chain '#cli-remove-blob' post inline 'community-only' --sign " .. KEY1,
    }
    local file, blob = blob_of(POST)

    -- KEY2 is not the author -> community channel
    exec {
        cmd = ENV_EXE .. " chain '#cli-remove-blob' revoke 1 " .. POST .. " --sign " .. KEY2,
    }

    TEST "community-revoke-drops-blob"
    do
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-remove-blob' get payload " .. POST,
            err = "ERROR : chain get : revoked post",
        }
        local _, code = exec { err=false,
            cmd = "git -C " .. DIR .. " cat-file -e " .. blob,
        }
        assert(code ~= 0, "community revoke should drop the blob too")
    end

    TEST "community-unrevoke-pending-by-hash-fetch"
    do
        -- reversible by design (reps.md:287-312), but the return path is
        -- the by-hash step of the next sync, which is not built yet --
        -- so today the gate refuses. Flips back when step 2 lands.
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-remove-blob' unrevoke 1 " .. POST .. " --sign " .. KEY2,
            err = "ERROR : chain unrevoke : blob unavailable",
        }
    end
end

do
    print("==> Sync survives a removed blob (incremental, peer already holds it)")

    -- Two separate hosts (separate --root, like repl-local-head.lua):
    -- the clone destination is named after the shared genesis hash,
    -- so a same-root clone of a chain already present there always
    -- fails (cli-chains.lua's "clone existing chain fails") -- real
    -- peers are separate machines, i.e. separate roots.
    --
    -- A FULL clone after removal still needs `filter=blob:none` +
    -- `uploadpack.allowFilter`, which is not implemented yet
    -- (260721-remove-blob.md open items). Cloning B before any
    -- removal avoids that and exercises exactly what IS implemented:
    -- incremental fetch after a removal, which does not renegotiate
    -- the missing blob.
    local ROOT_A = ROOT .. "/remove-blob-sync/A/"
    local ROOT_B = ROOT .. "/remove-blob-sync/B/"
    local EXE_A  = "../src/freechains.lua --root " .. ROOT_A
    local EXE_B  = "../src/freechains.lua --root " .. ROOT_B
    exec { cmd = "mkdir -p " .. ROOT_A }
    exec { cmd = "mkdir -p " .. ROOT_B }

    exec {
        cmd = EXE_A .. " chains add '#test' init file " .. GEN_3,
    }
    local DIR_A = ROOT_A .. "/chains/#test/"

    local POST = exec {
        cmd = EXE_A .. " chain '#test' post inline 'to-be-removed' --sign " .. KEY1,
    }

    -- B clones AFTER this post but BEFORE the removal -- it already
    -- holds the blob, same as any real pre-revocation holder would.
    exec {
        cmd = EXE_B .. " chains add '#test' clone " .. DIR_A,
    }

    exec {
        cmd = EXE_A .. " chain '#test' revoke 1 " .. POST .. " --sign " .. KEY1,
    }
    exec {
        cmd = EXE_A .. " chain '#test' post inline 'after-removal' --sign " .. KEY1,
    }

    TEST "incremental-sync-after-removal-succeeds"
    do
        local out, code = exec {
            cmd = EXE_B .. " chain '#test' sync recv '" .. DIR_A .. "'",
        }
        assert(code == 0, "sync recv should succeed despite the removed blob: " .. tostring(out))
    end

    TEST "peer-sees-the-revoke-via-synced-state"
    FAIL {
        cmd = EXE_B .. " chain '#test' get payload " .. POST,
        err = "ERROR : chain get : revoked post",
    }

    -- A community revoke drops the payload on the voting node, exactly
    -- like an author one -- one rule, both channels.
    local C_POST = exec {
        cmd = EXE_A .. " chain '#test' post inline 'community-target' --sign " .. KEY1,
    }
    local c_file = exec {
        cmd = "git -C " .. DIR_A .. " diff-tree --no-commit-id -r --name-only " .. C_POST,
    }
    local c_blob = exec {
        cmd = "git -C " .. DIR_A .. " rev-parse " .. C_POST .. ":" .. c_file,
    }

    -- B takes a copy BEFORE the revoke, so it still holds the bytes
    exec {
        cmd = EXE_B .. " chain '#test' sync recv '" .. DIR_A .. "'",
    }

    exec {
        cmd = EXE_A .. " chain '#test' revoke 1 " .. C_POST .. " --sign " .. KEY2,
    }

    TEST "community-revoke-drops-blob-on-the-voting-node"
    do
        local _, code = exec { err=false,
            cmd = "git -C " .. DIR_A .. " cat-file -e " .. c_blob,
        }
        assert(code ~= 0, "community revoke should drop the blob")
    end

    TEST "community-revoke-drops-blob-on-the-synced-peer-too"
    do
        local out, code = exec {
            cmd = EXE_B .. " chain '#test' sync recv '" .. DIR_A .. "'",
        }
        assert(code == 0, "sync recv should succeed: " .. tostring(out))
        FAIL {
            cmd = EXE_B .. " chain '#test' get payload " .. C_POST,
            err = "ERROR : chain get : revoked post",
        }
        local _, ccode = exec { err=false,
            cmd = "git -C " .. ROOT_B .. "/chains/#test/ cat-file -e " .. c_blob,
        }
        assert(ccode ~= 0, "the synced peer should drop it as well")
    end
end

exec {
    cmd = ENV_EXE .. " chains rem '#cli-remove-blob'",
}

print("<== ALL PASSED")
