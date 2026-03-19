#!/usr/bin/env lua5.4

require "tests"

local DIR_A = ROOT .. "/git-merge/A/"
local DIR_B = ROOT .. "/git-merge/B/"

exec("rm -rf " .. ROOT .. "/git-merge")

local function post (dir, file, text)
    local f = io.open(dir .. file, "w")
    f:write(text .. "\n")
    f:close()
    exec("git -C " .. dir .. " add " .. file)
    exec("git -C " .. dir .. " commit --allow-empty-message -m ''")
end

local function fetch (dir, remote)
    local _, code = exec("git -C " .. dir .. " fetch " .. remote .. " main")
    assert(code == 0, "fetch failed")
end

-- dry-run merge: returns true if clean, false if conflict
local function dry_merge (dir)
    local _, code = exec(true, "git -C " .. dir .. " merge --no-commit --no-ff FETCH_HEAD")
    exec("git -C " .. dir .. " merge --abort")
    return code == 0
end

local function read_file (path)
    local f = io.open(path)
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

-- SETUP: A inits, B clones
do
    print("==> Setup: A inits, B clones")

    do
        TEST "A creates repo"
        exec("git init -b main " .. DIR_A)
        exec("git -C " .. DIR_A .. " config user.name  '-'")
        exec("git -C " .. DIR_A .. " config user.email '-'")
        exec("git -C " .. DIR_A .. " commit --allow-empty -m 'genesis'")
    end

    do
        TEST "B clones from A"
        exec("git clone " .. DIR_A .. " " .. DIR_B)
        exec("git -C " .. DIR_B .. " config user.name  '-'")
        exec("git -C " .. DIR_B .. " config user.email '-'")
    end
end

-- SCENARIO 1: no-conflict merge (default strategy)
do
    print("==> Scenario 1: no-conflict merge (default strategy)")

    do
        TEST "A adds a.txt // B adds b.txt"
        post(DIR_A, "a.txt", "from A")
        post(DIR_B, "b.txt", "from B")
    end

    do
        TEST "A fetches from B"
        fetch(DIR_A, DIR_B)

        TEST "dry-run: no conflict"
        assert(dry_merge(DIR_A) == true, "should not conflict")

        TEST "A merges B (no conflict)"
        fetch(DIR_A, DIR_B)
        exec("git -C " .. DIR_A .. " merge --no-edit --no-ff FETCH_HEAD")
    end

    do
        TEST "both files present in A"
        assert(read_file(DIR_A .. "a.txt") == "from A\n", "a.txt")
        assert(read_file(DIR_A .. "b.txt") == "from B\n", "b.txt")
    end

    do
        TEST "B fetches from A (fast-forward)"
        fetch(DIR_B, DIR_A)
        exec("git -C " .. DIR_B .. " merge --no-edit FETCH_HEAD")
    end

    do
        TEST "A and B are equal after scenario 1"
        local _, ok = exec('stderr', "diff -r --exclude=.git " .. DIR_A .. " " .. DIR_B)
        assert(ok == 0, "A and B differ")
    end
end

-- SCENARIO 2: conflict, ours wins (-s ours)
do
    print("==> Scenario 2: conflict, ours wins (-s ours)")

    do
        TEST "B adds c.txt"
        post(DIR_B, "c.txt", "from B")

        TEST "A adds a2.txt"
        post(DIR_A, "a2.txt", "from A")

        TEST "A adds c.txt (conflict with B)"
        post(DIR_A, "c.txt", "from A")
    end

    do
        TEST "A fetches from B"
        fetch(DIR_A, DIR_B)

        TEST "dry-run: conflict detected"
        assert(dry_merge(DIR_A) == false, "should conflict")

        TEST "A merges B with -s ours (discard B entirely)"
        fetch(DIR_A, DIR_B)
        exec("git -C " .. DIR_A .. " merge --no-edit -s ours FETCH_HEAD")
    end

    do
        TEST "c.txt is from A (ours won)"
        assert(read_file(DIR_A .. "c.txt") == "from A\n", "c.txt should be from A")

        TEST "a2.txt present (A's branch kept)"
        assert(read_file(DIR_A .. "a2.txt") == "from A\n", "a2.txt")

        TEST "b.txt still present (from scenario 1)"
        assert(read_file(DIR_A .. "b.txt") == "from B\n", "b.txt")
    end

    do
        TEST "B fetches from A (fast-forward)"
        fetch(DIR_B, DIR_A)
        exec("git -C " .. DIR_B .. " merge --no-edit FETCH_HEAD")
    end

    do
        TEST "A and B are equal after scenario 2"
        local _, ok = exec('stderr', "diff -r --exclude=.git " .. DIR_A .. " " .. DIR_B)
        assert(ok == 0, "A and B differ")
    end
end

-- SCENARIO 3: conflict, theirs wins (read-tree hack)
do
    print("==> Scenario 3: conflict, theirs wins (read-tree hack)")

    do
        TEST "B adds d.txt"
        post(DIR_B, "d.txt", "from B")

        TEST "A adds a3.txt"
        post(DIR_A, "a3.txt", "from A")

        TEST "A adds d.txt (conflict with B)"
        post(DIR_A, "d.txt", "from A")
    end

    do
        TEST "A fetches from B"
        fetch(DIR_A, DIR_B)

        TEST "dry-run: conflict detected"
        assert(dry_merge(DIR_A) == false, "should conflict")

        TEST "A merges B with read-tree hack (discard A entirely)"
        fetch(DIR_A, DIR_B)
        exec("git -C " .. DIR_A .. " merge --no-commit -s ours FETCH_HEAD")
        exec("git -C " .. DIR_A .. " read-tree --reset -u FETCH_HEAD")
        exec("git -C " .. DIR_A .. " commit --no-edit")
    end

    do
        TEST "d.txt is from B (theirs won)"
        assert(read_file(DIR_A .. "d.txt") == "from B\n", "d.txt should be from B")

        TEST "a3.txt is gone (A's branch discarded)"
        assert(read_file(DIR_A .. "a3.txt") == nil, "a3.txt should not exist")
    end

    do
        TEST "B fetches from A (fast-forward)"
        fetch(DIR_B, DIR_A)
        exec("git -C " .. DIR_B .. " merge --no-edit FETCH_HEAD")
    end

    do
        TEST "A and B are equal after scenario 3"
        local _, ok = exec('stderr', "diff -r --exclude=.git " .. DIR_A .. " " .. DIR_B)
        assert(ok == 0, "A and B differ")
    end
end

print("<== ALL PASSED")
