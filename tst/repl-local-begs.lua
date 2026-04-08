#!/usr/bin/env lua5.4

require "tests"

local ROOT_A = ROOT .. "/repl-local-begs/A/"
local ROOT_B = ROOT .. "/repl-local-begs/B/"
local ROOT_C = ROOT .. "/repl-local-begs/C/"

local EXE_A  = ENV .. " ../src/freechains.lua --root " .. ROOT_A
local EXE_B  = ENV .. " ../src/freechains.lua --root " .. ROOT_B
local EXE_C  = ENV .. " ../src/freechains.lua --root " .. ROOT_C

local REPO_A = ROOT_A .. "/chains/test/"
local REPO_B = ROOT_B .. "/chains/test/"
local REPO_C = ROOT_C .. "/chains/test/"

exec("mkdir -p " .. ROOT_A)
exec("mkdir -p " .. ROOT_B)
exec("mkdir -p " .. ROOT_C)

-- HOST A: create chain + beg
local CHAIN_HASH

do
    print("==> Host A: create chain + beg")

    do
        TEST "chain created"
        CHAIN_HASH = exec (
            EXE_A .. " chains add test init " .. GEN_0
        )
        assert(#CHAIN_HASH == 40, "hash: " .. CHAIN_HASH)
        assert(CHAIN_HASH:match("^%x+$"), "not hex")
    end

    do
        TEST "beg on A"
        local out = exec (
            EXE_A .. " chain test post inline 'post from A' --beg"
        )
        assert(#out == 40, "hash: " .. out)
        assert(out:match("^%x+$"), "not hex")
    end
end

-- HOST B: clone chain + fetch begs + beg
do
    print("==> Host B: clone chain + fetch begs")

    do
        TEST "clone succeeds"
        exec (
            EXE_B .. " chains add test clone " .. REPO_A
        )
    end

    do
        TEST "B has same genesis"
        local gen_a = exec (
            "git -C " .. REPO_A .. " rev-list --max-parents=0 HEAD"
        )
        local gen_b = exec (
            "git -C " .. REPO_B .. " rev-list --max-parents=0 HEAD"
        )
        assert(gen_a == gen_b, "genesis mismatch")
    end

    do
        TEST "fetch begs from A"
        local _, code = exec (
            "git -C " .. REPO_B .. " fetch " .. REPO_A .. " refs/begs/*:refs/begs/*"
        )
        assert(code == 0, "fetch begs failed")
    end

    do
        TEST "B has A's beg ref"
        local a = exec (
            "git -C " .. REPO_A .. " for-each-ref refs/begs/ --format='%(objectname)'"
        )
        local b = exec (
            "git -C " .. REPO_B .. " for-each-ref refs/begs/ --format='%(objectname)'"
        )
        assert(a == b, "beg hashes differ: " .. a .. " vs " .. b)
    end

    do
        TEST "beg on B"
        local out = exec (
            EXE_B .. " chain test post inline 'post from B' --beg"
        )
        assert(#out == 40, "hash: " .. out)
        assert(out:match("^%x+$"), "not hex")
    end
end

-- HOST A: fetch begs from B, merge into HEAD
do
    print("==> Host A: fetch begs from B + merge")

    do
        TEST "fetch begs from B"
        local _, code = exec (
            "git -C " .. REPO_A .. " fetch " .. REPO_B .. " refs/begs/*:refs/begs/*"
        )
        assert(code == 0, "fetch failed")
    end

    do
        TEST "A has 2 beg refs"
        local out = exec (
            "git -C " .. REPO_A .. " for-each-ref refs/begs/ --format='%(refname)'"
        )
        local count = 0
        for _ in out:gmatch("[^\n]+") do count = count + 1 end
        assert(count == 2, "expected 2 beg refs, got: " .. count)
    end

    -- merge 1st/2nd beg into HEAD
    do
        local refs = exec (
            "git -C " .. REPO_A .. " for-each-ref refs/begs/ --sort=refname --format='%(refname)'"
        )
        do
            local ref1 = refs:match("[^\n]+")
            TEST "merge beg into HEAD (fast-forward)"
            exec (
                "git -C " .. REPO_A .. " merge --no-edit " .. ref1
            )
            local count = exec (
                "git -C " .. REPO_A .. " rev-list --count HEAD"
            )
            assert(count == "3", "count: " .. count)

            TEST "remove merged beg ref"
            exec (
                "git -C " .. REPO_A .. " update-ref -d " .. ref1
            )
        end
        do
            local ref2 = refs:match("[^\n]*\n([^\n]+)")
            TEST "merge second beg into HEAD (true merge)"
            exec (
                "git -C " .. REPO_A .. " merge --no-edit " .. ref2
            )
            local count = exec (
                "git -C " .. REPO_A .. " rev-list --count HEAD"
            )
            assert(count == "6", "count: " .. count)

            TEST "remove merged beg ref"
            exec (
                "git -C " .. REPO_A .. " update-ref -d " .. ref2
            )
        end
        do
            TEST "no beg refs remain"
            local out = exec (
                "git -C " .. REPO_A .. " for-each-ref refs/begs/ --format='%(refname)'"
            )
            assert(out == "", "stale refs: " .. out)
        end
        do
            TEST "both post files present in A"
            local h = io.popen("cat " .. REPO_A .. "*.txt")
            local all = h:read("a")
            h:close()
            assert(all:match("post from A"), "A's post missing")
            assert(all:match("post from B"), "B's post missing")
        end
    end
end

-- BIDIRECTIONAL SYNC: both beg, fetch begs, merge
do
    print("==> Bidirectional beg sync")

    do
        TEST "A begs again"
        local out = exec (
            EXE_A .. " chain test post inline 'second from A' --beg"
        )
        assert(#out == 40, "hash: " .. out)

        TEST "B begs again"
        local out = exec (
            EXE_B .. " chain test post inline 'second from B' --beg"
        )
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "A fetches begs from B"
        local _, code = exec (
            "git -C " .. REPO_A .. " fetch " .. REPO_B .. " refs/begs/*:refs/begs/*"
        )
        assert(code == 0, "fetch failed")

        TEST "B fetches begs from A"
        local _, code = exec (
            "git -C " .. REPO_B .. " fetch " .. REPO_A .. " refs/begs/*:refs/begs/*"
        )
        assert(code == 0, "fetch failed")
    end

    do
        TEST "A and B have same beg refs"
        local a = exec (
            "git -C " .. REPO_A .. " for-each-ref refs/begs/ --sort=refname --format='%(refname) %(objectname)'"
        )
        local b = exec (
            "git -C " .. REPO_B .. " for-each-ref refs/begs/ --sort=refname --format='%(refname) %(objectname)'"
        )
        assert(a == b, "beg refs differ")
    end

    -- B pulls HEAD from A, then prunes merged begs
    do
        TEST "B fetches HEAD from A"
        local _, code = exec (
            "git -C " .. REPO_B .. " fetch " .. REPO_A .. " main"
        )
        assert(code == 0, "fetch HEAD failed")

        TEST "B merges A's HEAD"
        exec (
            "git -C " .. REPO_B .. " merge --no-edit FETCH_HEAD"
        )
    end

    do
        TEST "B prunes merged begs"
        local refs = exec (
            "git -C " .. REPO_B .. " for-each-ref refs/begs/ --format='%(refname)'"
        )
        for ref in refs:gmatch("[^\n]+") do
            local _, code = exec (true,
                "git -C " .. REPO_B .. " merge-base --is-ancestor " .. ref .. " HEAD"
            )
            if code == 0 then
                exec (
                    "git -C " .. REPO_B .. " update-ref -d " .. ref
                )
            end
        end

        TEST "B has 2 beg refs remaining"
        local out = exec (
            "git -C " .. REPO_B .. " for-each-ref refs/begs/ --format='%(refname)'"
        )
        local count = 0
        for _ in out:gmatch("[^\n]+") do count = count + 1 end
        assert(count == 2, "expected 2 beg refs, got: " .. count)
    end
end

-- UNRELATED HISTORIES: independent chain, fetch beg, merge fails
do
    print("==> Unrelated histories rejected")

    local h = exec (
        EXE_C .. " chains add test init " .. GEN_0
    )
    assert(h ~= CHAIN_HASH, "should differ")

    do
        TEST "fetch begs from A succeeds"
        local _, code = exec (
            "git -C " .. REPO_C .. " fetch " .. REPO_A .. " refs/begs/*:refs/begs/*"
        )
        assert(code == 0, "fetch should succeed")
    end

    do
        TEST "merge beg into unrelated HEAD fails"
        local ref = exec (
            "git -C " .. REPO_C .. " for-each-ref refs/begs/ --sort=refname --format='%(refname)'"
        )
        local first = ref:match("[^\n]+")
        local _, code = exec (true,
            "git -C " .. REPO_C .. " merge --no-commit --no-ff " .. first
        )
        assert(code ~= 0, "should reject unrelated histories")
    end
end

-- CONFLICT: both beg to same file, merge both into HEAD
do
    print("==> Conflict: both beg to log.txt")

    exec("rm -rf " .. TMP)
    exec("mkdir -p " .. ROOT_A)
    exec("mkdir -p " .. ROOT_B)
    exec(EXE_A .. " chains add test init " .. GEN_0)

    -- clone A to B
    exec (
        EXE_B .. " chains add test clone " .. REPO_A
    )

    do
        TEST "A begs to log.txt"
        local out = exec (
            EXE_A .. " chain test post inline 'from A' --file log.txt --beg"
        )
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "B begs to log.txt"
        local out = exec (
            EXE_B .. " chain test post inline 'from B' --file log.txt --beg"
        )
        assert(#out == 40, "hash: " .. out)
    end

    do
        TEST "A fetches begs from B"
        local _, code = exec (
            "git -C " .. REPO_A .. " fetch " .. REPO_B .. " refs/begs/*:refs/begs/*"
        )
        assert(code == 0, "fetch should succeed")
    end

    -- merge first beg (fast-forward)
    local refs = exec (
        "git -C " .. REPO_A .. " for-each-ref refs/begs/ --sort=refname --format='%(refname)'"
    )
    local ref1 = refs:match("[^\n]+")
    local ref2 = refs:match("[^\n]*\n([^\n]+)")

    exec (
        "git -C " .. REPO_A .. " merge --no-edit " .. ref1
    )

    -- record content after first merge (order is non-deterministic)
    local clean = io.open(REPO_A .. "log.txt"):read("a")

    do
        TEST "merge second beg fails with conflict"
        local _, code = exec (true,
            "git -C " .. REPO_A .. " merge --no-edit " .. ref2
        )
        assert(code ~= 0, "should fail with conflict")
    end

    do
        TEST "log.txt has conflict markers"
        local h = io.open(REPO_A .. "log.txt")
        local content = h:read("a")
        h:close()
        assert(content:match("<<<<<<<"), "no conflict markers")
    end

    do
        TEST "abort merge restores clean state"
        local _, code = exec (
            "git -C " .. REPO_A .. " merge --abort"
        )
        assert(code == 0, "abort failed")
        local h = io.open(REPO_A .. "log.txt")
        local content = h:read("a")
        h:close()
        assert(content == clean, "content: " .. content)
    end
end

print("<== ALL PASSED")
