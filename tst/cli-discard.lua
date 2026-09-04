#!/usr/bin/env lua5.4

-- `chain discard <hash>` discards `hash` and everything after it, the only
-- escape from a hard fork: discard the diverging branch, receive the
-- settled one, repost on top of it.
--
-- Every post/like is ONE commit (whose hash the CLI prints); state
-- lives in local snapshots (`.git/states/`).
-- A post is always committed on top of a valid tip, so `discard` lands on
-- the PARENT of `hash`, and only a post/like/revoke may be named.
--
-- 1. Drop posts
--
--              G
--              |
--            p1[K1]
--              |
--            p2[K1]        <-- discard target, discarded
--              |
--            p3[K1]        <-- discarded
--
-- State reverts with the tree, so the discarded posts never happened: the
-- reps they spent come back and the repost is charged just once.
--
-- 2. Errors and begs
--
--              G ------------ b0[K2], b2[K2]   (beg refs, outside main)
--              |
--            p1[K1] -------- b1[K2]
--
-- A beg is a post with nothing after it, so `discard b2` just deletes its
-- ref and leaves `main` alone.
-- `discard p1` lands on G, so b1 can no longer attach to main and its ref
-- goes with it, while b0 still hangs off G and is kept.
--
-- 3. Hard fork recovery
--
-- GEN_2: KEY1=15, KEY2=15. A entrenches its own branch by spanning 7
-- days (a1..a2), so it REFUSES to reconcile with B.
--
--            seed[K1]
--             /    \
--       a1[K1]      beta[K2]
--          |
--       a2[K1] @+7d                      A: entrenched, recv refused
--
-- After `discard a1`, A holds no exclusive history left to protect, so
-- the recv is a plain fast-forward and the repost lands on top:
--
--            seed[K1]
--               |
--            beta[K2]
--               |
--            a3[K1]                      (repost of a1: new hash)

require "tests"

local DIR1 = ROOT .. "/chains/cli-discard-1/"
local DIR2 = ROOT .. "/chains/cli-discard-2/"

local WEEK = 7 * 24 * 60 * 60

local ROOT_A = ROOT .. "/cli-discard/A/"
local ROOT_B = ROOT .. "/cli-discard/B/"
local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

