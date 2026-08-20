#!/usr/bin/env lua5.4

-- git as the replication layer: fetches and DRY-RUN merges probe the
-- substrate directly (no HEAD move), while actual convergence goes
-- through `sync recv` (state lives in local snapshots, so a raw
-- merge alone cannot produce an operable replica)

require "tests"

local ROOT_A = ROOT .. "/repl-local-head/A/"
local ROOT_B = ROOT .. "/repl-local-head/B/"
local ROOT_C = ROOT .. "/repl-local-head/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C

local REPO_A = ROOT_A .. "/chains/#test/"
local REPO_B = ROOT_B .. "/chains/#test/"
local REPO_C = ROOT_C .. "/chains/#test/"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}
exec {
    cmd = "mkdir -p " .. ROOT_C,
}

-- HOST A: create chain + post
local CHAIN_HASH
local P1

do
    print("==> Host A: create chain + post")

    do
        TEST "chain created"
        CHAIN_HASH = exec {
            cmd = EXE_A .. " chains add '#test' init " .. GEN_1,
        }
        assert(#CHAIN_HASH == 41, "hash: " .. CHAIN_HASH)
        assert(CHAIN_HASH:match("^#%x+$"), "not hex")
    end

    do
        TEST "post on A"
        P1 = exec {
            cmd = EXE_A .. " chain '#test' post inline 'post from A' --sign " .. KEY1,
        }
        assert(#P1 == 40, "hash: " .. P1)
        assert(P1:match("^%x+$"), "not hex")
    end
end

local P2

do
    print("==> Host B: clone chain + post")

    do
        TEST "clone succeeds"
        exec {
            cmd = EXE_B .. " chains add '#test' clone " .. REPO_A,
        }
    end

    do
        TEST "B has same genesis"
        local gen_a = exec {
            cmd = "git -C " .. REPO_A .. " rev-list --max-parents=0 HEAD",
        }
        local gen_b = exec {
            cmd = "git -C " .. REPO_B .. " rev-list --max-parents=0 HEAD",
        }
        assert(gen_a == gen_b, "genesis mismatch")
    end

    do
        TEST "B has 2 commits (genesis + post)"
        local count = exec {
            cmd = "git -C " .. REPO_B .. " rev-list --count HEAD",
        }
        assert(count == "2", "count: " .. count)
    end

    do
        TEST "post on B"
        P2 = exec {
            cmd = EXE_B .. " chain '#test' post inline 'post from B' --sign " .. KEY1,
        }
        assert(#P2 == 40, "hash: " .. P2)
        assert(P2:match("^%x+$"), "not hex")
    end

    do
        TEST "B has 3 commits (genesis + A post + B post)"
        local count = exec {
            cmd = "git -C " .. REPO_B .. " rev-list --count HEAD",
        }
        assert(count == "3", "count: " .. count)
    end
end

-- HOST A: raw fetch probes the substrate, recv converges
do
    print("==> Host A: fetch from B + recv")

    do
        TEST "fetch from B"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " fetch " .. REPO_B .. " main",
        }
        assert(code == 0, "fetch failed")

        TEST "dry-run merge ok"
        assert(DRYMERGE(REPO_A, "FETCH_HEAD"), "dry-run merge failed")

        TEST "A recvs from B (fast-forward)"
        exec {
            cmd = EXE_A .. " chain '#test' sync recv " .. REPO_B,
        }
    end

    do
        TEST "A has 3 commits (fast-forward)"
        local count = exec {
            cmd = "git -C " .. REPO_A .. " rev-list --count HEAD",
        }
        assert(count == "3", "count: " .. count)
    end

    do
        TEST "both payloads present in A"
        local pa = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. P1,
        }
        local pb = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. P2,
        }
        assert(pa == "post from A", "A's post missing")
        assert(pb == "post from B", "B's post missing")
    end

    do
        TEST "A and B are equal"
        local ok = (TREE(REPO_A) == TREE(REPO_B)) and 0 or 1
        assert(ok==0, "A and B differ")
    end
