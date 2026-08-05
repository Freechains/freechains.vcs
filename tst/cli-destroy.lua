#!/usr/bin/env lua5.4

-- `chain destroy <hash>` destroys `hash` and everything after it, the only
-- escape from a hard fork: abandon the diverging branch, receive the
-- settled one, repost on top of it.
--
-- Every post/like is TWO commits: the content one (whose hash the CLI
-- prints) and the `state` one that follows it, holding the state files.
-- A post is always committed on top of a valid tip, so `destroy` lands on
-- the PARENT of `hash`, and only a post/like/revoke may be named.
--
-- 1. Drop posts
--
--              G
--              |
--            p1[K1]
--              |
--            p2[K1]        <-- destroy target, destroyed
--              |
--            p3[K1]        <-- destroyed
--
-- State reverts with the tree, so the destroyed posts never happened: the
-- reps they spent come back and the repost is charged just once.
--
-- 2. Errors and begs
--
--              G ------------ b0[K2], b2[K2]   (beg refs, outside main)
--              |
--            p1[K1] -------- b1[K2]
--
-- A beg is a post with nothing after it, so `destroy b2` just deletes its
-- ref and leaves `main` alone.
-- `destroy p1` lands on G, so b1 can no longer attach to main and its ref
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
-- After `destroy a1`, A holds no exclusive history left to protect, so
-- the recv is a plain fast-forward and the repost lands on top:
--
--            seed[K1]
--               |
--            beta[K2]
--               |
--            a3[K1]                      (repost of a1: new hash)

require "tests"

local DIR1 = ROOT .. "/chains/#cli-destroy-1/"
local DIR2 = ROOT .. "/chains/#cli-destroy-2/"

local WEEK = 7 * 24 * 60 * 60

local ROOT_A = ROOT .. "/cli-destroy/A/"
local ROOT_B = ROOT .. "/cli-destroy/B/"
local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B

