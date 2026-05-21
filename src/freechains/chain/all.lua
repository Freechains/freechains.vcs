if ARGS.order then
    for _, hash in ipairs(G.order) do
        if trailer(hash) ~= "state" then
            print(hash)
        end
    end

elseif ARGS.dag then
    local WIDTH = 40
    local MID   = 20

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

    -- walk up through state commits, return first non-state ancestor or nil
    local function up_non_state (h)
        while h and h ~= "" do
            if trailer(h) ~= "state" then
                return h
            end
            local ps = gparents(h)
            h = ps[1]
        end
        return nil
    end

    -- non-state parents of h (deduplicated)
    local function nparents (h)
        local result = {}
        local seen   = {}
        for _, p in ipairs(gparents(h)) do
            local np = up_non_state(p)
            if np and not seen[np] then
                seen[np] = true
                result[#result+1] = np
            end
        end
        return result
    end

    -- V: non-state commits in consensus order
    local V = {}
    for _, h in ipairs(G.order) do
        if trailer(h) ~= "state" then
            V[#V+1] = h
        end
    end

    if #V == 0 then
        return
    end

    local function clamp (c)
        if c < 0 then return 0 end
        if c > WIDTH-1 then return WIDTH-1 end
        return c
    end

    -- column assignment: linear stays in place; forks alternate +1/-1, +2/-2;
    -- merges take the midpoint of parent columns; tip forced to MID
    local col      = {}
    local children = {}
    col[V[1]]      = MID
    children[V[1]] = 0

    for i = 2, #V do
        local h  = V[i]
        local ps = nparents(h)
        if #ps == 0 then
            col[h] = MID
        elseif #ps == 1 then
            local p = ps[1]
            local n = children[p] or 0
            if n == 0 then
                col[h] = col[p]
            else
                local step = (n + 1) // 2
                local sign = (n % 2 == 1) and 1 or -1
                col[h] = clamp(col[p] + sign * step)
            end
            children[p] = n + 1
        else
            local sum = 0
            for _, p in ipairs(ps) do
                sum = sum + col[p]
                children[p] = (children[p] or 0) + 1
            end
            col[h] = clamp(sum // #ps)
        end
        children[h] = 0
    end

    -- tip centered
    col[V[#V]] = MID

    local function row (positions)
        local t = {}
        for i = 0, WIDTH-1 do
            t[i+1] = positions[i] or " "
        end
        return table.concat(t)
    end

    -- print first commit row
    print(row({ [col[V[1]]] = "*" }))

    -- for each subsequent commit: connector row + star row
    for i = 2, #V do
        local h  = V[i]
        local hc = col[h]
        local ps = nparents(h)

        local positions = {}
        for _, p in ipairs(ps) do
            local pc  = col[p]
            local mid = (pc + hc) // 2
            local ch
            if hc > pc then
                ch = "\\"
            elseif hc < pc then
                ch = "/"
            else
                ch = "|"
            end
            positions[mid] = ch
        end
        print(row(positions))
        print(row({ [hc] = "*" }))
    end
end
