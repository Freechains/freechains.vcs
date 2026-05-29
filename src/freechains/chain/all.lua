if ARGS.begs then
    -- pending begs: post hashes parked on refs/begs/beg-<hash>
    local out = exec (
        "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(refname)'"
    )
    for h in out:gmatch("refs/begs/beg%-(%x+)") do
        print(h)
    end

elseif ARGS.order then
    for _, hash in ipairs(G.order) do
        print(hash)
    end

elseif ARGS.dag then
    -- TODO: this whole branch is AI-gened and was not properly reviewed

    local WIDTH = 40
    local MID   = 20
    local SHORT = 7
    local SPAN  = 4

    -- G.order is already post/like only
    local V = G.order
    if #V == 0 then
        return
    end

    -- V-parents via backs() (walks state/merge transparently)
    local parents = {}
    for _, h in ipairs(V) do
        parents[h] = backs(h)
    end

    -- group V into rows: consecutive nodes sharing a single same v-parent.
    -- groupOf[h] = row index, used to distinguish immediate vs distant parents.
    local groups, groupOf = {}, {}
    do
        local function siblings (a, b)
            local pa, pb = parents[a], parents[b]
            return #pa == 1 and #pb == 1 and pa[1] == pb[1]
        end
        local cur = { V[1] }
        for i = 2, #V do
            if siblings(cur[#cur], V[i]) then
                cur[#cur+1] = V[i]
            else
                groups[#groups+1] = cur
                cur = { V[i] }
            end
        end
        groups[#groups+1] = cur
        for g, grp in ipairs(groups) do
            for _, h in ipairs(grp) do
                groupOf[h] = g
            end
        end
    end

    -- column assignment: parent-midpoint, then spread siblings around it
    local col = {}
    for g, group in ipairs(groups) do
        local pc
        if g == 1 then
            pc = MID
        else
            local ps  = parents[group[1]]
            local sum = 0
            for _, p in ipairs(ps) do
                sum = sum + col[p]
            end
            pc = sum // #ps
        end
        local n = #group
        for i, h in ipairs(group) do
            col[h] = pc + (2*(i-1) - (n-1)) * SPAN
        end
    end

    -- row helpers
    local function blank ()
        local t = {}
        for i = 1, WIDTH do
            t[i] = " "
        end
        return t
    end
    local function set_at (t, c, str)
        local start = c - (#str // 2)
        for k = 1, #str do
            local pos = start + k
            if pos >= 1 and pos <= WIDTH then
                t[pos] = str:sub(k, k)
            end
        end
    end
    local function emit (t)
        print((table.concat(t):gsub("%s+$", "")))
    end
    local function glyph (top, bot)
        if top < bot then
            return "\\"
        elseif top > bot then
            return "/"
        else
            return "|"
        end
    end

    -- render: per group, optional connector row, hash row, optional annotation
    for g, cur in ipairs(groups) do
        if g > 1 then
            local t = blank()
            if #cur >= 2 then
                -- fork: N siblings fan out from a single shared parent
                local pc = col[parents[cur[1]][1]]
                for _, h in ipairs(cur) do
                    set_at(t, (pc + col[h]) // 2, glyph(pc, col[h]))
                end
            else
                -- linear / join: a glyph per IMMEDIATE parent
                local h, hc = cur[1], col[cur[1]]
                for _, p in ipairs(parents[h]) do
                    if groupOf[p] == g - 1 then
                        set_at(t, (col[p] + hc) // 2, glyph(col[p], hc))
                    end
                end
            end
            emit(t)
        end
        local t = blank()
        for _, h in ipairs(cur) do
            set_at(t, col[h], h:sub(1, SHORT))
        end
        emit(t)
        if #cur == 1 then
            local h = cur[1]
            local distant = {}
            for _, p in ipairs(parents[h]) do
                if groupOf[p] ~= g - 1 then
                    distant[#distant+1] = "^" .. p:sub(1, SHORT)
                end
            end
            if #distant > 0 then
                local s = "(" .. table.concat(distant, " ") .. ")"
                local lead = math.max(0, col[h] - (#s // 2))
                print(string.rep(" ", lead) .. s)
            end
        end
    end
end
