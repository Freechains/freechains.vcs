if ARGS.begs then
    -- pending begs: post hashes parked on refs/begs/beg-<hash>
    local out = exec {
        cmd = "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(refname)'",
    }
    for h in out:gmatch("refs/begs/beg%-(%x+)") do
        print(h)
    end

elseif ARGS.order then
    -- consensus order; revoked posts wrapped in ~hash~
    for _, hash in ipairs(G.order) do
        if G.posts[hash] and is_revoked(G.posts[hash]) then
            print("~" .. hash .. "~")
        else
            print(hash)
        end
    end

elseif ARGS.revokes then
    -- revoked posts only, in consensus order (bare hashes)
    for _, hash in ipairs(G.order) do
        if G.posts[hash] and is_revoked(G.posts[hash]) then
            print(hash)
        end
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

    -- ups[h]: the nodes drawn above h, via backs() (walks state/merge
    -- commits transparently)
    local ups = {}
    for _, h in ipairs(V) do
        ups[h] = backs(h)
    end

    -- group V into rows: consecutive nodes sharing one single up.
    -- groupOf[h] = row index, used to distinguish immediate vs distant ups.
    local groups, groupOf = {}, {}
    do
        -- siblings share one single up -- and two CONTENT ROOTS (a
        -- chain whose first posts are concurrent) share the same
        -- ABSENT up, so they belong on one row too
        local function siblings (a, b)
            local ua, ub = ups[a], ups[b]
            if #ua == 0 and #ub == 0 then
                return true
            else
                return #ua == 1 and #ub == 1 and ua[1] == ub[1]
            end
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

    -- column assignment: midpoint of the ups, then spread siblings around it
    local col = {}
    for g, group in ipairs(groups) do
        local uc
        if g == 1 then
            uc = MID
        else
            -- average only the ups already PLACED: a content root has
            -- no ups at all, and an up ordered later has no column yet
            local sum, n = 0, 0
            for _, u in ipairs(ups[group[1]]) do
                if col[u] then
                    sum = sum + col[u]
                    n = n + 1
                end
            end
            uc = (n > 0) and (sum // n) or MID
        end
        local n = #group
        for i, h in ipairs(group) do
            col[h] = uc + (2*(i-1) - (n-1)) * SPAN
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
                -- fork: N siblings fan out from a single shared up
                local u1 = ups[cur[1]][1]
                if u1 and col[u1] then
                    local uc = col[u1]
                    for _, h in ipairs(cur) do
                        set_at(t, (uc + col[h]) // 2, glyph(uc, col[h]))
                    end
                end
            else
                -- linear / join: a glyph per IMMEDIATE up
                local h, hc = cur[1], col[cur[1]]
                for _, u in ipairs(ups[h]) do
                    if groupOf[u] == g - 1 then
                        set_at(t, (col[u] + hc) // 2, glyph(col[u], hc))
                    end
                end
            end
            -- a row with no glyph connects nothing: drop it rather than
            -- printing a blank line between two unrelated nodes
            if table.concat(t):match("%S") then
                emit(t)
            end
        end
        local t = blank()
        for _, h in ipairs(cur) do
            -- revoked posts render as ~short~
            local lbl = h:sub(1, SHORT)
            if G.posts[h] and is_revoked(G.posts[h]) then
                lbl = "~" .. lbl .. "~"
            end
            set_at(t, col[h], lbl)
        end
        emit(t)
        if #cur == 1 then
            local h = cur[1]
            local distant = {}
            for _, u in ipairs(ups[h]) do
                if groupOf[u] ~= g - 1 then
                    distant[#distant+1] = "^" .. u:sub(1, SHORT)
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
