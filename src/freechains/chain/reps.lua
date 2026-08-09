local function ext (int)
    if int > 0 then
        return math.tointeger((int + 999) // 1000)
    elseif int < 0 then
        return -math.tointeger((-int + 999) // 1000)
    else
        return 0
    end
end

if ARGS.key then
    ARGS.key = ARGS.key:match("^%s*(.-)%s*$")
end

-- CLI keys are aids; G.posts is commit-keyed.
-- unknown/alien aids tolerated: no entry -> 0
local function entry (aid)
    local cid = ACTION.cid(aid)
    return cid and G.posts[cid] or nil
end

if ARGS.target == "post" then
    if not ARGS.key then
        ERROR("chain reps : post requires a hash")
    end
    local e = entry(ARGS.key)
    local v = (e and e.reps) or 0
    print(ext(v))
elseif ARGS.target == "posts" then
    local T = {}
    for k, v in pairs(G.posts) do
        T[#T+1] = { k=assert(ACTION.aid(k)), v=v.reps }
    end
    table.sort(T, function (a, b) return a.v > b.v end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. ext(e.v))
    end

elseif ARGS.target == "revoke" then
    -- revoke axis is post-only, so the `post` target is implicit
    if not ARGS.key then
        ERROR("chain reps : revoke requires a hash")
    end
    local e = entry(ARGS.key)
    local r = (e and e.revoke) or { author=0, others=0 }
    print(ext(r.author) .. " " .. ext(r.others))
elseif ARGS.target == "revokes" then
    -- both revoke channels of all posts, most revoked first
    local T = {}
    for k, v in pairs(G.posts) do
        local r = v.revoke or { author=0, others=0 }
        T[#T+1] = { k=assert(ACTION.aid(k)), a=r.author, o=r.others }
    end
    table.sort(T, function (x, y)
        if x.o ~= y.o then
            return x.o < y.o
        else
            return x.a < y.a
        end
    end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. ext(e.a) .. " " .. ext(e.o))
    end

elseif ARGS.target == "author" then
    if not ARGS.key then
        ERROR("chain reps : author requires a pubkey")
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
    ERROR("chain reps : invalid target : " .. ARGS.target)
end
