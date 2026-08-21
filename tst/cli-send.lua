#!/usr/bin/env lua5.4

require "tests"
local ssh = require "freechains.chain.ssh"

local ROOT_A = ROOT .. "/cli-send/A/"
local ROOT_B = ROOT .. "/cli-send/B/"
local ROOT_C = ROOT .. "/cli-send/C/"
local ROOT_X = ROOT .. "/cli-send/X/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C
local EXE_X  = ENV .. " ../src/freechains.lua --root " .. ROOT_X

local REPO_A = ROOT_A .. "/chains/#test/"
local REPO_B = ROOT_B .. "/chains/#test/"
local REPO_C = ROOT_C .. "/chains/#test/"
local REPO_X = ROOT_X .. "/chains/#test/"


exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}
exec {
    cmd = "mkdir -p " .. ROOT_C,
}
exec {
    cmd = "mkdir -p " .. ROOT_X,
}

-- 1. create/clone + pre-receive hook installed + rejects non-main
do
    print("==> Step 1: create/clone + pre-receive hook")

    TEST "A creates chain"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#test' init " .. GEN_1,
    }

    TEST "B clones"
    exec {
        cmd = EXE_B .. " chains add '#test' clone " .. REPO_A,
    }

    TEST "A has executable pre-receive hook"
    local _, ok = exec { err=false,
        cmd = "test -x " .. REPO_A .. "hooks/pre-receive",
    }
    assert(ok == 0, "A hook missing or not executable")

    TEST "B has executable pre-receive hook"
    local _, ok = exec { err=false,
        cmd = "test -x " .. REPO_B .. "hooks/pre-receive",
    }
    assert(ok == 0, "B hook missing or not executable")

    TEST "reject push to refs/heads/hack"
    local err = FAIL {
        cmd = "git -C " .. REPO_A .. " push " .. REPO_B .. " main:refs/heads/hack",
    }
    assert (
        err and err:find("ERROR : chain sync : unexpected ref : refs/heads/hack"),
        "refs/heads/hack : unexpected stderr: " .. tostring(err)
    )

    TEST "reject push to refs/tags/v1"
    local err = FAIL {
        cmd = "git -C " .. REPO_A .. " push " .. REPO_B .. " main:refs/tags/v1",
    }
    assert (
        err and err:find("ERROR : chain sync : unexpected ref : refs/tags/v1"),
        "refs/tags/v1 : unexpected stderr: " .. tostring(err)
    )

    TEST "refs/begs/foo without freechains option -> missing option"
    local err = FAIL {
        cmd = "git -C " .. REPO_A .. " push " .. REPO_B .. " main:refs/begs/foo",
    }
    assert (
        err and err:find("ERROR : chain sync : missing freechains push option"),
        "refs/begs/foo : unexpected stderr: " .. tostring(err)
    )

    TEST "reject multi-ref push with unexpected refs"
    local err = FAIL {
        cmd = "git -C " .. REPO_A .. " push " .. REPO_B .. " main:refs/heads/alpha main:refs/heads/beta",
    }
    assert (
        err and err:find("ERROR : chain sync : unexpected ref : refs/heads/alpha")
            or err:find("ERROR : chain sync : unexpected ref : refs/heads/beta"),
        "multi-ref : unexpected stderr: " .. tostring(err)
    )

    -- temp commit on A so next pushes trigger the hook
    COMMIT(REPO_A, { msg = "tmp" })

    TEST "reject push without freechains option"
    local err = FAIL {
        cmd = "git -C " .. REPO_A .. " push " .. REPO_B .. " main",
    }
    assert (
        err and err:find("ERROR : chain sync : missing freechains push option"),
        "no freechains option : unexpected stderr: " .. tostring(err)
    )

    TEST "reject push without url option"
    local err = FAIL {
        cmd = "git -C " .. REPO_A .. " push -o freechains=true " .. REPO_B .. " main",
    }
    assert (
        err and err:find("ERROR : chain sync : missing url push option"),
        "no url option : unexpected stderr: " .. tostring(err)
    )

    -- drop the temp commit
    exec {
        cmd = "git -C " .. REPO_A .. " update-ref HEAD HEAD~1",
    }

    TEST "accept main:main no-op"
    exec {
        cmd = "git -C " .. REPO_A .. " push -o freechains=true -o url=" .. REPO_A .. " " .. REPO_B .. " main:refs/heads/main",
    }
end

-- 2. send rejects like from author with insufficient reputation
--    (based on tst/err-like.lua lines 268-308)
do
    print("==> Step 2: send rejects like with insufficient reps")

    TEST "X clones from A"
    exec {
        cmd = EXE_X .. " chains add '#test' clone " .. REPO_A,
    }

    TEST "X crafts malicious like signed by non-pioneer (0 reps)"
    local now = 1500
    COMMIT(REPO_X, {
        msg  = 'like 1000\nauthor ' .. PUB1 .. '\n',
        date = now,
        sign = KEY3,
    })

    TEST "X sends to B: push should be rejected"
    local err = FAIL {
        cmd = EXE_X .. " chain '#test' sync send " .. REPO_B,
    }
    assert(err and err:find("ERROR : chain sync : invalid like : insufficient reputation"), "send should fail: " .. tostring(err))
