if ARGS.order then
    for _, hash in ipairs(G.order) do
        if trailer(hash) ~= "state" then
            print(hash)
        end
    end

elseif ARGS.dag then
    local WIDTH = 40
    local MID   = 20
    local SHORT = 7
    local SPAN  = 4

    -- raw git parents of h
    local function gparents (h)
        local out = exec (
            "git -C " .. REPO .. " log -1 --format='%P' " .. h
        )
        local ps = {}
        for p in out:gmatch("%S+") do
            ps[#ps+1] = p
        end
        return ps
    end

    -- V membership: post / like / state-with-2+-parents
    local function is_v (h)
        local t = trailer(h)
        if t == "post" or t == "like" then
            return true
        end
        if t == "state" then
            return #gparents(h) >= 2
        end
        return false
    end

    -- walk transitively through non-V commits collecting V-member ancestors
    local function up_v (h, visited, out, out_seen)
        if visited[h] then
            return
        end
        visited[h] = true
        if is_v(h) then
            if not out_seen[h] then
                out_seen[h] = true
                out[#out+1] = h
            end
            return
        end
        for _, p in ipairs(gparents(h)) do
            up_v(p, visited, out, out_seen)
        end
    end

    -- V-member parents of h
    local function vparents (h)
        local out      = {}
        local out_seen = {}
        for _, p in ipairs(gparents(h)) do
            up_v(p, {}, out, out_seen)
        end
        return out
    end

    -- V in consensus order
    local V = {}
    for _, h in ipairs(G.order) do
        if is_v(h) then
            V[#V+1] = h
        end
    end

    if #V == 0 then
        return
    end

    local parents = {}
    for _, h in ipairs(V) do
        parents[h] = vparents(h)
    end

    -- group V into rows: consecutive entries each with exactly 1 v-parent equal to the
    -- previous entry's 1 v-parent are siblings
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

    -- state-merge → `*`, post/like → 7-char short hash
    local function glyph (h)
        if trailer(h) == "state" then
            return "*"
        end
        return h:sub(1, SHORT)
    end

    -- first hash row
    do
        local t = blank()
        for _, h in ipairs(groups[1]) do
            set_at(t, col[h], glyph(h))
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
            set_at(t2, col[h], glyph(h))
        end
        emit(t2)
    end
end
