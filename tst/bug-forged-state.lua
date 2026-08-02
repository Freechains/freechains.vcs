#!/usr/bin/env lua5.4

-- A `state` commit carries `.freechains/state/`, but the receiver never
-- checks that what it carries matches what a replay actually computes.
--
-- `commit` (sync.lua) validates a state commit with ONE check:
--
--     assert(kind == 'state')
--     local mx = PEAKS(parents(hash))
--     if PEAK(hash) ~= mx then ... end     <- only `now.lua`
--
-- `authors.lua`, `posts.lua` and `order.lua` are never compared. The
-- mode check allows A|M on all four paths, so a forged state commit is
-- well-formed and passes straight through.
--
-- The full comparison DOES exist, but only on the fast-forward path:
--
--     write(G_rem); git diff --quiet HEAD -- .freechains/state/
--         -> "chain sync : remote state mismatch"
--
-- On the DIVERGE path there is no comparison at all. The forged values
-- are ignored for the merge -- `G_fst` is recomputed -- but the commit
-- is accepted into shared history. That is the hole: `G_oct` is later
-- loaded straight out of a commit tree,
--
--     G_oct = { authors = F(".freechains/state/authors.lua"), ... }
--
-- so once a forged state commit sits at or below a future fork point,
-- its invented reputations become the basis for replay AND for the
-- consensus that decides which branch wins.
--
-- This test forges the simplest version: A hands itself the reputation
-- cap. The fix is to compare the recomputed state against the commit's
-- tree in `commit`, on every path, not just on fast-forward.

require "tests"

local ROOT_A = ROOT .. "/bug-forged-state/A/"
local ROOT_X = ROOT .. "/bug-forged-state/X/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_X  = ENV .. " ../src/freechains.lua --root " .. ROOT_X

local REPO_A = ROOT_A .. "chains/#fs/"

exec {
    cmd = "mkdir -p " .. ROOT_A,
}
exec {
    cmd = "mkdir -p " .. ROOT_X,
}

do
    print("==> Test: forged state commit is refused on the diverge path")

    -- A: G -- seed[K1]
    TEST "A creates chain + seeds s.txt"
    exec {
        cmd = EXE_A .. " --now=1000 chains add '#fs' init file " .. GEN_2,
    }
    exec {
        cmd = EXE_A .. " --now=1020 chain '#fs' post inline 'seed\n' --file s.txt --sign " .. KEY1,
    }

    TEST "X clones fs"
    exec {
        cmd = EXE_X .. " chains add '#fs' clone " .. REPO_A,
    }

    -- both sides advance, so the recv takes the DIVERGE path and not the
    -- fast-forward one (which already catches this via `write`+`diff`)
    TEST "A posts alpha"
    exec {
        cmd = EXE_A .. " --now=1100 chain '#fs' post inline 'alpha\n' --file a.txt --sign " .. KEY1,
    }

    TEST "X posts beta (branches diverge)"
    exec {
        cmd = EXE_X .. " --now=1100 chain '#fs' post inline 'beta\n' --file b.txt --sign " .. KEY2,
    }

    -- A: ... -- alpha -- FORGED    (K1 hands itself the reputation cap)
    TEST "A hand-forges a state commit granting K1 the reps cap"
    do
        local f = assert(io.open(REPO_A .. ".freechains/state/authors.lua", "w"))
        f:write("return {\n    ['" .. PUB1 .. "'] = { reps=30000, time=1020 },\n}\n")
        f:close()
    end
    exec {
        cmd = "git -C " .. REPO_A .. " add .freechains/state/",
    }
    exec {
        cmd = "GIT_AUTHOR_DATE='@1120 +0000' GIT_COMMITTER_DATE='@1120 +0000'" ..
            " git -C " .. REPO_A .. " commit -q -m '(empty message)'" ..
            " --trailer 'Freechains: state' --no-gpg-sign",
    }

    TEST "the forgery is well-formed: real trailer, only state/ touched"
    do
        assert(TRAILER(REPO_A, "HEAD") == "state", "expected a state trailer")
        local out = exec {
            cmd = "git -C " .. REPO_A ..
                " diff-tree --cc --no-commit-id -r --name-status HEAD",
        }
        assert(
            out:match("^M%s+%.freechains/state/authors%.lua$"),
            "expected exactly one modified state file, got: " .. out
        )
    end

    TEST "the forged reps are NOT what a replay computes"
    do
        -- K1 spent 1 rep per post (2 posts) from GEN_2's 15, so anything
        -- near the 30000 cap can only have been invented
        local n = REPS(EXE_A, "#fs", PUB1)
        assert(n == 30, "expected the forged cap (30), got " .. tostring(n))
    end

    TEST "X recvs A: the forged state commit must be refused"
    do
        local err = FAIL {
            cmd = EXE_X .. " --now=1200 chain '#fs' sync recv " .. REPO_A,
        }
        assert(
            err:find("invalid state", 1, true),
            "expected an invalid-state refusal, got: " .. tostring(err)
        )
    end

    TEST "X is untouched (2 entries: seed + beta)"
    do
        local out = exec {
            cmd = EXE_X .. " chain '#fs' list order",
        }
        local n = 0
        for _ in out:gmatch("[^\n]+") do n = n + 1 end
        assert(n == 2, "expected 2 entries, got " .. n)
    end

    TEST "X did not absorb the invented reputation"
    do
        local n = REPS(EXE_X, "#fs", PUB1)
        assert(n ~= 30, "X absorbed the forged cap")
    end
