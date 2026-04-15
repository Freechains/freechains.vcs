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

-- Walk fork at `node`: returns l1, l2, r1, r2, join
-- l1, r1 = two branch entries (children of node)
-- join   = first common forward-descendant of l1 and r1
-- l2, r2 = parents of join on left/right side respectively
-- General: works even when branches contain nested sub-forks.
local function walk (H, node)
    local l1 = H[node].childs[1]
    local r1 = H[node].childs[2]
    local L, Lpred = { [l1]=true }, {}
    do
        local stack = { l1 }
        while #stack > 0 do
            local cur = table.remove(stack)
            for _, c in ipairs(H[cur].childs) do
                if not L[c] then
                    L[c] = true
                    Lpred[c] = cur
                    stack[#stack+1] = c
                else
                    -- already seen
                end
            end
        end
    end
    local join, Rpred = nil, {}
    do
        local stack = { r1 }
        local seen = { [r1]=true }
        while #stack > 0 and not join do
            local cur = table.remove(stack)
            for _, c in ipairs(H[cur].childs) do
                if L[c] then
                    join = c
                    Rpred[c] = cur
                    break
                elseif not seen[c] then
                    seen[c] = true
                    Rpred[c] = cur
                    stack[#stack+1] = c
                else
                    -- already seen
                end
            end
        end
    end
    return l1, Lpred[join], r1, Rpred[join], join
end

-- SCENARIO 1: nested merge DAG lab
--
-- pre → H1 → a1 → a2 → M1 → a4 → a5 → M2 → H2 → post
--         \    \       /              /
--          \    b1 → b2              /
--           \                       /
--            c1 ──────── c2 ───────
--
-- H1..H2 contains M2 (outer) which contains M1 (inner)
do
    print("==> Scenario 1: nested merge DAG lab")

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
    local c1 = exec("git -C " .. DIR .. " rev-parse HEAD")
    post(DIR, "c2.txt", "c2")
    local c2 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- back to main: a1
    exec("git -C " .. DIR .. " checkout main")
    post(DIR, "a1.txt", "a1")
    local a1 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- branch-b from a1: b1, b2
    exec("git -C " .. DIR .. " checkout -b branch-b")
    post(DIR, "b1.txt", "b1")
    local b1 = exec("git -C " .. DIR .. " rev-parse HEAD")
    post(DIR, "b2.txt", "b2")
    local b2 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- back to main: a2
    exec("git -C " .. DIR .. " checkout main")
    post(DIR, "a2.txt", "a2")
    local a2 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- M1: merge branch-b into main
    exec("git -C " .. DIR .. " merge --no-edit branch-b")
    local M1 = exec("git -C " .. DIR .. " rev-parse HEAD")

    -- a4, a5
    post(DIR, "a4.txt", "a4")
    post(DIR, "a5.txt", "a5")
    local a5 = exec("git -C " .. DIR .. " rev-parse HEAD")

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

        TEST "walk: outer fork at H1 joins at M2"
        do
            local l1, l2, r1, r2, join = walk(G, H1)
            assert(join == M2)
            assert((l1==a1 and r1==c1) or (l1==c1 and r1==a1))
            if l1 == a1 then
                assert(l2==a5 and r2==c2)
            else
                assert(l2==c2 and r2==a5)
            end
        end

        TEST "walk: inner fork at a1 joins at M1"
        do
            local l1, l2, r1, r2, join = walk(G, a1)
            assert(join == M1)
            assert((l1==a2 and r1==b1) or (l1==b1 and r1==a2))
            if l1 == a2 then
                assert(l2==a2 and r2==b2)
            else
                assert(l2==b2 and r2==a2)
            end
        end
    end
end

print("<== ALL PASSED")