end

-- 3. A send after 1st post
do
    print("==> Step 3: A send after 1st post")

    TEST "A posts"
    local out = exec {
        cmd = EXE_A .. " --now=2000 chain '#test' post inline 'post from A' --sign " .. KEY1,
    }
    assert(#out == 40, "hash: " .. out)
    -- A:  genesis ── [post] P1
    -- B:  genesis

    TEST "A sends to B"
    exec {
        cmd = EXE_A .. " --now=2500 chain '#test' sync send " .. REPO_B,
    }

    TEST "B has A's latest post"
    local A = exec {
        cmd = "git -C " .. REPO_A .. " rev-parse HEAD",
    }
    local B = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }
    assert (A == B,
        "heads should be equal: " .. A .. " vs " .. B
    )
    -- A:  genesis ── [post] P1
    -- B:  genesis ── [post] P1
end

-- 4. send bidirectional
do
    print("==> Step 4: send bidirectional")

    do
        TEST "A posts"
        local out = exec {
            cmd = EXE_A .. " --now=4000 chain '#test' post inline 'third from A' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)

        TEST "A sends to B"
        exec {
            cmd = EXE_A .. " --now=4500 chain '#test' sync send " .. REPO_B,
        }
    end
    -- A:  genesis ── P1 ── P2 ── [post] P3
    -- B:  genesis ── P1 ── P2 ── [post] P3

    do
        TEST "B posts"
        local out = exec {
            cmd = EXE_B .. " --now=5000 chain '#test' post inline 'first from B' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)

        TEST "B sends to A"
        exec {
            cmd = EXE_B .. " --now=5500 chain '#test' sync send " .. REPO_A,
        }
    end
    -- A:  genesis ── ... ── P3 ── [post] P4
    -- B:  genesis ── ... ── P3 ── [post] P4

    do
        TEST "A and B are equal"
        local ok = (TREE(REPO_A) == TREE(REPO_B)) and 0 or 1
        assert(ok == 0, "A and B should not differ")
    end
    -- A:  genesis ── ... ── P3 ── [post] P4
    -- B:  genesis ── ... ── P3 ── [post] P4
end

-- 5. recv divergent + consensus
do
    print("==> Step 5: recv divergent")

    local A, B

    -- A,B posts independently
    do
        TEST "A posts (diverge)"
        A = exec {
            cmd = EXE_A .. " --now=6000 chain '#test' post inline 'fourth from A' --sign " .. KEY1,
        }
        assert(#A == 40, "hash: " .. A)

        TEST "B posts (diverge)"
        B = exec {
            cmd = EXE_B .. " --now=7000 chain '#test' post inline 'second from B' --sign " .. KEY1,
        }
        assert(#B == 40, "hash: " .. B)
    end
    -- A:  genesis ── ... ── P4 ── [post] P5
    -- B:  genesis ── ... ── P4 ── [post] P6

    -- A <-- B
    do
        TEST "A recvs from B"
        exec {
            cmd = EXE_A .. " --now=7500 chain '#test' sync recv " .. REPO_B,
        }

        TEST "no wall-clock timestamps"
        local out = exec {
            cmd = "git -C " .. REPO_A .. " log --format=%at",
        }
        for ts in out:gmatch("%d+") do
            assert(tonumber(ts) <= 10000, "wall-clock leak: " .. ts)
        end

        TEST "A has both payloads"
        local pa = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. A,
        }
        local pb = exec {
            cmd = EXE_A .. " chain '#test' get payload " .. B,
        }
        assert(pa == "fourth from A", "A's payload missing")
        assert(pb == "second from B", "B's payload missing")

        TEST "A's snapshot has both actions"
        local acts = STATE(REPO_A).actions
        assert(acts[A], "A's should be in actions")
        assert(acts[B], "B's should be in actions")
    end
    --                             ┌── [post] P5
    -- A:  genesis ── ... ── P4 ── [merge]
    --                             └── [post] P6
    -- B:  genesis ── ... ── P4 ── [post] P6

    -- B <-- A
    do
        TEST "B recvs from A"
        exec {
            cmd = EXE_B .. " --now=7500 chain '#test' sync recv " .. REPO_A,
        }

        TEST "B has both payloads"
        local pa = exec {
            cmd = EXE_B .. " chain '#test' get payload " .. A,
        }
        local pb = exec {
            cmd = EXE_B .. " chain '#test' get payload " .. B,
        }
        assert(pa == "fourth from A", "A's payload missing in B")
        assert(pb == "second from B", "B's payload missing in B")

        TEST "A and B have same authors"
        local aa = STATE(REPO_A).authors
        local ab = STATE(REPO_B).authors
        for k, v in pairs(aa) do
            assert(ab[k], "author missing in B: " .. k)
            assert(ab[k].reps == v.reps, "reps mismatch for " .. k)
        end

        TEST "A and B have same actions"
        local pa = STATE(REPO_A).actions
        local pb = STATE(REPO_B).actions
        for k, v in pairs(pa) do
            assert(pb[k], "action missing in B: " .. k)
            assert(pb[k].maturity == v.maturity, "maturity mismatch for " .. k)
        end
        for k, v in pairs(pb) do
            assert(pa[k], "action missing in A: " .. k)
        end

        TEST "A and B are bit-equal"
        local ok = (TREE(REPO_A) == TREE(REPO_B)) and 0 or 1
        assert(ok == 0, "A and B should not differ")
    end
    --                             ┌── [post] P5
    -- A:  genesis ── ... ── P4 ── [merge]
    --                             └── [post] P6
    -- B:  same as A (FF recv)
end

-- 6. recv with like
do
    print("==> Step 6: recv like")

    local A
    do
        local acts = STATE(REPO_A).actions
        for k, v in pairs(acts) do
            if v.action == 'post' then
                A = k
                break
            end
        end
        assert(A, "need a post aid from previous steps")
    end

    do
        TEST "A likes a post"

        local bef = {
            author = tonumber((exec {
                cmd = EXE_A .. " --now=8000 chain '#test' reps author '" .. PUB1 .. "'",
            })),
            post = tonumber((exec {
                cmd = EXE_A .. " --now=8000 chain '#test' reps action " .. A,
            })),
        }
        assert(bef.author==49500, "bef.author expected 49500, got " .. bef.author)
        assert(bef.post  == 0, "bef.post expected 0, got " .. bef.post)

        exec {
            cmd = EXE_A .. " --now=8000 chain '#test' like 5000 action " .. A .. " --sign " .. KEY1,
        }

        local aft = {
            author = tonumber((exec {
                cmd = EXE_A .. " --now=8000 chain '#test' reps author '" .. PUB1 .. "'",
            })),
            post = tonumber((exec {
                cmd = EXE_A .. " --now=8000 chain '#test' reps action " .. A,
            })),
        }
        assert(aft.author == 47250, "aft.author expected 47250, got " .. aft.author)
        assert(aft.post   == 2250,  "aft.post expected 2250, got " .. aft.post)

        TEST "B recvs from A (with like)"
        exec {
            cmd = EXE_B .. " --now=8500 chain '#test' sync recv " .. REPO_A,
        }

        TEST "B reflects like"
        local b = {
            author = tonumber((exec {
                cmd = EXE_B .. " --now=8500 chain '#test' reps author '" .. PUB1 .. "'",
            })),
            post = tonumber((exec {
                cmd = EXE_B .. " --now=8500 chain '#test' reps action " .. A,
            })),
        }
        assert(b.author == aft.author, "author reps: A=" .. aft.author .. " B=" .. b.author)
        assert(b.post   == aft.post,   "post reps: A=" .. aft.post .. " B=" .. b.post)
    end
end

-- 7. recv unrelated histories
do
    print("==> Step 7: recv unrelated histories")

    TEST "C creates independent chain"
    exec {
        cmd = EXE_C .. " --now=1000 chains add '#test' init " .. GEN_1,
    }
    exec {
        cmd = EXE_C .. " --now=2000 chain '#test' post inline 'post from C' --sign " .. KEY1,
    }

    TEST "B's HEAD before recv"
    local before = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }

    TEST "B recvs from C fails with unrelated histories"
    FAIL {
        cmd = EXE_B .. " --now=9000 chain '#test' sync recv " .. REPO_C,
        err = "ERROR : chain sync : incompatible genesis",
    }

    TEST "B's HEAD unchanged"
    local after = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }
    assert(before == after, "B's HEAD changed: " .. before .. " vs " .. after)
end

-- 8. divergent send pins commit dates (send forwards --now to recv)
do
    print("==> Step 8: divergent send timestamp")

    TEST "A posts (diverge)"
    exec {
        cmd = EXE_A .. " --now=9500 chain '#test' post inline 'diverge A' --sign " .. KEY1,
    }

    TEST "B posts (diverge)"
    exec {
        cmd = EXE_B .. " --now=9600 chain '#test' post inline 'diverge B' --sign " .. KEY1,
    }

    -- A,B diverge; A sends to B -> B's hook runs recv with the
    -- forwarded --now, so B's case-4 state commit (sync.lua:490)
    -- is pinned, not dated by wall clock
    TEST "A sends to B (divergent -> B merges)"
    exec {
        cmd = EXE_A .. " --now=9700 chain '#test' sync send " .. REPO_B,
    }

    TEST "B has no wall-clock timestamps"
    local out = exec {
        cmd = "git -C " .. REPO_B .. " log --format=%at",
    }
    for ts in out:gmatch("%d+") do
        assert(tonumber(ts) <= 10000, "wall-clock leak: " .. ts)
    end
end

print("<== ALL PASSED")
