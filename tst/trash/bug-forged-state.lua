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
        cmd = EXE_A .. " --now=1000 chains add '#fs' init " .. GEN_2,
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
        cmd = EXE_C .. " --now=1000 chains add '#fi' init " .. GEN_2,
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
    -- dates pinned to @1100, same as `now.lua`: a stealthy forger
    -- matches them, or `PEAKS = max(%at, now)` trips the NEXT commit's
    -- `now` check on the forged `%at` (accidental catch, not a check
    -- on the forged values)
    exec {
        cmd = "GIT_AUTHOR_DATE='@1100 +0000' GIT_COMMITTER_DATE='@1100 +0000'" ..
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

-- Same forgery again, but reachable ONLY through a merge SIDE.
--
-- A beg is a real side branch: two commits parked on refs/begs/ until a
-- positive `like` merges them into `main` as parent 2. Forge the beg's
-- `state` commit and every check that walks the DAG in replay order
-- misses it -- `meet` cannot compare either side of a merge against the
-- replay, because a side's tree is relative to a baseline the replay
-- never had. The tip stays honest too: `like -X ours` keeps our state
-- files, so the invented reps never reach `main`'s state.
--
-- Ignored as a record, alive as an anchor: `octopus` sits BELOW every
-- fork, so this is precisely the kind of commit a later sync loads as
-- `G_oct`.
--
-- Context-free verification has nothing to miss here. The set is
-- `rev-list <tip>`, which yields side branches like any other commit,
-- and the link is checked against the commit's OWN parent.
do
    print("==> Test: forged state commit is refused on a merge side")

    local ROOT_E = ROOT .. "/bug-forged-state/E/"
    local ROOT_Z = ROOT .. "/bug-forged-state/Z/"
    local EXE_E  = ENV .. " ../src/freechains.lua --root " .. ROOT_E
    local EXE_Z  = ENV .. " ../src/freechains.lua --root " .. ROOT_Z
    local REPO_E = ROOT_E .. "chains/#ms/"

    exec {
        cmd = "mkdir -p " .. ROOT_E,
    }
    exec {
        cmd = "mkdir -p " .. ROOT_Z,
    }

    TEST "E creates chain + seeds s.txt"
    exec {
        cmd = EXE_E .. " --now=1000 chains add '#ms' init " .. GEN_1,
    }
    exec {
        cmd = EXE_E .. " --now=1020 chain '#ms' post inline 'seed\n' --file s.txt --sign " .. KEY1,
    }

    TEST "Z clones ms"
    exec {
        cmd = EXE_Z .. " chains add '#ms' clone " .. REPO_E,
    }

    -- E:  G ── seed ── S            refs/begs/beg-BEG -> BEG
    --                  └── [beg] P ── [state] BEG
    TEST "E creates a beg (K2 has no reps)"
    local BEG = exec {
        cmd = EXE_E .. " --now=1100 chain '#ms' post inline 'please\n' --file p.txt --beg --sign " .. KEY2,
    }

    -- amend, not append: the beg branch must stay exactly two commits,
    -- because `chain like` reads the beg post at `ref~1`
    TEST "E forges the beg's state commit, granting K1 the reps cap"
    do
        local ref = "refs/begs/beg-" .. BEG
        exec {
            cmd = "git -C " .. REPO_E .. " checkout -q --detach " .. ref,
        }
        local f = assert(io.open(REPO_E .. ".freechains/state/authors.lua", "w"))
        f:write("return {\n    ['" .. PUB1 .. "'] = { reps=30000, time=1020 },\n}\n")
        f:close()
        exec {
            cmd = "git -C " .. REPO_E .. " add .freechains/state/",
        }
        exec {
            cmd = "GIT_AUTHOR_DATE='@1100 +0000' GIT_COMMITTER_DATE='@1100 +0000'" ..
                " git -C " .. REPO_E .. " commit -q --amend --no-edit --no-gpg-sign",
        }
        exec {
            cmd = "git -C " .. REPO_E .. " update-ref " .. ref .. " HEAD",
        }
        exec {
            cmd = "git -C " .. REPO_E .. " checkout -q main",
        }
    end
    local forged = exec {
        cmd = "git -C " .. REPO_E .. " rev-parse refs/begs/beg-" .. BEG,
    }

    TEST "E likes the beg: the forgery merges into main as parent 2"
    exec {
        cmd = EXE_E .. " --now=1200 chain '#ms' like 1 post " .. BEG .. " --sign " .. KEY1,
    }

    TEST "the forgery is in main's history"
    do
        local ok = exec { stderr=false, err=false,
            cmd = "git -C " .. REPO_E .. " merge-base --is-ancestor " ..
                forged .. " main",
        }
        assert(ok, "forged commit should be an ancestor of main")
        local out = exec {
            cmd = "git -C " .. REPO_E .. " show " .. forged ..
                ":.freechains/state/authors.lua",
        }
        assert(out:match("30000"), "forged commit should carry the forgery")
    end

    TEST "but only through a merge SIDE (not on the first-parent path)"
    do
        local out = exec {
            cmd = "git -C " .. REPO_E .. " rev-list --first-parent main",
        }
        assert(not out:find(forged, 1, true), "should be off the first-parent path")
    end

    TEST "main's TIP is honest: `-X ours` kept our state files"
    do
        local tip = exec {
            cmd = "git -C " .. REPO_E .. " show main:.freechains/state/authors.lua",
        }
        assert(not tip:match("30000"), "tip should not carry the forgery")
    end

    TEST "Z recvs E: the side-branch forgery must be refused"
    do
        local err = FAIL {
            cmd = EXE_Z .. " --now=1250 chain '#ms' sync recv " .. REPO_E,
        }
        assert(
            err:find("invalid state", 1, true),
            "expected an invalid-state refusal, got: " .. tostring(err)
        )
    end

    TEST "Z is untouched (1 entry: seed)"
    do
        local out = exec {
            cmd = EXE_Z .. " chain '#ms' list order",
        }
        local n = 0
        for _ in out:gmatch("[^\n]+") do n = n + 1 end
        assert(n == 1, "expected 1 entry, got " .. n)
    end
end

-- Same forgery, but delivered by CLONE. `chains add clone` validates
-- nothing at all: the whole history is accepted verbatim, so the
-- invented reputation is the victim's state from the very first read.
-- No diverge, no merge, no sync -- just a copy. This is the base case:
-- every later sync is incremental on top of what clone accepted.
do
    print("==> Test: forged state commit is refused on clone")

    local ROOT_F = ROOT .. "/bug-forged-state/F/"
    local ROOT_W = ROOT .. "/bug-forged-state/W/"
    local EXE_F  = ENV .. " ../src/freechains.lua --root " .. ROOT_F
    local EXE_W  = ENV .. " ../src/freechains.lua --root " .. ROOT_W
    local REPO_F = ROOT_F .. "chains/#fc/"

    exec {
        cmd = "mkdir -p " .. ROOT_F,
    }
    exec {
        cmd = "mkdir -p " .. ROOT_W,
    }

    TEST "F creates chain + seeds s.txt"
    exec {
        cmd = EXE_F .. " --now=1000 chains add '#fc' init " .. GEN_2,
    }
    exec {
        cmd = EXE_F .. " --now=1020 chain '#fc' post inline 'seed\n' --file s.txt --sign " .. KEY1,
    }

    TEST "F hand-forges a state commit granting K1 the reps cap"
    do
        local f = assert(io.open(REPO_F .. ".freechains/state/authors.lua", "w"))
        f:write("return {\n    ['" .. PUB1 .. "'] = { reps=30000, time=1020 },\n}\n")
        f:close()
    end
    exec {
        cmd = "git -C " .. REPO_F .. " add .freechains/state/",
    }
    exec {
        cmd = "GIT_AUTHOR_DATE='@1040 +0000' GIT_COMMITTER_DATE='@1040 +0000'" ..
            " git -C " .. REPO_F .. " commit -q -m '(empty message)'" ..
            " --trailer 'Freechains: state' --no-gpg-sign",
    }

    TEST "the forged reps are NOT what a replay computes"
    do
        local n = REPS(EXE_F, "#fc", PUB1)
        assert(n == 30, "expected the forged cap (30), got " .. tostring(n))
    end

    TEST "W clones F: the forged history must be refused"
    do
        local err = FAIL {
            cmd = EXE_W .. " chains add '#fc' clone " .. REPO_F,
        }
        assert(
            err:find("invalid state", 1, true),
            "expected an invalid-state refusal, got: " .. tostring(err)
        )
    end

    TEST "W keeps no chain behind (clone rolled back)"
    exec {
        cmd = "test ! -d " .. ROOT_W .. "chains/#fc",
    }
end

print("<== ALL PASSED")
