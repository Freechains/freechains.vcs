#!/usr/bin/env lua5.4

-- Standalone `list dag` renderer, tree-style (plan 260812).
-- DFS with prefix strings, as `tree`:
--  - every edge appears once: expansion or `id (shared)` stub
--  - a shared node expands under its FIRST parent in consensus
--    order; later parents get the stub

-- render(order, ups, revoked): same contract as dag.lua

local function render (order, ups, revoked)
    revoked = revoked or {}
    local function lbl (n)
        return revoked[n] and ("~" .. n .. "~") or n
    end

    -- downs in consensus order; roots have no ups
    local downs = {}
    local roots = {}
    for _, n in ipairs(order) do
        downs[n] = {}
    end
    for _, n in ipairs(order) do
        if #ups[n] == 0 then
            roots[#roots+1] = n
        end
        for _, u in ipairs(ups[n]) do
            local d = downs[u]
            d[#d+1] = n
        end
    end

    local visited = {}
    local function rec (n, prefix, is_last)
        local conn = is_last and "└── " or "├── "
        if visited[n] then
            print(prefix .. conn .. lbl(n) .. " (shared)")
            return
        end
        visited[n] = true
        print(prefix .. conn .. "[" .. lbl(n) .. "]")
        local sub = prefix .. (is_last and "    " or "│   ")
        for i, c in ipairs(downs[n]) do
            rec(c, sub, i == #downs[n])
        end
    end
    for i, r in ipairs(roots) do
        rec(r, "", i == #roots)
    end
end

-- the same four examples as dag.lua

do
    print("== diamond ==")
    local order = { "A", "B", "C", "D", "E" }
    local ups   = {
        A = {},
        B = { "A" },
        C = { "A" },
        D = { "B", "C" },
        E = { "D" },
    }
    render(order, ups)
end

do
    print("== example ==")
    local order = {
        "560a55c",      -- like: alice -> bob
        "c7d8e9f",      -- 'A great post!'
        "d8e9f0a",      -- like: alice -> beg
        "a1b2c3d",      -- 'Alice was here'
        "e6d7626",      -- like: bob -> charlie
        "a9b0c1d",      -- like: charlie -> hello
        "b0c1d2e",      -- dislike: bob -> here
        "f4e5d6c",      -- 'Charlie was here'
    }
    local ups = {
        ["560a55c"] = {},
        ["c7d8e9f"] = { "560a55c" },
        ["d8e9f0a"] = { "c7d8e9f", "560a55c" },
        ["a1b2c3d"] = { "d8e9f0a" },
        ["e6d7626"] = { "560a55c" },
        ["a9b0c1d"] = { "e6d7626" },
        ["b0c1d2e"] = { "a9b0c1d" },
        ["f4e5d6c"] = { "b0c1d2e" },
    }
    render(order, ups)
end

do
    print("== full guide ==")
    local order = {
        "b52c62f",      -- 'Hello World'
        "d6568e4",      -- 'I am here'
        "e1f2a3b",      -- 'Sync me'
        "560a55c",      -- like: alice -> bob
        "c7d8e9f",      -- 'A great post!'
        "d8e9f0a",      -- like: alice -> beg
        "a1b2c3d",      -- 'Alice was here'
        "e6d7626",      -- like: bob -> charlie
        "a9b0c1d",      -- like: charlie -> hello
        "b0c1d2e",      -- dislike: bob -> here
        "f4e5d6c",      -- 'Charlie was here'
        "1a2b3c4",      -- 'day 1'
        "7d8e9f0",      -- 'day 7'
        "3c4d5e6",      -- 'Alice takes over' (repost)
        "4a5b6c7",      -- 'BUY NOW' (revoked)
        "8f9a0b1",      -- revoke: alice -> spam
        "5d6e7f8",      -- 'my address is ...' (revoked)
        "6e7f8a9",      -- revoke: bob -> himself
    }
    local ups = {
        ["b52c62f"] = {},
        ["d6568e4"] = { "b52c62f" },
        ["e1f2a3b"] = { "d6568e4" },
        ["560a55c"] = { "e1f2a3b" },
        ["c7d8e9f"] = { "560a55c" },
        ["d8e9f0a"] = { "c7d8e9f", "560a55c" },
        ["a1b2c3d"] = { "d8e9f0a" },
        ["e6d7626"] = { "560a55c" },
        ["a9b0c1d"] = { "e6d7626" },
        ["b0c1d2e"] = { "a9b0c1d" },
        ["f4e5d6c"] = { "b0c1d2e" },
        ["1a2b3c4"] = { "a1b2c3d", "f4e5d6c" },
        ["7d8e9f0"] = { "1a2b3c4" },
        ["3c4d5e6"] = { "7d8e9f0" },
        ["4a5b6c7"] = { "3c4d5e6" },
        ["8f9a0b1"] = { "4a5b6c7" },
        ["5d6e7f8"] = { "8f9a0b1" },
        ["6e7f8a9"] = { "5d6e7f8" },
    }
    local revoked = {
        ["4a5b6c7"] = true,
        ["5d6e7f8"] = true,
    }
    render(order, ups, revoked)
end

do
    print("== revoked ==")
    local order = { "RP1", "RP2", "REV" }
    local ups   = {
        RP1 = {},
        RP2 = { "RP1" },
        REV = { "RP2" },
    }
    render(order, ups, { RP2 = true })
end
