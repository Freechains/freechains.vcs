if ARGS.order then
    for _, hash in ipairs(G.order) do
        print(hash)
    end

elseif ARGS.dag then
    local WIDTH = 40
    local MID   = 20
    local SHORT = 7
    local SPAN  = 4

    -- G.order is already post/like only
    local V = G.order
    if #V == 0 then
        return
    end

    -- V-parents via backs() (walks through state/merge transparently)
    local parents = {}
    for _, h in ipairs(V) do
        parents[h] = backs(h)
    end

    -- group V into rows: consecutive entries each with exactly 1 v-parent equal
    -- to the previous entry's 1 v-parent are siblings
    local groups = {}
    do
        local current = { V[1] }
        for i = 2, #V do
            local pl = parents[current[#current]]
            local pn = parents[V[i]]
            if #pl == 1 and #pn == 1 and pl[1] == pn[1] then
                current[#current+1] = V[i]
            else
                groups[#groups+1] = current
                current = { V[i] }
            end
        end
        groups[#groups+1] = current
    end

    -- column assignment
    local col = {}
    col[groups[1][1]] = MID
    for g = 2, #groups do
        local group = groups[g]
        local ps    = parents[group[1]]
        local pc
        if #ps == 0 then
            pc = MID
        elseif #ps == 1 then
            pc = col[ps[1]]
        else
            local sum = 0
            for _, p in ipairs(ps) do
                sum = sum + col[p]
            end
            pc = sum // #ps
        end
        if #group == 1 then
            col[group[1]] = pc
        elseif #group == 2 then
            col[group[1]] = pc - SPAN
            col[group[2]] = pc + SPAN
        else
            error("bug: 3+ way fork not supported")
        end
    end

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

    -- first hash row
    do
        local t = blank()
        for _, h in ipairs(groups[1]) do
            set_at(t, col[h], h:sub(1, SHORT))
        end
        emit(t)
    end

    -- subsequent: lane row + hash row
    for g = 2, #groups do
        local prev = groups[g-1]
        local cur  = groups[g]

        local t = blank()
        if #cur == 1 and #prev == 1 then
            local cps = parents[cur[1]]
            if #cps >= 2 then
                -- multi-parent commit alone in its row: render join `\   /`
                local hc = col[cur[1]]
                set_at(t, hc - SPAN // 2, "\\")
                set_at(t, hc + SPAN // 2, "/")
            else
                -- linear (possibly shifted)
                local pc  = col[prev[1]]
                local hc  = col[cur[1]]
                local mid = (pc + hc) // 2
                local ch
                if hc > pc then
                    ch = "\\"
                elseif hc < pc then
                    ch = "/"
                else
                    ch = "|"
                end
                set_at(t, mid, ch)
            end
        elseif #cur == 2 and #prev == 1 then
            -- fork
            local pc = col[parents[cur[1]][1]]
            set_at(t, pc - SPAN // 2, "/")
            set_at(t, pc + SPAN // 2, "\\")
        elseif #cur == 1 and #prev == 2 then
            -- join from siblings
            local hc = col[cur[1]]
            set_at(t, hc - SPAN // 2, "\\")
            set_at(t, hc + SPAN // 2, "/")
        end
        emit(t)

        local t2 = blank()
        for _, h in ipairs(cur) do
            set_at(t2, col[h], h:sub(1, SHORT))
        end
        emit(t2)
    end
end
