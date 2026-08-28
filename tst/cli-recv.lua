#!/usr/bin/env lua5.4

require "tests"
local ssh = require "freechains.chain.ssh"

local ROOT_A = ROOT .. "/cli-recv/A/"
local ROOT_B = ROOT .. "/cli-recv/B/"
local ROOT_C = ROOT .. "/cli-recv/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"
local REPO_C = ROOT_C .. "/chains/test/"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_B,
}
exec {
    cmd = "mkdir -p " .. ROOT_C,
}

-- 1. recv basic (fetch + merge)
do
    print("==> Step 1: recv basic")

    do
        TEST "A creates chain + posts"
        exec {
            cmd = EXE_A .. " --now=1000 chains add /test init " .. GEN_1,
        }
        local out = exec {
            cmd = EXE_A .. " --now=2000 chain /test post inline 'post from A' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)

        TEST "B clones"
        exec {
            cmd = EXE_B .. " chains add /test clone " .. REPO_A,
        }
    end
    -- A:  genesis ── [post] P1
    -- B:  genesis ── [post] P1

    do
        TEST "A posts again"
        local out = exec {
            cmd = EXE_A .. " --now=3000 chain /test post inline 'second from A' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)

        TEST "pubkey matches pioneer key"
        local hash = exec {
            cmd = "git -C " .. REPO_A .. " rev-parse HEAD~1",
        }
        local pk = ssh.verify(REPO_A, hash)
        assert(pk == PUB1, "pubkey mismatch: [" .. tostring(pk) .. "] vs [" .. PUB1 .. "]")
    end
    -- A:  genesis ── [post] P1 ── [post] P2
    -- B:  genesis ── [post] P1

    do
        TEST "B recvs from A"
        exec {
            cmd = EXE_B .. " --now=3500 chain /test sync recv " .. REPO_A,
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
    end
    -- A:  genesis ── [post] P1 ── [post] P2
    -- B:  genesis ── [post] P1 ── [post] P2
end

-- 2. recv bidirectional
do
    print("==> Step 2: recv bidirectional")

    do
        TEST "A posts"
        local out = exec {
            cmd = EXE_A .. " --now=4000 chain /test post inline 'third from A' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)

        TEST "B recvs from A"
        exec {
            cmd = EXE_B .. " --now=4500 chain /test sync recv " .. REPO_A,
        }
    end
    -- A:  genesis ── P1 ── P2 ── [post] P3
    -- B:  genesis ── P1 ── P2 ── [post] P3

    do
        TEST "B posts"
        local out = exec {
            cmd = EXE_B .. " --now=5000 chain /test post inline 'first from B' --sign " .. KEY1,
        }
        assert(#out == 40, "hash: " .. out)

        TEST "A recvs from B"
        exec {
            cmd = EXE_A .. " --now=5500 chain /test sync recv " .. REPO_B,
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

-- 3. recv divergent + consensus
do
    print("==> Step 3: recv divergent")

    local A, B

    -- A,B posts independently
    do
        TEST "A posts (diverge)"
        A = exec {
            cmd = EXE_A .. " --now=6000 chain /test post inline 'fourth from A' --sign " .. KEY1,
        }
        assert(#A == 40, "hash: " .. A)

        TEST "B posts (diverge)"
        B = exec {
            cmd = EXE_B .. " --now=7000 chain /test post inline 'second from B' --sign " .. KEY1,
        }
        assert(#B == 40, "hash: " .. B)
    end
    -- A:  genesis ── ... ── P4 ── [post] P5
    -- B:  genesis ── ... ── P4 ── [post] P6

    -- A <-- B
    do
        TEST "A recvs from B"
        exec {
            cmd = EXE_A .. " --now=7500 chain /test sync recv " .. REPO_B,
        }

        TEST "only actions carry dates (merges/genesis stay @0)"
        local out = exec { trim=false,
            cmd = "git -C " .. REPO_A .. " log --format='%at %s'",
        }
        for l in out:gmatch("[^\n]+") do
            local ts, subj = l:match("^(%d+) ?(.*)$")
            if subj == "" then
                assert(tonumber(ts) == 0, "merge dated: " .. l)
            elseif subj:match("^post") or subj:match("^like")
                or subj:match("^revoke") then
                assert(tonumber(ts) ~= 0, "undated action: " .. l)
            end
            -- anything else: the genesis (dated @0, own message)
        end

        TEST "A has both payloads"
        local pa = exec {
            cmd = EXE_A .. " chain /test get payload " .. A,
        }
        local pb = exec {
            cmd = EXE_A .. " chain /test get payload " .. B,
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
            cmd = EXE_B .. " --now=7500 chain /test sync recv " .. REPO_A,
        }

        TEST "B has both payloads"
        local pa = exec {
            cmd = EXE_B .. " chain /test get payload " .. A,
        }
        local pb = exec {
            cmd = EXE_B .. " chain /test get payload " .. B,
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

-- 4. recv with like
do
    print("==> Step 4: recv like")

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
                cmd = EXE_A .. " --now=8000 chain /test reps author '" .. PUB1 .. "'",
            })),
            post = tonumber((exec {
                cmd = EXE_A .. " --now=8000 chain /test reps action " .. A,
            })),
        }
        assert(bef.author==49500, "bef.author expected 49500, got " .. bef.author)
        assert(bef.post  == 0, "bef.post expected 0, got " .. bef.post)

        exec {
            cmd = EXE_A .. " --now=8000 chain /test like 5000 action " .. A .. " --sign " .. KEY1,
        }

        local aft = {
            author = tonumber((exec {
                cmd = EXE_A .. " --now=8000 chain /test reps author '" .. PUB1 .. "'",
            })),
            post = tonumber((exec {
                cmd = EXE_A .. " --now=8000 chain /test reps action " .. A,
            })),
        }
        assert(aft.author == 47250, "aft.author expected 47250, got " .. aft.author)
        assert(aft.post   == 2250,  "aft.post expected 2250, got " .. aft.post)

        TEST "B recvs from A (with like)"
        exec {
            cmd = EXE_B .. " --now=8500 chain /test sync recv " .. REPO_A,
        }

        TEST "B reflects like"
        local b = {
            author = tonumber((exec {
                cmd = EXE_B .. " --now=8500 chain /test reps author '" .. PUB1 .. "'",
            })),
            post = tonumber((exec {
                cmd = EXE_B .. " --now=8500 chain /test reps action " .. A,
            })),
        }
        assert(b.author == aft.author, "author reps: A=" .. aft.author .. " B=" .. b.author)
        assert(b.post   == aft.post,   "post reps: A=" .. aft.post .. " B=" .. b.post)
    end
end

-- 5. recv unrelated histories
do
    print("==> Step 5: recv unrelated histories")

    TEST "C creates independent chain"
    exec {
        cmd = EXE_C .. " --now=1000 chains add /test init " .. GEN_1,
    }
    exec {
        cmd = EXE_C .. " --now=2000 chain /test post inline 'post from C' --sign " .. KEY1,
    }

    TEST "B's HEAD before recv"
    local before = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }

    TEST "B recvs from C fails with unrelated histories"
    FAIL {
        cmd = EXE_B .. " --now=9000 chain /test sync recv " .. REPO_C,
        err = "ERROR : chain sync : incompatible genesis",
    }

    TEST "B's HEAD unchanged"
    local after = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }
    assert(before == after, "B's HEAD changed: " .. before .. " vs " .. after)
end

-- 6. recv action commit smuggling an extra file
do
    print("==> Step 6: recv action commit with extra file")

    TEST "A commits an action file plus a smuggled file"
    local f = io.open(REPO_A .. "/smuggle.lua", "w")
    f:write("return { action='post' }\n")
    f:close()
    local aid = exec {
        cmd = "git -C " .. REPO_A .. " hash-object smuggle.lua",
    }
    os.remove(REPO_A .. "smuggle.lua")
    COMMIT(REPO_A, {
        files = {
            ["actions/" .. aid:sub(1,2) .. "/" .. aid .. ".lua"]
                = "return { action='post' }\n",
            ["evil2.txt"] = "smuggled\n",
        },
    })

    TEST "B's HEAD before recv"
    local before = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }

    TEST "B recvs from A fails with mode violation"
    local err = FAIL {
        cmd = EXE_B .. " --now=10000 chain /test sync recv " .. REPO_A,
    }
    assert(err and err:match("malformed commit : unexpected tree"), "should fail: " .. tostring(err))

    TEST "B's HEAD unchanged"
    local after = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }
    assert(before == after,
        "B's HEAD changed: " .. before .. " vs " .. after
    )
end

-- 7. recv commit that is not an action
do
    print("==> Step 7: recv non-action commit")

    TEST "A resets to last good state (B's HEAD)"
    local b_head = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }
    exec {
        cmd = "git -C " .. REPO_A .. " update-ref HEAD " .. b_head,
    }

    TEST "A commits a junk file"
    COMMIT(REPO_A, {
        files = { ["evil.txt"] = "smuggled\n" },
    })

    TEST "B's HEAD before recv"
    local before = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }

    TEST "B recvs from A fails with not an action"
    local err = FAIL {
        cmd = EXE_B .. " --now=11000 chain /test sync recv " .. REPO_A,
    }
    assert(err and err:match("malformed commit : unexpected tree"), "should fail: " .. tostring(err))

    TEST "B's HEAD unchanged"
    local after = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }
    assert(before == after,
        "B's HEAD changed: " .. before .. " vs " .. after
    )
end

-- 8. recv action file whose name is not its own hash
do
    print("==> Step 8: recv forged action path")

    TEST "A resets to last good state (B's HEAD)"
    local b_head = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }
    exec {
        cmd = "git -C " .. REPO_A .. " update-ref HEAD " .. b_head,
    }

    TEST "A commits a forged action path"
    local fake = string.rep("ab", 20)
    COMMIT(REPO_A, {
        files = {
            ["actions/" .. fake:sub(1,2) .. "/" .. fake .. ".lua"]
                = "return { action='post' }\n",
        },
    })

    TEST "B's HEAD before recv"
    local before = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }

    TEST "B recvs from A fails with invalid action file"
    local err = FAIL {
        cmd = EXE_B .. " --now=12000 chain /test sync recv " .. REPO_A,
    }
    assert(err and err:match("malformed commit : unexpected tree"), "should fail: " .. tostring(err))

    TEST "B's HEAD unchanged"
    local after = exec {
        cmd = "git -C " .. REPO_B .. " rev-parse HEAD",
    }
    assert(before == after,
        "B's HEAD changed: " .. before .. " vs " .. after
    )
end

print("<== ALL PASSED")
