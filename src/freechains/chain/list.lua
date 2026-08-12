if ARGS.begs then
    -- pending begs: post aids parked on refs/begs/beg-<aid>
    local out = exec {
        cmd = "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(refname)'",
    }
    for h in out:gmatch("refs/begs/beg%-(%x+)") do
        print(h)
    end

elseif ARGS.order then
    -- consensus order (aids); revoked payloads wrapped in ~aid~
    for _, aid in ipairs(G.order) do
        if G.actions[aid] and is_revoked(G.actions[aid]) then
            print("~" .. aid .. "~")
        else
            print(aid)
        end
    end

elseif ARGS.revokes then
    -- revoked payloads only, in consensus order (bare aids)
    for _, aid in ipairs(G.order) do
        if G.actions[aid] and is_revoked(G.actions[aid]) then
            print(aid)
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

    -- ups from each action file's `backs` (the aid IS its blob
    -- hash); short labels, revoked wrapped in ~~
    local ups = {}
    local lbl = {}
    for _, h in ipairs(order) do
        ups[h] = assert(load(exec {
            cmd = "git -C " .. REPO .. " cat-file blob " .. h,
        }))().backs
        local l = h:sub(1, 7)
        if G.actions[h] and is_revoked(G.actions[h]) then
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
