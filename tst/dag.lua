#!/usr/bin/env lua5.4

-- Standalone `list dag` renderer (plan 260812-list-dag).
--  - each node at its depth line; same depth, same line
--  - alternate 1 node line, 1 edge line
--  - columns: parents centered (root mid, single up inherits,
--    forks spread around the up, joins at the ups' midpoint)

-- render(order, ups, revoked):
--  - order:   array of ids, insertion order (ups come earlier)
--  - ups:     map id -> array of ids it links back to (backs)
--  - revoked: optional set of ids, rendered as ~id~

local function render (order, ups, revoked)
    revoked = revoked or {}
    local lbl = {}
    for _, n in ipairs(order) do
        lbl[n] = revoked[n] and ("~" .. n .. "~") or n
    end
    -- depth: root = 0; else 1 + max over ups
    local depth = {}
    local rows  = {}
    for _, n in ipairs(order) do
        local d = 0
        for _, u in ipairs(ups[n]) do
            d = math.max(d, depth[u] + 1)
        end
        depth[n] = d
        rows[d] = rows[d] or {}
        local r = rows[d]
        r[#r+1] = n
    end

    -- hang[u]: the single-up children of u, the ones whose
    -- column derives from it (joins center on their own ups)
    local hang = {}
    for _, n in ipairs(order) do
        hang[n] = {}
    end
    for _, n in ipairs(order) do
        if #ups[n] == 1 then
            local h = hang[ups[n][1]]
            h[#h+1] = n
        end
    end

    -- columns; STEP scales with the widest label, rounded up to
    -- a multiple of 4 so every column stays EVEN and every edge
    -- midpoint is an exact integer (no rounding skew)
    local W = 0
    for _, n in ipairs(order) do
        W = math.max(W, #lbl[n])
    end
    local STEP = (W + 8) // 4 * 4

    local maxd = 0
    local idx  = {}
    for i, n in ipairs(order) do
        maxd = math.max(maxd, depth[n])
        idx[n] = i
    end

    -- assign depth by depth (parents always above), then sweep
    -- each row left to right enforcing a minimum separation:
    -- colliding nodes shift right instead of overwriting each
    -- other (nested forks, criss-cross joins)
    local SEP = (W + 4) // 2 * 2
    local col = {}
    for d = 0, maxd do
        for i, n in ipairs(rows[d]) do
            local us = ups[n]
            if #us == 0 then
                col[n] = (2*i - #rows[0] - 1) * STEP // 2
            elseif #us == 1 then
                local hs = hang[us[1]]
                for j, h in ipairs(hs) do
                    if h == n then
                        col[n] = col[us[1]] + (2*j - #hs - 1) * STEP // 2
                    end
                end
            else
                local sum = 0
                for _, u in ipairs(us) do
                    sum = sum + col[u]
                end
                col[n] = sum // #us
                -- keep columns even (exact midpoints)
                if col[n] % 2 ~= 0 then
                    col[n] = col[n] + 1
                end
            end
        end
        local row = {}
        for _, n in ipairs(rows[d]) do
            row[#row+1] = n
        end
        table.sort(row, function (a, b)
            if col[a] ~= col[b] then
                return col[a] < col[b]
            end
            return idx[a] < idx[b]
        end)
        for i = 2, #row do
            if col[row[i]] - col[row[i-1]] < SEP then
                col[row[i]] = col[row[i-1]] + SEP
            end
        end
    end

    -- shift left border to column 1
    local min = math.huge
    for _, n in ipairs(order) do
        min = math.min(min, col[n] - (#lbl[n] // 2))
    end
    for _, n in ipairs(order) do
        col[n] = col[n] - min
    end

    -- row helpers: sparse char table, emitted trimmed
    local function set_at (t, c, s)
        local start = c - (#s // 2)
        for k = 1, #s do
            if start + k >= 1 then
                t[start + k] = s:sub(k, k)
            end
        end
    end
    local function emit (t)
        local max = 0
        for i in pairs(t) do
            max = math.max(max, i)
        end
        local cs = {}
        for i = 1, max do
            cs[i] = t[i] or " "
        end
        print(table.concat(cs))
    end

    -- render top-down: edge line (glyph above the child, at the
    -- midpoint of the edge), then node line
    for d = 0, maxd do
        if d > 0 then
            local t = {}
            for _, n in ipairs(rows[d]) do
                for _, u in ipairs(ups[n]) do
                    local mid = (col[u] + col[n]) // 2
                    if d - depth[u] > 1 then
                        -- parent in an upper level (long edge):
                        -- the `^` sits at the midpoint, the
                        -- parent hint extends to the parent's
                        -- side (`123^` left, `^123` right)
                        local hint = u:sub(1, 3)
                        if col[u] < col[n] then
                            local g = hint .. "^"
                            set_at(t, mid + 1 + #g // 2 - #g, g)
                        elseif col[u] > col[n] then
                            local g = "^" .. hint
                            set_at(t, mid + #g // 2, g)
                        else
                            -- straight up: one cell right, so the
                            -- `|` of an immediate parent survives
                            local g = "^" .. hint
                            set_at(t, mid + 1 + #g // 2, g)
                        end
                    elseif col[u] < col[n] then
                        set_at(t, mid, "\\")
                    elseif col[u] > col[n] then
                        set_at(t, mid, "/")
                    else
                        set_at(t, mid, "|")
                    end
                end
            end
            emit(t)
        end
        local t = {}
        for _, n in ipairs(rows[d]) do
            set_at(t, col[n], lbl[n])
        end
        emit(t)
    end
end

-- A/B. diamond
do
    print("== diamond ==")
    local order = { "A", "B", "C", "D" }
    local ups   = {
        A = {},
        B = { "A" },
        C = { "A" },
        D = { "B", "C" },
    }
    render(order, ups)
end

-- C/D. our example (X consensus DAG from the README)
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

-- full guide: the whole #chat story, root to moderation
-- ('day 1' joins the fork tips; the discarded post is gone;
-- the two revoked posts render as ~id~)
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

-- revoked: minimal chain, the middle post erased
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

-- ugly 1, tri: 3 peers post from a shared tip; the next post
-- after the syncs backs all three
do
    print("== tri ==")
    local order = { "R", "A", "B", "C", "J", "K" }
    local ups   = {
        R = {},
        A = { "R" },
        B = { "R" },
        C = { "R" },
        J = { "A", "B", "C" },
        K = { "J" },
    }
    render(order, ups)
end

-- ugly 2, nested: two peers fork, then each side forks again
-- (inner spreads collide in the middle)
do
    print("== nested ==")
    local order = { "R", "A", "A1", "A2", "B", "B1", "B2" }
    local ups   = {
        R  = {},
        A  = { "R" },
        A1 = { "A" },
        A2 = { "A" },
        B  = { "R" },
        B1 = { "B" },
        B2 = { "B" },
    }
    render(order, ups)
end

-- ugly 3, criss-cross: bilateral sync, both peers post
-- concurrently twice (both joins share both parents)
do
    print("== criss-cross ==")
    local order = { "R", "X1", "X2", "J1", "J2" }
    local ups   = {
        R  = {},
        X1 = { "R" },
        X2 = { "R" },
        J1 = { "X1", "X2" },
        J2 = { "X1", "X2" },
    }
    render(order, ups)
end

-- ugly 4, roots: three concurrent first posts (content roots);
-- a later post backs only the two outer ones
do
    print("== roots ==")
    local order = { "P", "Q", "S", "M" }
    local ups   = {
        P = {},
        Q = {},
        S = {},
        M = { "P", "S" },
    }
    render(order, ups)
end

-- ugly 5, late beg: a beg parked early, admitted after the
-- chain advanced (the like backs the beg AND the far tip)
do
    print("== late beg ==")
    local order = { "R", "BEG", "A1", "A2", "A3", "LIK" }
    local ups   = {
        R   = {},
        BEG = { "R" },
        A1  = { "R" },
        A2  = { "A1" },
        A3  = { "A2" },
        LIK = { "BEG", "A3" },
    }
    render(order, ups)
end
