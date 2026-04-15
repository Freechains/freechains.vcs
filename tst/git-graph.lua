#!/usr/bin/env lua5.4

require "tests"

local DIR_A = ROOT .. "/git-graph/A/"
local DIR_B = ROOT .. "/git-graph/B/"

exec("rm -rf " .. ROOT .. "/git-graph")

local function post (dir, file, text)
    local f = io.open(dir .. file, "w")
    f:write(text .. "\n")
    f:close()
    exec("git -C " .. dir .. " add " .. file)
    exec("git -C " .. dir .. " commit --allow-empty-message -m ''")
end

local function graph (dir, fr, to)
    local log = exec (
        "git -C " .. dir .. " rev-list --topo-order --reverse --parents " ..
            fr .. ".." .. to
    )
    local G = {
        root = fr,
        [fr] = { hash=fr, childs={} },
    }
    for l in log:gmatch("[^\n]+") do
        local hs = {}
        for h in l:gmatch("%x+") do
            hs[#hs+1] = h
        end
        local me = hs[1]
        G[me] = { hash=me, childs={} }
        for i=2, #hs do
            local up = G[hs[i]].childs
            up[#up+1] = me
        end
    end
    return G
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

    local DIR = ROOT .. "/git-graph/lab/"
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
        assert(G.root == H1)

        TEST "graph: H1 is fork (2 children)"
        assert(#G[H1].childs == 2)

        TEST "graph: M1 has 1 child (linear after merge)"
        assert(#G[M1].childs == 1)

        TEST "graph: M2 has 1 child (H2)"
        assert(#G[M2].childs == 1)
        assert(G[M2].childs[1] == H2)

        TEST "graph: H2 is leaf"
        assert(#G[H2].childs == 0)
    end
end

print("<== ALL PASSED")