-- 1. Drop local posts back to a previous one
do
    print("==> Test 1: destroy removes posts")

    -- G
    TEST "create chain"
    exec {
        cmd = ENV_EXE .. " chains add '#cli-destroy-1' init file " .. GEN_1,
    }

    -- G -- p1[K1]
    TEST "post p1"
    local p1 = exec {
        cmd = ENV_EXE .. " chain '#cli-destroy-1' post inline 'p1\n' --file p1.txt --sign " .. KEY1,
    }
    local at_p1 = REPS(ENV_EXE, "#cli-destroy-1", PUB1)

    -- G -- p1[K1] -- p2[K1]
    TEST "post p2"
    local p2 = exec {
        cmd = ENV_EXE .. " chain '#cli-destroy-1' post inline 'p2\n' --file p2.txt --sign " .. KEY1,
    }
    local at_p2 = REPS(ENV_EXE, "#cli-destroy-1", PUB1)

    -- G -- p1[K1] -- p2[K1] -- p3[K1]
    TEST "post p3"
    local p3 = exec {
        cmd = ENV_EXE .. " chain '#cli-destroy-1' post inline 'p3\n' --file p3.txt --sign " .. KEY1,
    }

    -- G -- p1[K1]                         (p2, p3 destroyed)
    do
        TEST "destroy lists every destroyed post"
        local out = exec {
            cmd = ENV_EXE .. " chain '#cli-destroy-1' destroy " .. p2,
        }
        local T = {}
        for h in out:gmatch("[^\n]+") do
            T[#T+1] = h
        end
        assert(#T == 2, "expected 2 destroyed, got " .. #T)
        assert(T[1] == p2, "p2 should be destroyed first")
        assert(T[2] == p3, "p3 should be destroyed second")
    end

    do
        TEST "destroyed posts are out of the order"
        local O, S = ORDER(ENV_EXE, "#cli-destroy-1")
        assert(#O == 1, "expected 1 entry, got " .. #O)
        assert(O[1] == p1, "p1 should be the only entry")
        assert(not S[p2], "p2 must be gone")
        assert(not S[p3], "p3 must be gone")
    end

    do
        TEST "destroyed payloads are out of the tree"
        assert(io.open(DIR1 .. "p1.txt"), "p1.txt should remain")
        assert(not io.open(DIR1 .. "p2.txt"), "p2.txt should be gone")
        assert(not io.open(DIR1 .. "p3.txt"), "p3.txt should be gone")
    end

    -- `destroy` names the first post to remove, so it lands on its parent,
    -- which is the `state` commit accounting for p1
    do
        TEST "HEAD lands on the state commit of p1"
        local head = exec {
            cmd = "git -C " .. DIR1 .. " rev-parse HEAD",
        }
        assert(TRAILER(DIR1, head) == 'state', "HEAD is not a state commit")
        assert(head ~= p1, "HEAD should be past p1")
        local parent = exec {
            cmd = "git -C " .. DIR1 .. " rev-parse HEAD^1",
        }
        assert(parent == CID(p1, true, DIR1), "HEAD^1 should be p1: " .. parent)
    end

    -- state files revert with the tree: the destroyed posts never happened
    do
        TEST "reps are restored"
        local now = REPS(ENV_EXE, "#cli-destroy-1", PUB1)
        assert(now == at_p1, "expected " .. at_p1 .. " reps, got " .. now)
    end

    -- G -- p1[K1] -- p2'[K1]              (repost, new hash)
    local p2b
    do
        -- the repost is charged once, exactly like the original p2:
        -- the destroyed posts cost nothing, they never happened
        TEST "repost after destroy costs no extra reps"
        p2b = exec {
            cmd = ENV_EXE .. " chain '#cli-destroy-1' post inline 'p2\n' --file p2.txt --sign " .. KEY1,
        }
        local now = REPS(ENV_EXE, "#cli-destroy-1", PUB1)
        assert(now == at_p2, "expected " .. at_p2 .. " reps, got " .. now)
    end

    -- G -- p1[K1]                         (p2' destroyed again)
    do
        TEST "destroy the newest post removes just it"
        local out = exec {
            cmd = ENV_EXE .. " chain '#cli-destroy-1' destroy " .. p2b,
        }
        assert(out == p2b, "should list p2' alone: " .. out)
        local O = ORDER(ENV_EXE, "#cli-destroy-1")
        assert(#O == 1, "expected 1 entry, got " .. #O)
        assert(O[1] == p1, "p1 should be the only entry")
    end

    -- `state` commits are plumbing: they are not part of the protocol
    do
        TEST "state commit rejects"
        local head = exec {
            cmd = "git -C " .. DIR1 .. " rev-parse HEAD",
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-destroy-1' destroy " .. head,
            err = "ERROR : chain destroy : invalid hash",
        }
    end
end

-- 2. Errors and beg cleanup
do
    print("==> Test 2: errors and begs")

    -- G
    TEST "create chain"
    exec {
        cmd = ENV_EXE .. " chains add '#cli-destroy-2' init file " .. GEN_1,
    }
    local gen = exec {
        cmd = "git -C " .. DIR2 .. " rev-parse HEAD",
    }

    do
        TEST "unknown hash rejects"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-destroy-2' destroy nohash",
            err = "ERROR : chain destroy : invalid hash",
        }
    end

    -- the genesis is a `state` commit, and there is nothing before it
    do
        TEST "genesis rejects"
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-destroy-2' destroy " .. gen,
            err = "ERROR : chain destroy : invalid hash",
        }
    end

    -- G -- b0[K2]                         (beg: own ref, outside main)
    -- a beg lives on its own ref, outside `main`
    TEST "beg b0 off the genesis"
    local b0 = exec {
        cmd = ENV_EXE .. " chain '#cli-destroy-2' post inline 'b0\n' --file b0.txt --beg --sign " .. KEY2,
    }

    -- the ref points to the beg's `state` commit, which no ref names
    do
        TEST "hash outside main rejects"
        local ref = exec {
            cmd = "git -C " .. DIR2 .. " for-each-ref refs/begs/ --format='%(objectname)'",
        }
        FAIL {
            cmd = ENV_EXE .. " chain '#cli-destroy-2' destroy " .. ref,
            err = "ERROR : chain destroy : invalid hash",
        }
    end

    -- G -- b0[K2], b2[K2]                  (a second beg, to destroy alone)
    TEST "beg b2 off the genesis"
    local b2 = exec {
        cmd = ENV_EXE .. " chain '#cli-destroy-2' post inline 'b2\n' --file b2.txt --beg --sign " .. KEY2,
    }

    -- G -- b0[K2]                          (b2 destroyed: nothing follows)
    do
        TEST "destroy a beg deletes its ref alone"
        local head = exec {
            cmd = "git -C " .. DIR2 .. " rev-parse HEAD",
        }
        local out = exec {
            cmd = ENV_EXE .. " chain '#cli-destroy-2' destroy " .. b2,
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
        cmd = ENV_EXE .. " chain '#cli-destroy-2' post inline 'p1\n' --file p1.txt --sign " .. KEY1,
    }

    -- G -- p1[K1] -- b1[K2]
    -- b0 hangs off the genesis, b1 off p1: only b1 is orphaned below
    TEST "beg b1 off p1"
    local b1 = exec {
        cmd = ENV_EXE .. " chain '#cli-destroy-2' post inline 'b1\n' --file b1.txt --beg --sign " .. KEY2,
    }

    -- G                                    (p1 destroyed, b1 unattachable)
    do
        TEST "destroy removes only the orphaned beg"
        exec {
            cmd = ENV_EXE .. " chain '#cli-destroy-2' destroy " .. p1,
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

-- 3. Hard fork recovery: destroy, recv, repost, back in sync
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
        cmd = EXE_A .. " --now=1000 chains add '#destroy-fork' init file " .. GEN_2,
    }
    local seed = exec {
        cmd = EXE_A .. " --now=1100 chain '#destroy-fork' post inline 'seed\n' --file seed.txt --sign " .. KEY1,
    }

    -- A: G -- S      B: G -- S            (fork point = S, at t=1100)
    TEST "B clones destroy-fork"
    exec {
        cmd = EXE_B .. " chains add '#destroy-fork' clone " .. ROOT_A .. "/chains/#destroy-fork/",
    }

    -- A: G -- S -- a1[K1]                  (right after the fork)
    TEST "A posts a1, right after the fork"
    local a1 = exec {
        cmd = EXE_A .. " --now=1200 chain '#destroy-fork' post inline 'a1\n' --file a1.txt --sign " .. KEY1,
    }

    -- A: G -- S -- a1[K1] -- a2[K1]        (a1..a2 spans 7d: entrenched)
    TEST "A posts a2 7 days later: A's exclusive commits now span 7d"
    local a2 = exec {
        cmd = EXE_A .. " --now=" .. (1200+WEEK) .. " chain '#destroy-fork' post inline 'a2\n' --file a2.txt --sign " .. KEY1,
    }

    -- B: G -- S -- beta[K2]                (single post: no span)
    TEST "B posts beta"
    local beta = exec {
        cmd = EXE_B .. " --now=" .. (1200+WEEK) .. " chain '#destroy-fork' post inline 'beta\n' --file b.txt --sign " .. KEY2,
    }

    -- A is entrenched, so it refuses to reconcile with B at all
    TEST "A recvs from B: hard fork"
    FAIL {
        cmd = EXE_A .. " --now=" .. (1200+WEEK+100) .. " chain '#destroy-fork' sync recv " .. ROOT_B .. "/chains/#destroy-fork/",
        err = "ERROR : chain sync : hard fork",
    }

    -- A: G -- S                            (a1, a2 destroyed)
    TEST "A destroys from its first post after the fork"
    do
        local out = exec {
            cmd = EXE_A .. " chain '#destroy-fork' destroy " .. a1,
        }
        local T = {}
        for h in out:gmatch("[^\n]+") do
            T[#T+1] = h
        end
        assert(#T == 2, "expected 2 destroyed, got " .. #T)
        assert(T[1]==a1 and T[2]==a2, "a1 and a2 should be destroyed")
    end

    -- A: G -- S -- beta[K2]                (plain fast-forward)
    TEST "A recvs from B: accepted"
    exec {
        cmd = EXE_A .. " --now=" .. (1200+WEEK+200) .. " chain '#destroy-fork' sync recv " .. ROOT_B .. "/chains/#destroy-fork/",
    }

    TEST "A holds B's branch"
    do
        local O, S = ORDER(EXE_A, "#destroy-fork")
        assert(#O == 2, "expected 2 entries, got " .. #O)
        assert(O[1] == seed, "seed should be first")
        assert(O[2] == beta, "beta should be second")
    end

    -- A: G -- S -- beta[K2] -- a3[K1]      (a1 reposted: new hash)
    TEST "A reposts on top of the settled branch"
    local a3 = exec {
        cmd = EXE_A .. " --now=" .. (1200+WEEK+300) .. " chain '#destroy-fork' post inline 'a1\n' --file a1.txt --sign " .. KEY1,
    }
    assert(a3 ~= a1, "repost should be a new post")

    -- B: G -- S -- beta[K2] -- a3[K1]      (both peers converge)
    TEST "B recvs from A: back in sync"
    exec {
        cmd = EXE_B .. " --now=" .. (1200+WEEK+400) .. " chain '#destroy-fork' sync recv " .. ROOT_A .. "/chains/#destroy-fork/",
    }

    TEST "both peers agree on the order"
    do
        local OA = ORDER(EXE_A, "#destroy-fork")
        local OB = ORDER(EXE_B, "#destroy-fork")
        assert(#OA == 3, "expected 3 entries in A, got " .. #OA)
        assert(#OB == 3, "expected 3 entries in B, got " .. #OB)
        for i = 1, 3 do
            assert(OA[i] == OB[i], "order differs at " .. i)
        end
        assert(OA[3] == a3, "repost should be last")
    end
end

print("<== ALL PASSED")
