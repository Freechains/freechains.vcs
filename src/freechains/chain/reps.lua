if ARGS.key then
    ARGS.key = ARGS.key:match("^%s*(.-)%s*$")
end

advance(G, { time = tonumber(CMD.now) })
cap(G)

if ARGS.target == "action" then
    if not ARGS.key then
        ERROR("chain reps : action requires a hash")
    end
    local e = G.actions[ARGS.key]
    local v = (e and e.reps) or 0
    print(v)
elseif ARGS.target == "actions" then
    local T = {}
    for k, v in pairs(G.actions) do
        T[#T+1] = { k=k, v=v.reps }
    end
    table.sort(T, function (a, b) return a.v > b.v end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. e.v)
    end

elseif ARGS.target == "revoke" then
    -- the axis is per ACTION (post or vote), so no target argument
    if not ARGS.key then
        ERROR("chain reps : revoke requires a hash")
    end
    local e = G.actions[ARGS.key]
    local r = (e and e.revoke) or { author=0, others=0 }
    print(r.author .. " " .. r.others)
elseif ARGS.target == "revokes" then
    -- both revoke channels of every action, most revoked first
    local T = {}
    for k, v in pairs(G.actions) do
        local r = v.revoke or { author=0, others=0 }
        T[#T+1] = { k=k, a=r.author, o=r.others }
    end
    table.sort(T, function (x, y)
        if x.o ~= y.o then
            return x.o < y.o
        else
            return x.a < y.a
        end
    end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. e.a .. " " .. e.o)
    end

elseif ARGS.target == "author" then
    if not ARGS.key then
        ERROR("chain reps : author requires a pubkey")
    end
    local e = G.authors[ARGS.key]
    local v = (e and e.reps) or 0
    print(v)
elseif ARGS.target == "authors" then
    local T = {}
    for k, v in pairs(G.authors) do
        T[#T+1] = { k=k, v=v.reps }
    end
    table.sort(T, function (a, b) return a.v > b.v end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. e.v)
    end

else
    ERROR("chain reps : invalid target : " .. ARGS.target)
end
