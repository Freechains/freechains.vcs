local function ext (int)
    if int > 0 then
        return math.tointeger((int + 999) // 1000)
    elseif int < 0 then
        return -math.tointeger((-int + 999) // 1000)
    else
        return 0
    end
end

if ARGS.target == "post" then
    if not ARGS.key then
        ERROR("TODO : TEST : chain reps : post requires a hash")
    end
    local e = G.posts[ARGS.key]
    local v = (e and e.reps) or 0
    print(ext(v))
elseif ARGS.target == "posts" then
    local T = {}
    for k, v in pairs(G.posts) do
        T[#T+1] = { k=k, v=v.reps }
    end
    table.sort(T, function (a, b) return a.v > b.v end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. ext(e.v))
    end
elseif ARGS.target == "author" then
    if not ARGS.key then
        ERROR("TODO : TEST : chain reps : author requires a pubkey")
    end
    local e = G.authors[ARGS.key]
    local v = (e and e.reps) or 0
    print(ext(v))
elseif ARGS.target == "authors" then
    local T = {}
    for k, v in pairs(G.authors) do
        T[#T+1] = { k=k, v=v.reps }
    end
    table.sort(T, function (a, b) return a.v > b.v end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. ext(e.v))
    end
else
    ERROR("TODO : TEST : chain reps : invalid target : " .. ARGS.target)
end