end

-- BIDIRECTIONAL SYNC: both post, A recvs B, B recvs A
do
    print("==> Bidirectional sync")

    do
        TEST "A posts again"
        local out = exec {
            cmd = EXE_A .. " chain '#test' post inline 'second from A' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)

        TEST "B posts again"
        local out = exec {
            cmd = EXE_B .. " chain '#test' post inline 'second from B' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "A fetches from B"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " fetch " .. REPO_B .. " main",
        }
        assert(code == 0, "fetch failed")

        TEST "A dry-run merge ok"
        assert(DRYMERGE(REPO_A, "FETCH_HEAD"), "dry-run merge failed")

        TEST "A recvs B (true merge)"
        exec {
            cmd = EXE_A .. " chain '#test' sync recv " .. REPO_B,
        }

        TEST "A has 6 commits (3 shared + 2 posts + merge)"
        local count = exec {
            cmd = "git -C " .. REPO_A .. " rev-list --count HEAD",
        }
        assert(count == "6", "count: " .. count)
    end

    do
        TEST "B recvs A (fast-forward)"
        exec {
            cmd = EXE_B .. " chain '#test' sync recv " .. REPO_A,
        }

        TEST "B has 6 commits"
        local count = exec {
            cmd = "git -C " .. REPO_B .. " rev-list --count HEAD",
        }
        assert(count == "6", "count: " .. count)
    end

    do
        TEST "A and B are equal after bidirectional sync"
        local ok = (TREE(REPO_A) == TREE(REPO_B)) and 0 or 1
        assert(ok == 0, "A and B differ")
    end
end

-- UNRELATED HISTORIES: independent chain creation must fail sync
do
    print("==> Unrelated histories rejected")

    local h = exec {
        cmd = EXE_C .. " chains add '#test' init " .. GEN_1,
    }
    assert(h ~= CHAIN_HASH, "should differ")

    do
        TEST "fetch from unrelated chain succeeds"
        local _, code = exec {
            cmd = "git -C " .. REPO_C .. " fetch " .. REPO_A .. " main",
        }
        assert(code == 0, "fetch should succeed")

        TEST "dry-run merge from unrelated chain fails"
        assert(not DRYMERGE(REPO_C, "FETCH_HEAD"), "merge should fail")
    end
end

-- NO CONFLICT: payloads live outside the tree, so concurrent posts
-- can never collide on a path (the old shared-file conflict is gone)
do
    print("==> Concurrent posts do not conflict")

    local PA, PB

    do
        TEST "A posts concurrently"
        PA = exec {
            cmd = EXE_A .. " chain '#test' post" .. " inline 'from A\n' --sign " .. KEY1,
        }
        assert(#PA == 40, "hash: " .. PA)
    end

    do
        TEST "B posts concurrently"
        PB = exec {
            cmd = EXE_B .. " chain '#test' post" .. " inline 'from B\n' --sign " .. KEY1,
        }
        assert(#PB == 40, "hash: " .. PB)
    end

    do
        TEST "fetch succeeds"
        local _, code = exec {
            cmd = "git -C " .. REPO_A .. " fetch " .. REPO_B .. " main",
        }
        assert(code == 0, "fetch should succeed")

        TEST "dry-run merge succeeds (no shared paths)"
        assert(DRYMERGE(REPO_A, "FETCH_HEAD"), "merge should not conflict")

        TEST "A recvs B (converges)"
        exec {
            cmd = EXE_A .. " chain '#test' sync recv " .. REPO_B,
        }
    end

    do
        TEST "A holds both concurrent payloads"
        local pa = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. PA,
        }
        local pb = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. PB,
        }
        assert(pa == "from A", "A's payload missing")
        assert(pb == "from B", "B's payload missing")
    end
end

print("<== ALL PASSED")