-- 1. Drop local posts back to a previous one
do
    print("==> Test 1: discard removes posts")

    -- G
    TEST "create chain"
    exec {
        cmd = ENV_EXE .. " chains add /cli-discard-1 init " .. GEN_1,
    }

    -- G -- p1[K1]
    TEST "post p1"
    local p1 = exec {
        cmd = ENV_EXE .. " chain /cli-discard-1 post inline 'p1\n' --sign " .. KEY1,
    }
    local at_p1 = REPS(ENV_EXE, "/cli-discard-1", PUB1)

    -- G -- p1[K1] -- p2[K1]
    TEST "post p2"
    local p2 = exec {
        cmd = ENV_EXE .. " chain /cli-discard-1 post inline 'p2\n' --sign " .. KEY1,
    }
    local at_p2 = REPS(ENV_EXE, "/cli-discard-1", PUB1)

    -- G -- p1[K1] -- p2[K1] -- p3[K1]
    TEST "post p3"
    local p3 = exec {
        cmd = ENV_EXE .. " chain /cli-discard-1 post inline 'p3\n' --sign " .. KEY1,
    }

    -- capture p2's commit + its state blob BEFORE discard, to prove
    -- the state ref is dropped and the blob reclaimed
    local p2cid  = CID(DIR1, p2)
    local p1cid  = CID(DIR1, p1)
    local p2blob = exec {
        cmd = "git -C " .. DIR1 .. " rev-parse refs/states/" .. p2cid,
    }

    -- G -- p1[K1]                         (p2, p3 discarded)
    do
        TEST "discard lists every discarded post"
        local out = exec {
            cmd = ENV_EXE .. " chain /cli-discard-1 discard " .. p2,
        }
        local T = {}
        for h in out:gmatch("[^\n]+") do
            T[#T+1] = h
        end
        assert(#T == 2, "expected 2 discarded, got " .. #T)
        assert(T[1] == p2, "p2 should be discarded first")
        assert(T[2] == p3, "p3 should be discarded second")
    end

    do
        TEST "discarded payloads lose their anchor"
        -- the ref goes with the action: the blob is unreachable
        local _, code = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR1 .. " rev-parse refs/payloads/" .. p2,
        }
        assert(code ~= 0, "p2 payload ref should be gone")
        local _, code1 = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR1 .. " rev-parse refs/payloads/" .. p1,
        }
        assert(code1 == 0, "p1 payload ref should remain")

        TEST "discarded payloads stay readable until sweep"
        -- `get` is a DISK query: the discarded bytes are still on
        -- disk (unreferenced), so readable until the gc below
        local v = exec {
            cmd = ENV_EXE .. " chain /cli-discard-1 get payload " .. p2,
        }
        assert(v == "p2", "p2 still on disk before gc: " .. v)
    end

    do
        TEST "discarded commit loses its state ref, gc reclaims the blob"
        -- the dropped commit's refs/states anchor is gone
        local _, code = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR1 .. " rev-parse refs/states/" .. p2cid,
        }
        assert(code ~= 0, "p2 state ref should be gone")
        -- p1 (the kept tip) still has its state
        local _, code1 = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR1 .. " rev-parse refs/states/" .. p1cid,
        }
        assert(code1 == 0, "p1 state ref should remain")
        -- unanchored (not in any commit tree either), so gc reaps it
        exec {
            cmd = "git -C " .. DIR1 .. " gc --prune=now --quiet",
        }
        local _, gone = exec { err=false, stderr=false,
            cmd = "git -C " .. DIR1 .. " cat-file -e " .. p2blob,
        }
        assert(gone ~= 0, "p2 state blob should be reclaimed by gc")
    end

    do
        TEST "discarded posts are out of the order"
        local O, S = ORDER(ENV_EXE, "/cli-discard-1")
        assert(#O == 1, "expected 1 entry, got " .. #O)
        assert(O[1] == p1, "p1 should be the only entry")
        assert(not S[p2], "p2 must be gone")
        assert(not S[p3], "p3 must be gone")
    end

    do
        TEST "swept payloads are gone for good"
        -- the gc above reclaimed the discarded bytes: only now
        -- does `get` stop serving them
        local v = exec {
            cmd = ENV_EXE .. " chain /cli-discard-1 get payload " .. p1,
        }
        assert(v == "p1", "p1 payload should remain: " .. v)
        FAIL {
            cmd = ENV_EXE .. " chain /cli-discard-1 get payload " .. p2,
            err = "ERROR : chain get : unknown post",
        }
        FAIL {
            cmd = ENV_EXE .. " chain /cli-discard-1 get payload " .. p3,
            err = "ERROR : chain get : unknown post",
        }
    end

    -- `discard` names the first post to remove, so it lands on its
    -- parent, which is p1 itself
    do
        TEST "HEAD lands on p1"
        local head = exec {
            cmd = "git -C " .. DIR1 .. " rev-parse HEAD",
        }
        assert(head == CID(DIR1, p1), "HEAD should be p1: " .. head)
    end

    -- state reverts with the snapshot: the discarded posts never happened
    do
        TEST "reps are restored"
        local now = REPS(ENV_EXE, "/cli-discard-1", PUB1)
        assert(now == at_p1, "expected " .. at_p1 .. " reps, got " .. now)
    end

    -- G -- p1[K1] -- p2'[K1]              (repost, new hash)
    local p2b
    do
        -- the repost is charged once, exactly like the original p2:
        -- the discarded posts cost nothing, they never happened
        TEST "repost after discard costs no extra reps"
        p2b = exec {
            cmd = ENV_EXE .. " chain /cli-discard-1 post inline 'p2\n' --sign " .. KEY1,
        }
        local now = REPS(ENV_EXE, "/cli-discard-1", PUB1)
        assert(now == at_p2, "expected " .. at_p2 .. " reps, got " .. now)
    end

    -- G -- p1[K1]                         (p2' discarded again)
    do
        TEST "discard the newest post removes just it (SHORT id)"
        -- ids may be abbreviated, as `list dag` prints them
        local out = exec {
            cmd = ENV_EXE .. " chain /cli-discard-1 discard " .. p2b:sub(1, 7),
        }
        assert(out == p2b, "should list p2' in full: " .. out)
        local O = ORDER(ENV_EXE, "/cli-discard-1")
        assert(#O == 1, "expected 1 entry, got " .. #O)
        assert(O[1] == p1, "p1 should be the only entry")
    end

end

-- 2. Errors and beg cleanup
do
    print("==> Test 2: errors and begs")

    -- G
    TEST "create chain"
    exec {
        cmd = ENV_EXE .. " chains add /cli-discard-2 init " .. GEN_1,
    }
    local gen = exec {
        cmd = "git -C " .. DIR2 .. " rev-parse HEAD",
    }

    do
        TEST "unknown hash rejects"
        FAIL {
            cmd = ENV_EXE .. " chain /cli-discard-2 discard nohash",
            err = "ERROR : chain discard : invalid action",
        }
    end

    -- the genesis is plumbing, and there is nothing before it
    do
        TEST "genesis rejects"
        FAIL {
            cmd = ENV_EXE .. " chain /cli-discard-2 discard " .. gen,
            err = "ERROR : chain discard : invalid action",
        }
    end

    -- G -- b0[K2]                         (beg: own ref, outside main)
    -- a beg lives on its own ref, outside `main`
    TEST "beg b0 off the genesis"
    local b0 = exec {
        cmd = ENV_EXE .. " chain /cli-discard-2 post inline 'b0\n' --beg --sign " .. KEY2,
    }

    -- G -- b0[K2], b2[K2]                  (a second beg, to discard alone)
    TEST "beg b2 off the genesis"
    local b2 = exec {
        cmd = ENV_EXE .. " chain /cli-discard-2 post inline 'b2\n' --beg --sign " .. KEY2,
    }

    -- G -- b0[K2]                          (b2 discarded: nothing follows)
    do
        TEST "discard a beg deletes its ref alone"
        local head = exec {
            cmd = "git -C " .. DIR2 .. " rev-parse HEAD",
        }
        local out = exec {
            cmd = ENV_EXE .. " chain /cli-discard-2 discard " .. b2,
        }
        assert(out == b2, "should list b2 alone: " .. out)
        local now = exec {
            cmd = "git -C " .. DIR2 .. " rev-parse HEAD",
        }
        assert(now == head, "main should not move")
        local refs = exec {
            cmd = "git -C " .. DIR2 .. " for-each-ref refs/begs/ --format='%(refname)'",
        }
        assert(refs:match("beg%-" .. b0), "b0 should survive: " .. refs)
        assert(not refs:match("beg%-" .. b2), "b2 should be gone: " .. refs)
    end

    -- G -- p1[K1]                         (b0 still off G)
    TEST "post p1"
    local p1 = exec {
        cmd = ENV_EXE .. " chain /cli-discard-2 post inline 'p1\n' --sign " .. KEY1,
    }

    -- G -- p1[K1] -- b1[K2]
    -- b0 hangs off the genesis, b1 off p1: only b1 is orphaned below
    TEST "beg b1 off p1"
    local b1 = exec {
        cmd = ENV_EXE .. " chain /cli-discard-2 post inline 'b1\n' --beg --sign " .. KEY2,
    }

    -- G                                    (p1 discarded, b1 unattachable)
    do
        TEST "discard removes only the orphaned beg"
        exec {
            cmd = ENV_EXE .. " chain /cli-discard-2 discard " .. p1,
        }
        local head = exec {
            cmd = "git -C " .. DIR2 .. " rev-parse HEAD",
        }
        assert(head == gen, "HEAD should be the genesis: " .. head)
        local out = exec {
            cmd = "git -C " .. DIR2 .. " for-each-ref refs/begs/ --format='%(refname)'",
        }
        assert(out:match("beg%-" .. b0), "b0 should survive: " .. out)
        assert(not out:match("beg%-" .. b1), "b1 should be gone: " .. out)
    end
end

-- 3. Hard fork recovery: discard, recv, repost, back in sync
do
    print("==> Test 3: hard fork recovery")

    exec {
        cmd = "mkdir -p " .. ROOT_A,
    }
    exec {
        cmd = "mkdir -p " .. ROOT_B,
    }

    -- A: G -- S[K1]
    TEST "A creates chain + seeds seed.txt"
    exec {
        cmd = EXE_A .. " --now=1000 chains add /discard-fork init " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1100 chain /discard-fork post inline 'seed\n' --sign " .. KEY1,
    }

    -- A: G -- S      B: G -- S            (fork point = S, at t=1100)
    TEST "B clones discard-fork"
    exec {
        cmd = EXE_B .. " chains add /discard-fork clone " .. ROOT_A .. "/chains/discard-fork/",
    }

    -- A: G -- S -- a1[K1]                  (right after the fork)
    TEST "A posts a1, right after the fork"
    local a1 = exec {
        cmd = EXE_A .. " --now=1200 chain /discard-fork post inline 'a1\n' --sign " .. KEY1,
    }

    -- A: G -- S -- a1[K1] -- a2[K1]        (a1..a2 spans 7d: entrenched)
    TEST "A posts a2 7 days later: A's exclusive commits now span 7d"
    local a2 = exec {
        cmd = EXE_A .. " --now=" .. (1200+WEEK) .. " chain /discard-fork post inline 'a2\n' --sign " .. KEY1,
    }

    -- B: G -- S -- beta[K2]                (single post: no span)
    TEST "B posts beta"
    local beta = exec {
        cmd = EXE_B .. " --now=" .. (1200+WEEK) .. " chain /discard-fork post inline 'beta\n' --sign " .. KEY2,
    }

    -- A is entrenched, so it refuses to reconcile with B at all
    TEST "A recvs from B: hard fork"
    FAIL {
        cmd = EXE_A .. " --now=" .. (1200+WEEK+100) .. " chain /discard-fork sync recv " .. ROOT_B .. "/chains/discard-fork/",
        err = "ERROR : chain sync : hard fork",
    }

    -- A: G -- S                            (a1, a2 discarded)
    TEST "A discards from its first post after the fork"
    do
        local out = exec {
            cmd = EXE_A .. " chain /discard-fork discard " .. a1,
        }
        local T = {}
        for h in out:gmatch("[^\n]+") do
            T[#T+1] = h
        end
        assert(#T == 2, "expected 2 discarded, got " .. #T)
        assert(T[1]==a1 and T[2]==a2, "a1 and a2 should be discarded")
    end

    -- A: G -- S -- beta[K2]                (plain fast-forward)
    TEST "A recvs from B: accepted"
    exec {
        cmd = EXE_A .. " --now=" .. (1200+WEEK+200) .. " chain /discard-fork sync recv " .. ROOT_B .. "/chains/discard-fork/",
    }

    TEST "A holds B's branch"
    do
        local O, S = ORDER(EXE_A, "/discard-fork")
        assert(#O == 2, "expected 2 entries, got " .. #O)
        assert(O[1] == seed, "seed should be first")
        assert(O[2] == beta, "beta should be second")
    end

    -- A: G -- S -- beta[K2] -- a3[K1]      (a1 reposted: new hash)
    TEST "A reposts on top of the settled branch"
    local a3 = exec {
        cmd = EXE_A .. " --now=" .. (1200+WEEK+300) .. " chain /discard-fork post inline 'a1\n' --sign " .. KEY1,
    }
    assert(a3 ~= a1, "repost should be a new post")

    -- B: G -- S -- beta[K2] -- a3[K1]      (both peers converge)
    TEST "B recvs from A: back in sync"
    exec {
        cmd = EXE_B .. " --now=" .. (1200+WEEK+400) .. " chain /discard-fork sync recv " .. ROOT_A .. "/chains/discard-fork/",
    }

    TEST "both peers agree on the order"
    do
        local OA = ORDER(EXE_A, "/discard-fork")
        local OB = ORDER(EXE_B, "/discard-fork")
        assert(#OA == 3, "expected 3 entries in A, got " .. #OA)
        assert(#OB == 3, "expected 3 entries in B, got " .. #OB)
        for i = 1, 3 do
            assert(OA[i] == OB[i], "order differs at " .. i)
        end
        assert(OA[3] == a3, "repost should be last")
    end
end

print("<== ALL PASSED")
