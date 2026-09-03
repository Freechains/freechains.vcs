#!/usr/bin/env lua5.4
require "tests"

exec {
    cmd = ENV_EXE .. " chains add /cli-reps init " .. GEN_1,
}

-- BASIC QUERY
do
    print("==> Basic query")

    do
        TEST "reps-pioneer-initial"
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }
        assert(code==0, "exit code: " .. tostring(code))
        assert(out=="50000", "reps: " .. out)
    end

    do
        -- cli.md "Keys:": a key file resolves to its pubkey
        TEST "reps-member-key-file forms agree"
        local pvt = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member " .. KEY1,
        }
        assert(pvt=="50000", "pvt path: " .. pvt)
        local pub = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member " .. KEY1 .. ".pub",
        }
        assert(pub=="50000", "pub path: " .. pub)
    end

    do
        TEST "reps-unknown-pubkey"
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB2 .. "'",
        }
        assert(code==0,  "exit code: " .. tostring(code))
        assert(out=="0", "reps: " .. out)
    end

    do
        TEST "reps-list-members"
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps members",
        }
        assert(code==0,         "exit code: " .. tostring(code))
        assert(out:find(PUB1, 1, true), "PUB1 not listed")
        assert(out:match("50000"), "50000 not in output")
    end

    do
        TEST "reps-list-posts-empty"
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps actions",
        }
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "", "should be empty: " .. out)
    end
end

-- AFTER POSTS
do
    print("==> After posts")

    do
        TEST "reps-after-1-post"
        exec {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'p1'" .. " --sign " .. KEY1,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(out == "49500", "reps: " .. out)    -- KEY1: 50000 -> post -> 49500
    end

    do
        TEST "reps-after-3-posts"
        exec {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'p2'" .. " --sign " .. KEY1,
        }
        exec {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'p3'" .. " --sign " .. KEY1,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "49500", "reps: " .. out)    -- KEY1: 50000 -> posts -> 49500 (discount refunds)
    end

    do
        TEST "reps-list-posts-after-3"
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps actions",
        }
        assert(code==0, "exit code: " .. tostring(code))
        -- 3 posts, all with 0 reps (no likes)
        local count = 0
        for _ in out:gmatch("[^\n]+") do count = count + 1 end
        assert(count == 3, "expected 3 posts, got: " .. count)
    end
end

exec {
    cmd = ENV_EXE .. " chains rem /cli-reps",
}

-- AFTER LIKE/DISLIKE
do
    print("==> After like/dislike")

    exec {
        cmd = ENV_EXE .. " chains add /cli-reps init " .. GEN_2,
    }

    do
        TEST "reps-liker-after-like"
        local post = exec {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'hello'" .. " --sign " .. KEY2,
        }
        exec {
            cmd = ENV_EXE .. " chain /cli-reps like 2000 action " .. post .. " --sign " .. KEY1,
        }

        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "23000", "reps: " .. out)    -- KEY1: 25000 -> like -> 23000

        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps action " .. post,
        }
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "900", "reps: " .. out)   -- post: 0 -> like 2000*90%/2 -> 900

        TEST "reps action accepts a SHORT id"
        -- ids are printed abbreviated (`list dag`): a prefix must
        -- resolve (ACTION.full), not silently miss G.actions
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps action " .. post:sub(1, 7),
        }
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "900", "short-id reps: " .. out)

        TEST "reps action of an UNKNOWN id is 0 (query semantics)"
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps action " .. string.rep("0", 40),
        }
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "0", "unknown reps: " .. out)
    end

    do
        TEST "reps-after-dislike"
        local post = exec {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'bad'" .. " --sign " .. KEY2,
        }
        exec {
            cmd = ENV_EXE .. " chain /cli-reps dislike 1000 action " .. post .. " --sign " .. KEY1,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }
        assert(code==0, "exit code: " .. tostring(code))
        assert(out == "22000", "reps: " .. out) -- KEY1: 25000 -> like -> 23000 -> dislike -> 22000
    end

    do
        TEST "reps-target-disliked"

        local target = exec {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'disliked'" .. " --sign " .. KEY2,
        }
        exec {
            cmd = ENV_EXE .. " chain /cli-reps dislike 1000 action " .. target .. " --sign " .. KEY1,
        }
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB2 .. "'",
        }
        assert(code == 0, "exit code: " .. tostring(code))
        -- KEY2: 25000 - 1500 (posts) + 900 (like) - 900 (dislikes)
        --       + 1000 (refunds) = 24500
        local n = tonumber(out)
        assert(n == 24500, "target should lose reps: " .. out)
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-reps",
    }
end