end

-- Same forgery, but INTERIOR: capped with an honestly-computed state
-- commit on top. A check that only compares the branch TIP passes here,
-- because the tip is correct -- yet the forged commit is still in shared
-- history, and `octopus` sits BELOW every fork, so it is exactly the
-- kind of commit a later sync loads as `G_oct`.
--
-- This is the case that separates "compare after the replay" from
-- "compare at every commit on the first-climbed path".
do
    print("==> Test: forged state commit is refused mid-branch too")

    local ROOT_C = ROOT .. "/bug-forged-state/C/"
    local ROOT_Y = ROOT .. "/bug-forged-state/Y/"
    local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C
    local EXE_Y  = ENV .. " ../src/freechains.lua --root " .. ROOT_Y
    local REPO_C = ROOT_C .. "chains/#fi/"

    exec {
        cmd = "mkdir -p " .. ROOT_C,
    }
    exec {
        cmd = "mkdir -p " .. ROOT_Y,
    }

    TEST "C creates chain + seeds s.txt"
    exec {
        cmd = EXE_C .. " --now=1000 chains add '#fi' init file " .. GEN_2,
    }
    exec {
        cmd = EXE_C .. " --now=1020 chain '#fi' post inline 'seed\n' --file s.txt --sign " .. KEY1,
    }

    TEST "Y clones fi"
    exec {
        cmd = EXE_Y .. " chains add '#fi' clone " .. REPO_C,
    }

    TEST "C posts alpha"
    exec {
        cmd = EXE_C .. " --now=1100 chain '#fi' post inline 'alpha\n' --file a.txt --sign " .. KEY1,
    }

    TEST "Y posts beta (branches diverge)"
    exec {
        cmd = EXE_Y .. " --now=1100 chain '#fi' post inline 'beta\n' --file b.txt --sign " .. KEY2,
    }

    TEST "C hand-forges an INTERIOR state commit"
    do
        local f = assert(io.open(REPO_C .. ".freechains/state/authors.lua", "w"))
        f:write("return {\n    ['" .. PUB1 .. "'] = { reps=30000, time=1020 },\n}\n")
        f:close()
    end
    exec {
        cmd = "git -C " .. REPO_C .. " add .freechains/state/",
    }
    exec {
        cmd = "GIT_AUTHOR_DATE='@1120 +0000' GIT_COMMITTER_DATE='@1120 +0000'" ..
            " git -C " .. REPO_C .. " commit -q -m '(empty message)'" ..
            " --trailer 'Freechains: state' --no-gpg-sign",
    }
    local forged = exec {
        cmd = "git -C " .. REPO_C .. " rev-parse HEAD",
    }

    -- cap it: restore the honest state and commit that on top, so the
    -- BRANCH TIP is correct and only the interior commit lies
    TEST "C caps it with an honestly-computed state commit"
    exec {
        cmd = "git -C " .. REPO_C .. " checkout " .. forged ..
            "~1 -- .freechains/state/authors.lua",
    }
    exec {
        cmd = "GIT_AUTHOR_DATE='@1140 +0000' GIT_COMMITTER_DATE='@1140 +0000'" ..
            " git -C " .. REPO_C .. " commit -q -m '(empty message)'" ..
            " --trailer 'Freechains: state' --no-gpg-sign",
    }

    TEST "the branch TIP is honest (a tip-only check would pass)"
    do
        local tip = exec {
            cmd = "git -C " .. REPO_C .. " show HEAD:.freechains/state/authors.lua",
        }
        local good = exec {
            cmd = "git -C " .. REPO_C .. " show " .. forged ..
                "~1:.freechains/state/authors.lua",
        }
        assert(tip == good, "tip should carry the honest state")
        assert(not tip:match("30000"), "tip should not carry the forgery")
    end

    TEST "the forged commit is still there, mid-branch"
    do
        local out = exec {
            cmd = "git -C " .. REPO_C .. " show " .. forged ..
                ":.freechains/state/authors.lua",
        }
        assert(out:match("30000"), "interior commit should carry the forgery")
    end

    TEST "Y recvs C: the interior forgery must be refused"
    do
        local err = FAIL {
            cmd = EXE_Y .. " --now=1200 chain '#fi' sync recv " .. REPO_C,
        }
        assert(
            err:find("invalid state", 1, true),
            "expected an invalid-state refusal, got: " .. tostring(err)
        )
    end

    TEST "Y is untouched (2 entries: seed + beta)"
    do
        local out = exec {
            cmd = EXE_Y .. " chain '#fi' list order",
        }
        local n = 0
        for _ in out:gmatch("[^\n]+") do n = n + 1 end
        assert(n == 2, "expected 2 entries, got " .. n)
    end
end

print("<== ALL PASSED")
