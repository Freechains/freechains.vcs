#!/usr/bin/env lua5.4

require "tests"

-- Phase 2 of revocation (260721-remove-blob.md): honest peers
-- physically drop a REVOKED post's payload, not just hide it
-- (260721-revoke.md, Phase 1).
--
-- Removal is deferred to the end of a command (`revokes`,
-- common.lua).
--
-- BOTH channels destroy: `revokes` tests `is_revoked`, the same
-- predicate `get.lua` hides by. Transfer is two steps -- a filtered
-- pack, then the payloads by explicit hash -- so a peer holding a
-- removed payload can still serve, and a completed sync still leaves
-- the peer holding every live payload.

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

    TEST "community-unrevoke-refused-with-no-supplier"
    do
        -- no peer here holds a copy, and this node just dropped its own,
        -- so a plain unrevoke has nothing to restore from and the gate
        -- refuses. `--file` is the way back if someone kept one out of
        -- band (section below); if nobody did, the revoke is permanent
        -- -- decided, not a bug (reps.md, "Reversible on the SUMS").
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
    -- `chains add ... clone` still uses a plain `git clone`, which is
    -- unfiltered and so cannot onboard from a peer with a removed
    -- payload (260721-remove-blob.md open items). Cloning B before any
    -- removal sidesteps that; the filtered path is exercised by
    -- `sync recv` below and by the two-step section at the end.
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

do
    print("==> --file re-seeds a payload nobody serves any more")

    -- Once every honest peer has dropped a payload, no sync can bring it
    -- back -- there is no supplier left. `--file` is the way back: the
    -- caster hands over an out-of-band copy. Safe to accept from anyone
    -- BECAUSE it is content-addressed: only the exact bytes the DAG
    -- already names can hash to the hash it names.
    local POST = exec {
        cmd = ENV_EXE .. " chain '#cli-remove-blob' post inline 'precious' --sign " .. KEY1,
    }
    exec { cmd = "printf 'precious' > " .. TMP .. "/backup.txt" }
    exec { cmd = "printf 'tampered' > " .. TMP .. "/bad.txt" }

    exec {
        cmd = ENV_EXE .. " chain '#cli-remove-blob' revoke 1 " .. POST .. " --sign " .. KEY2,
    }

    TEST "file-refused-when-it-does-not-match"
    FAIL {
        cmd = ENV_EXE .. " chain '#cli-remove-blob' unrevoke 1 " .. POST ..
              " --sign " .. KEY2 .. " --file " .. TMP .. "/bad.txt",
        err = "ERROR : chain unrevoke : file does not match payload",
    }

    TEST "mismatched-file-never-enters-the-object-store"
    do
        local bad = exec { cmd = "git hash-object " .. TMP .. "/bad.txt" }
        local _, code = exec { err=false,
            cmd = "git -C " .. DIR .. " cat-file -e " .. bad,
        }
        assert(code ~= 0, "a rejected file must not be written")
    end

    TEST "file-restores-the-payload"
    do
        local out, code = exec {
            cmd = ENV_EXE .. " chain '#cli-remove-blob' unrevoke 1 " .. POST ..
                  " --sign " .. KEY2 .. " --file " .. TMP .. "/backup.txt",
        }
        assert(code == 0, "unrevoke with --file should succeed: " .. tostring(out))
        local pay, pcode = exec {
            cmd = ENV_EXE .. " chain '#cli-remove-blob' get payload " .. POST,
        }
        assert(pcode == 0 and pay == "precious", "payload should read again: " .. tostring(pay))
    end

    TEST "worktree-back-under-normal-management"
    do
        -- the path was skip-worktree'd when dropped; restoring clears
        -- that and materialises the file, so status stays clean
        local out = exec { cmd = "git -C " .. DIR .. " status --porcelain" }
        assert(out == "", "status should be clean: " .. out)
    end
end

do
    print("==> Two-step transfer: filtered pack, then payloads by hash")

    -- step 1 pulls commits+trees only (so a peer holding a removed
    -- payload can still serve), step 2 pulls the payloads themselves by
    -- explicit hash, in sequence, from that same peer. A completed sync
    -- therefore still leaves the peer holding every live payload --
    -- replication is unchanged, it just takes two round trips.
    local ROOT_X = ROOT .. "/two-step/X/"
    local ROOT_Y = ROOT .. "/two-step/Y/"
    local EXE_X  = "../src/freechains.lua --root " .. ROOT_X
    local EXE_Y  = "../src/freechains.lua --root " .. ROOT_Y
    exec { cmd = "mkdir -p " .. ROOT_X }
    exec { cmd = "mkdir -p " .. ROOT_Y }

    exec { cmd = EXE_X .. " chains add '#test' init file " .. GEN_3 }
    local DIR_X = ROOT_X .. "/chains/#test/"
    exec { cmd = EXE_Y .. " chains add '#test' clone " .. DIR_X }
    local DIR_Y = ROOT_Y .. "/chains/#test/"

    local A = exec {
        cmd = EXE_X .. " chain '#test' post inline 'alpha' --sign " .. KEY1,
    }
    local B = exec {
        cmd = EXE_X .. " chain '#test' post inline 'beta' --sign " .. KEY1,
    }

    TEST "sync-lands-every-payload"
    do
        local out, code = exec {
            cmd = EXE_Y .. " chain '#test' sync recv '" .. DIR_X .. "'",
        }
        assert(code == 0, "sync recv should succeed: " .. tostring(out))
        -- nothing deferred: step 2 already pulled what step 1 filtered out
        local miss = exec {
            cmd = "git -C " .. DIR_Y .. " rev-list --objects --all --missing=print"
                  .. " | grep -c '^?' || true",
        }
        assert(miss == "0", "peer should hold every object, missing: " .. miss)
        local pa = exec { cmd = EXE_Y .. " chain '#test' get payload " .. A }
        local pb = exec { cmd = EXE_Y .. " chain '#test' get payload " .. B }
        assert(pa == "alpha" and pb == "beta", "payloads: " .. pa .. "/" .. pb)
    end

    TEST "no-promisor-config-left-behind"
    do
        -- --filter registers the peer as a promisor remote, which would
        -- lazily re-fetch on any read -- including a read of something
        -- this node revoked on purpose. sync strips it.
        local out = exec {
            cmd = "git -C " .. DIR_Y .. " config --get-regexp"
                  .. " 'promisor|partialclone|extensions' || true",
        }
        assert(out == "", "promisor config should be stripped: " .. out)
    end
end

exec {
    cmd = ENV_EXE .. " chains rem '#cli-remove-blob'",
}

print("<== ALL PASSED")
