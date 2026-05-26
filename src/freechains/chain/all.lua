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

    -- per-group membership: is p an immediate (previous-row) parent?
    local groups_set = {}
    for i, grp in ipairs(groups) do
        local s = {}
        for _, h in ipairs(grp) do
            s[h] = true
        end
        groups_set[i] = s
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
        else
            -- spread N siblings symmetrically around pc, 2*SPAN between centers
            local n = #group
            for i = 1, n do
                col[group[i]] = pc + (2*(i-1) - (n-1)) * SPAN
            end
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

    -- subsequent: lane row + hash row (+ annotation row for distant parents)
    for g = 2, #groups do
        local cur  = groups[g]
        local imm  = groups_set[g-1]

        -- connector row: a glyph per IMMEDIATE parent (in the previous row)
        local t = blank()
        if #cur >= 2 then
            -- fork: N siblings fan out from a single parent
            local pc = col[parents[cur[1]][1]]
            for _, h in ipairs(cur) do
                local cc  = col[h]
                local mid = (pc + cc) // 2
                if cc < pc then
                    set_at(t, mid, "/")
                elseif cc > pc then
                    set_at(t, mid, "\\")
                else
                    set_at(t, mid, "|")
                end
            end
        else
            local h  = cur[1]
            local hc = col[h]
            for _, p in ipairs(parents[h]) do
                if imm[p] then
                    local pc  = col[p]
                    local mid = (pc + hc) // 2
                    if pc < hc then
                        set_at(t, mid, "\\")
                    elseif pc > hc then
                        set_at(t, mid, "/")
                    else
                        set_at(t, mid, "|")
                    end
                end
            end
        end
        emit(t)

        -- hash row
        local t2 = blank()
        for _, h in ipairs(cur) do
            set_at(t2, col[h], h:sub(1, SHORT))
        end
        emit(t2)

        -- annotation row: distant parents (not in the previous row)
        if #cur == 1 then
            local h = cur[1]
            local distant = {}
            for _, p in ipairs(parents[h]) do
                if not imm[p] then
                    distant[#distant+1] = p
                end
            end
            if #distant > 0 then
                local s = "(^" .. distant[1]:sub(1, SHORT)
                for i = 2, #distant do
                    s = s .. " ^" .. distant[i]:sub(1, SHORT)
                end
                s = s .. ")"
                local lead = col[h] - (#s // 2)
                if lead < 0 then
                    lead = 0
                end
                print(string.rep(" ", lead) .. s)
            end
        end
    end
end
