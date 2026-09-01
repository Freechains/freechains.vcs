--[[
-- `chain <alias> list begs|order|revokes|tips|dag`
-- Print chain actions in the chosen view.
-- Inputs:
--  - ARGS.begs|order|revokes|tips|dag [boolean]: the view
--  - G    [table]: state at HEAD (order, revocations)
--  - REPO [string]: the chain's bare repo dir
-- Outputs:
--  - stdout: cids one per line (revoked wrapped in ~cid~),
--            tips as sorted bare cids,
--            or ASCII dag (short labels)
-- Errors:
--  - none
-- Callers:
--  - dispatch (chain/init.lua): ARGS.list
--]]

if ARGS.tips then
    -- tips: blocks that are ups of no other block; sorted cids
    local has = {}
    for _, cid in ipairs(G.order) do
        for _, u in ipairs(ACTION.backs(GIT.parents(cid))) do
            has[u] = true
        end
    end
    local tips = {}
    for _, cid in ipairs(G.order) do
        if not has[cid] then
            tips[#tips+1] = cid
        end
    end
    table.sort(tips)
    for _, cid in ipairs(tips) do
        print(cid)
    end

elseif ARGS.begs then
    -- pending begs: post cids parked on refs/begs/beg-<cid>
    local out = exec {
        cmd = "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(refname)'",
    }
    for h in out:gmatch("refs/begs/beg%-(%x+)") do
        print(h)
    end

elseif ARGS.revokes then
    -- revoked payloads only, in consensus order (bare cids)
    for _, cid in ipairs(G.order) do
        if G.actions[cid] and RULES.is_revoked(G.actions[cid]) then
            print(cid)
        end
    end

elseif ARGS.order then
    -- consensus order (cids); revoked payloads wrapped in ~cid~
    for _, cid in ipairs(G.order) do
        if G.actions[cid] and RULES.is_revoked(G.actions[cid]) then
            print("~" .. cid .. "~")
        else
            print(cid)
        end
    end

elseif ARGS.dag then
    -- TODO: this whole branch is AI-gened and was not properly reviewed
    -- tst/dag.lua algorithm (plan 260812-list-dag):
    --  - each node at its depth line; same depth, same line
    --  - alternate 1 node line, 1 edge line
    --  - columns: parents centered (root mid, single up
    --    inherits, forks spread around the up, joins at the
    --    ups' midpoint); per-row sweep resolves collisions
    --  - edges: `|` `\` `/` at the midpoint; upper-level
    --    parents as `abc^`/`^abc` hints on the parent's side

    local order = G.order
    if #order == 0 then
        return
    end

    -- ups are structural: the action ancestors of each commit's
    -- parents (the cid IS the commit); short labels, revoked wrapped in ~~
    local ups = {}
    local lbl = {}
    for _, h in ipairs(order) do
        ups[h] = ACTION.backs(GIT.parents(h))
        local l = h:sub(1, 7)
        if G.actions[h] and RULES.is_revoked(G.actions[h]) then
            l = "~" .. l .. "~"
        end
        lbl[h] = l
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

    --[[
    -- Write string `s` centered at column `c` of a sparse row.
    -- Inputs:
    --  - t [table]: sparse char row (column -> char); MUTATED
    --  - c [integer]: center column
    --  - s [string]: the label/glyph
    -- Outputs:
    --  - none
    -- Errors:
    --  - none
    -- Callers:
    --  - list dag (list.lua): node and edge lines
    --]]
    local function set_at (t, c, s)
        local start = c - (#s // 2)
        for k = 1, #s do
            if start + k >= 1 then
                t[start + k] = s:sub(k, k)
            end
        end
    end
    --[[
    -- Print a sparse char row, blanks filled, right-trimmed.
    -- Inputs:
    --  - t [table]: sparse char row (column -> char)
    -- Outputs:
    --  - none: prints one line
    -- Errors:
    --  - none
    -- Callers:
    --  - list dag (list.lua): once per node/edge line
    --]]
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
