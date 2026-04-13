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

local function graph (dir, fr, to)
    local log = exec (
        "git -C " .. dir .. " rev-list --topo-order --reverse --parents " ..
            fr .. ".." .. to
    )
    local pars = {}
    local order = {}
    for line in log:gmatch("[^\n]+") do
        local hashes = {}
        for h in line:gmatch("%x+") do
            hashes[#hashes+1] = h
        end
        local commit = hashes[1]
        order[#order+1] = commit
        pars[commit] = {}
        for i = 2, #hashes do
            pars[commit][#pars[commit]+1] = hashes[i]
        end
    end
    local children = {}
    children[fr] = {}
    for _, h in ipairs(order) do
        children[h] = children[h] or {}
    end
    for _, h in ipairs(order) do
        for _, p in ipairs(pars[h]) do
            if children[p] then
                children[p][#children[p]+1] = h
            end
        end
    end
    local nodes = {}
    local function build (hash)
        if nodes[hash] then return nodes[hash] end
        local node = { hash = hash }
        nodes[hash] = node
        for _, child in ipairs(children[hash]) do
            node[#node+1] = build(child)
        end
        return node
    end
    return build(fr)
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
        local _, ok = exec("diff -r --exclude=.git " .. DIR_A .. " " .. DIR_B)
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
        local _, ok = exec("diff -r --exclude=.git " .. DIR_A .. " " .. DIR_B)
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
        local _, ok = exec("diff -r --exclude=.git " .. DIR_A .. " " .. DIR_B)
        assert(ok == 0, "A and B differ")
    end
end

-- SCENARIO 4: nested merge DAG lab
--
-- pre → H1 → a1 → a2 → M1 → a4 → a5 → M2 → H2 → post
--         \    \       /              /
--          \    b1 → b2              /
--           \                       /
--            c1 ──────── c2 ───────
--
-- H1..H2 contains M2 (outer) which contains M1 (inner)
do
    print("==> Scenario 4: nested merge DAG lab")

    local DIR = ROOT .. "/git-merge/lab/"
    exec("rm -rf " .. DIR)
    exec("git init -b main " .. DIR)
    exec("git -C " .. DIR .. " config user.name  '-'")
    exec("git -C " .. DIR .. " config user.email '-'")

    -- pre
    post(DIR, "pre.txt", "pre")

    -- H1
    post(DIR, "h1.txt", "h1")
    local H1 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- branch-c from H1: c1, c2
    exec("git -C " .. DIR .. " checkout -b branch-c")
    post(DIR, "c1.txt", "c1")
    post(DIR, "c2.txt", "c2")

    -- back to main: a1
    exec("git -C " .. DIR .. " checkout main")
    post(DIR, "a1.txt", "a1")

    -- branch-b from a1: b1, b2
    exec("git -C " .. DIR .. " checkout -b branch-b")
    post(DIR, "b1.txt", "b1")
    post(DIR, "b2.txt", "b2")

    -- back to main: a2
    exec("git -C " .. DIR .. " checkout main")
    post(DIR, "a2.txt", "a2")

    -- M1: merge branch-b into main
    exec("git -C " .. DIR .. " merge --no-edit branch-b")
    local M1 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- a4, a5
    post(DIR, "a4.txt", "a4")
    post(DIR, "a5.txt", "a5")

    -- M2: merge branch-c into main
    exec("git -C " .. DIR .. " merge --no-edit branch-c")
    local M2 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- H2
    post(DIR, "h2.txt", "h2")
    local H2 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- post (after H2)
    post(DIR, "post.txt", "post")

    -- DAG diagram
    print()
    print("--- full DAG ---")
    print(exec("git -C " .. DIR .. " log --oneline --graph --all"))
    print()

    print("--- H1..H2 ---")
    print(exec("git -C " .. DIR .. " log --oneline --graph " .. H1 .. ".." .. H2))
    print()
    print("git -C " .. DIR .. " log --oneline --graph " .. H1 .. ".." .. H2)

    print("H1 = " .. H1:sub(1,7))
    print("H2 = " .. H2:sub(1,7))
    print("M1 = " .. M1:sub(1,7))
    print("M2 = " .. M2:sub(1,7))
    print()

    -- merges in H1..H2
    print("--- merges in H1..H2 ---")
    local merges = exec("git -C " .. DIR .. " rev-list --topo-order --merges " .. H1 .. ".." .. H2)
    for h in merges:gmatch("%x+") do
        local parents = exec("git -C " .. DIR .. " rev-list --parents -1 " .. h)
        print(h:sub(1,7) .. " parents: " .. parents:gsub("(%x+)", function(x) return x:sub(1,7) end))
    end
    print()

    -- merge-bases
    print("--- merge-bases ---")
    do
        local p = exec("git -C " .. DIR .. " rev-list --parents -1 " .. M2)
        local _, p1, p2 = p:match("(%x+) (%x+) (%x+)")
        local base = exec("git -C " .. DIR .. " merge-base " .. p1 .. " " .. p2)
        print("M2 parents: " .. p1:sub(1,7) .. " " .. p2:sub(1,7) .. "  base: " .. base:sub(1,7))
    end
    do
        local p = exec("git -C " .. DIR .. " rev-list --parents -1 " .. M1)
        local _, p1, p2 = p:match("(%x+) (%x+) (%x+)")
        local base = exec("git -C " .. DIR .. " merge-base " .. p1 .. " " .. p2)
        print("M1 parents: " .. p1:sub(1,7) .. " " .. p2:sub(1,7) .. "  base: " .. base:sub(1,7))
    end
    print()

    -- last merge in range (what recursive replay would find first)
    print("--- last merge (--max-count=1) ---")
    local last = exec("git -C " .. DIR .. " rev-list --topo-order --merges --max-count=1 " .. H1 .. ".." .. H2)
    print(last:sub(1,7) .. " (should be M2)")
    assert(last == M2, "last merge should be M2")

    -- graph tests
    do
        local G = graph(DIR, H1, H2)

        TEST "graph root is H1"
        assert(G.hash == H1)

        TEST "graph: H1 has 2 children (a1, c1)"
        assert(#G == 2)

        TEST "graph: fork at a1 (2 children: a2, b1)"
        local a1 = G[1]
        assert(#a1 == 2)

        TEST "graph: M1 is shared ref"
        local a2 = a1[1]
        local b2 = a1[2][1]  -- b1 -> b2
        assert(#a2 == 1 and #b2 == 1)
        assert(a2[1] == b2[1], "M1 should be shared")
        assert(a2[1].hash == M1)

        TEST "graph: M2 is shared ref"
        local m1 = a2[1]
        local a5 = m1[1][1]  -- M1 -> a4 -> a5
        local c2 = G[2][1]   -- c1 -> c2
        assert(#a5 == 1 and #c2 == 1)
        assert(a5[1] == c2[1], "M2 should be shared")
        assert(a5[1].hash == M2)

        TEST "graph: H2 is leaf"
        local m2 = a5[1]
        assert(#m2 == 1)
        assert(m2[1].hash == H2)
        assert(#m2[1] == 0)
    end
end

print("<== ALL PASSED")