-- MULTI-PIONEER
do
    print("==> Multi-pioneer")

    do
        TEST "reps-2-pioneers"
        exec {
            cmd = ENV_EXE .. " chains add /cli-reps init " .. GEN_2,
        }
        local out1 = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }
        local out2 = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB2 .. "'",
        }
        assert(out1 == "25000", "KEY1 reps: " .. out1)
        assert(out2 == "25000", "KEY2 reps: " .. out2)
    end

    do
        TEST "reps-3-pioneers"
        exec {
            cmd = "rm -rf " .. TMP,
        }
        exec {
            cmd = "mkdir -p " .. ROOT,
        }
        exec {
            cmd = ENV_EXE .. " chains add /cr7 init " .. GEN_3,
        }
        local out = exec {
            cmd = ENV_EXE .. " chain /cr7 reps member '" .. PUB1 .. "'",
        }
        assert(out == "16666", "KEY1 reps: " .. out)
    end
end

-- GATE CHECK (Rule 4.a: >= cost to post)
do
    print("==> Gate check")

    exec {
        cmd = "rm -rf " .. TMP,
    }
    exec {
        cmd = "mkdir -p " .. ROOT,
    }
    exec {
        cmd = ENV_EXE .. " chains add /cli-reps init " .. GEN_1,
    }

    do
        TEST "gate-blocked-no-reps"
        -- KEY2 is not a pioneer, has 0 reps -> post must fail
        FAIL {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'blocked'" .. " --sign " .. KEY2,
            err = "ERROR : chain post : insufficient reputation",
        }
    end

    do
        TEST "gate-accepted-with-reps"
        -- KEY1 is pioneer at the cap -> post must succeed
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'accepted'" .. " --sign " .. KEY1,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "expected commit hash: " .. out)
    end

    do
        TEST "gate-unblocked-after-like"
        -- KEY1 likes KEY2 (member-targeted) to give reps, then KEY2 can post
        exec {
            cmd = ENV_EXE .. " chain /cli-reps like 1000 member '" .. PUB2 .. "'" .. " --sign " .. KEY1,
        }
        local out2 = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB2 .. "'",
        }
        -- one standard like (1000 -> 900) covers the 500 post cost
        assert(tonumber(out2) >= 500, "KEY2 should afford a post: " .. out2)

        local post, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'now ok'" .. " --sign " .. KEY2,
        }
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#post == 40, "expected commit hash: " .. post)
    end

    do
        TEST "gate-beg-with-reps-fails"
        -- KEY1 is pioneer with reps -> --beg must fail
        FAIL {
            cmd = ENV_EXE .. " chain /cli-reps post inline 'no beg needed'" .. " --sign " .. KEY1 .. " --beg",
            err = "ERROR : chain post : --beg error : member has sufficient reputation",
        }
    end

end

-- NO DEBT: gates are cost-quantized (posting costs `cost`, so
-- holding less than `cost` can neither post nor be sponsored
-- with dust). Times are pinned: the whole section lives at
-- now=0, except the maturity step at 12h
do
    print("==> No debt")

    exec {
        cmd = ENV_EXE .. " --now=0 chains add /no-debt init " .. GEN_1,
    }

    -- KEY1 grants KEY2 dust: 500 -> 90% -> 450 (below the 500 cost)
    exec {
        cmd = ENV_EXE .. " --now=0 chain /no-debt like 500 member '" .. PUB2 .. "' --sign " .. KEY1,
    }

    do
        TEST "dust-cannot-post"
        local out = exec {
            cmd = ENV_EXE .. " --now=0 chain /no-debt reps member '" .. PUB2 .. "'",
        }
        assert(out == "450", "KEY2 reps: " .. out)
        FAIL {
            cmd = ENV_EXE .. " --now=0 chain /no-debt post inline 'dust' --sign " .. KEY2,
            err = "ERROR : chain post : insufficient reputation",
        }
    end

    local BEG
    do
        TEST "dust-can-beg"
        -- the mirror gate: below `cost` one may still beg
        BEG = exec {
            cmd = ENV_EXE .. " --now=0 chain /no-debt post inline 'please' --beg --sign " .. KEY2,
        }
        assert(#BEG == 40, "beg: " .. BEG)
    end

    do
        TEST "dust-beg-like-rejected"
        -- admission mints future income: its price is not dust
        FAIL {
            cmd = ENV_EXE .. " --now=0 chain /no-debt like 499 action " .. BEG .. " --sign " .. KEY1,
            err = "ERROR : chain like : invalid number : expects at least 500",
        }
    end

    do
        TEST "beg-like admits the post, holds the member"
        -- the vote splits 50/50: 1000 -> 900 -> member 450, post 450
        exec {
            cmd = ENV_EXE .. " --now=0 chain /no-debt like 1000 action " .. BEG .. " --sign " .. KEY1,
        }
        local out = exec {
            cmd = ENV_EXE .. " --now=0 chain /no-debt reps member '" .. PUB2 .. "'",
        }
        assert(out == "900", "KEY2 reps: " .. out)   -- 450 + 450
        local post = exec {
            cmd = ENV_EXE .. " --now=0 chain /no-debt reps action " .. BEG,
        }
        assert(post == "450", "beg post reps: " .. post)
    end

    do
        TEST "beg-like on a ZERO member: still below the gate"
        -- KEY3 starts at 0: 450 < 500, so its first own post waits
        -- for the 12h refund (probation)
        local beg3 = exec {
            cmd = ENV_EXE .. " --now=0 chain /no-debt post inline 'me too' --beg --sign " .. KEY3,
        }
        exec {
            cmd = ENV_EXE .. " --now=0 chain /no-debt like 1000 action " .. beg3 .. " --sign " .. KEY1,
        }
        local out = exec {
            cmd = ENV_EXE .. " --now=0 chain /no-debt reps member '" .. PUB3 .. "'",
        }
        assert(out == "450", "KEY3 reps: " .. out)
        FAIL {
            cmd = ENV_EXE .. " --now=0 chain /no-debt post inline 'too soon' --sign " .. KEY3,
            err = "ERROR : chain post : insufficient reputation",
        }

        TEST "...and speaks after the 12h refund"
        local out = exec {
            cmd = ENV_EXE .. " --now=43200 chain /no-debt reps member '" .. PUB3 .. "'",
        }
        assert(tonumber(out) >= 500, "KEY3 after 12h: " .. out)
        local post, code = exec {
            cmd = ENV_EXE .. " --now=43200 chain /no-debt post inline 'matured' --sign " .. KEY3,
        }
        assert(code == 0, "matured member should post: " .. tostring(code))
        assert(#post == 40, "post: " .. post)
    end

    do
        TEST "reps-above-cost-cannot-beg"
        -- KEY2 holds 900 >= 500
        FAIL {
            cmd = ENV_EXE .. " --now=43200 chain /no-debt post inline 'no beg' --beg --sign " .. KEY2,
            err = "ERROR : chain post : --beg error : member has sufficient reputation",
        }
    end

    exec {
        cmd = ENV_EXE .. " chains rem /no-debt",
    }
end

-- WHITESPACE TRIM
do
    print("==> Whitespace trim")

    do
        TEST "reps-member-whitespace"
        local clean = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }
        local padded = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member ' " .. PUB1 .. " \n'",
        }
        assert(clean == padded, "trimmed lookup mismatch: " .. clean .. " vs " .. padded)
        assert(tonumber(clean) > 0, "expected non-zero reps: " .. clean)
    end

    do
        TEST "reps-post-whitespace"
        local posts = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps actions",
        }
        local hash = posts:match("(%x+)")
        assert(hash, "no post available")
        local clean = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps action " .. hash,
        }
        local padded = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps action ' " .. hash .. " \n'",
        }
        assert(clean == padded, "trimmed post lookup mismatch: " .. clean .. " vs " .. padded)
    end
end

-- ERROR PATHS
do
    print("==> Error paths")

    do
        TEST "reps-post-requires-hash"
        FAIL {
            cmd = ENV_EXE .. " chain /cli-reps reps action",
            err = "ERROR : chain reps : action requires id",
        }
    end

    do
        TEST "reps-member-requires-pubkey"
        FAIL {
            cmd = ENV_EXE .. " chain /cli-reps reps member",
            err = "ERROR : chain reps : member requires a pubkey",
        }
    end

    do
        TEST "reps-invalid-target"
        FAIL {
            cmd = ENV_EXE .. " chain /cli-reps reps foo",
            err = "ERROR : chain reps : invalid target : foo",
        }
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-reps",
    }
end

-- DEBT GATE (Rule 4.a: must afford the full vote magnitude)
do
    print("==> Debt gate")

    exec {
        cmd = "rm -rf " .. TMP,
    }
    exec {
        cmd = "mkdir -p " .. ROOT,
    }
    exec {
        cmd = ENV_EXE .. " chains add /cli-reps init " .. GEN_1,
    }
    -- KEY1 pioneer starts at the 50000 cap; a post to target
    local post = exec {
        cmd = ENV_EXE .. " chain /cli-reps post inline 'target' --sign " .. KEY1,
    }

    do
        TEST "debt-overspend-rejected"
        -- like 100000 is far beyond the 50000 cap -> always unaffordable
        local before = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }
        FAIL {
            cmd = ENV_EXE .. " chain /cli-reps like 100000 action " .. post .. " --sign " .. KEY1,
            err = "ERROR : chain like : insufficient reputation",
        }
        local after = exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }
        assert(before == after, "reps unchanged after rejected vote: " .. before .. " -> " .. after)
    end

    do
        TEST "debt-affordable-ok"
        local out, code = exec {
            cmd = ENV_EXE .. " chain /cli-reps like 1000 action " .. post .. " --sign " .. KEY1,
        }
        assert(code == 0, "affordable like should succeed: " .. tostring(code))
    end

    do
        TEST "debt-never-negative"
        local n = tonumber((exec {
            cmd = ENV_EXE .. " chain /cli-reps reps member '" .. PUB1 .. "'",
        }))
        assert(n >= 0, "reps must never go negative: " .. tostring(n))
    end

    exec {
        cmd = ENV_EXE .. " chains rem /cli-reps",
    }
end

print("<== ALL PASSED")
