C    = require "freechains.constants"
REPO = ARGS.root .. "/chains/" .. ARGS.alias .. "/"
FC   = REPO .. ".freechains/"

function NOW (hash)
    return assert(
        tonumber((
            exec("git -C " .. REPO .. " log -1 --format=%at " .. hash)
        ))
    )
end

function write (G)
    local function f (V, file)
        local f = io.open(file, "w")
        f:write(serial(V))
        f:close()
    end

    f(G.authors, FC .. "state/authors.lua")
    f(G.posts,   FC .. "state/posts.lua")
    f(G.order,   FC .. "state/order.lua")
end

function apply (G, kind, time, T)
    local sign = T and T.sign

    -- TIME: monotonicity, discount, consolidation
    do
        -- monotonic timestamp
        if time < G.now-C.time.diff then
            return false, "too old"
        end

        -- discount scan (maybe signed at same G.now)
        if time>G.now or sign then
            for hash, entry in pairs(G.posts) do
                if entry.state == "00-12" then
                    local subs = {}
                    for h2, other in pairs(G.posts) do
                        if other.time and other.time>entry.time then
                            subs[other.author] = true
                        end
                    end
                    if sign then
                        subs[sign] = true
                    end

                    local cur = 0
                    for a in pairs(subs) do
                        cur = cur + math.max(0, (G.authors[a] and G.authors[a].reps) or 0)
                    end
                    local tot = 0
                    for _, v in pairs(G.authors) do
                        tot = tot + math.max(0, v.reps)
                    end

                    local ratio = (tot>0 and cur/tot) or 0
                    local discount = C.time.half * math.max(0, 1 - 2*ratio)

                    if time >= entry.time + discount then
                        G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                        entry.state = "12-24"
                    end
                end
            end
        end

        -- consolidation scan
        if time > G.now then
            for hash, entry in pairs(G.posts) do
                if entry.state == "12-24" then
                    if time >= entry.time+C.time.full then
                        local last = G.authors[entry.author].time
                        if time-last >= C.time.full then
                            G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                            G.authors[entry.author].time = last + C.time.full
                            entry.state = nil
                            entry.time  = nil
                        end
                    end
                end
            end
        end

        if time > G.now then
            G.now = time
        end
    end

    if kind == 'reps' then
        -- no validation / mutation

    elseif kind == 'post' then
        -- validation
        assert(T.sign or T.beg)
        if T.sign then
            if T.beg then
                local reps = G.authors[T.sign] and G.authors[T.sign].reps or 0
                if reps > 0 then
                    return false, "--beg error : author has sufficient reputation"
                end
            else
                local reps = G.authors[T.sign] and G.authors[T.sign].reps or 0
                if reps <= 0 then
                    return false, "insufficient reputation"
                end
            end
        end

        -- mutation
        G.posts[T.hash] = {
            author = T.sign,
            time   = time,
            state  = (T.beg and 'blocked') or (T.sign and '00-12') or 'blocked',
            reps   = 0,
        }
        if T.sign then
            G.authors[T.sign] = G.authors[T.sign] or { reps=0 }
            if not T.beg then
                G.authors[T.sign].reps = G.authors[T.sign].reps - C.reps.cost
                if G.authors[T.sign].time == nil then
                    -- do not set for beg, bc not available to others
                    G.authors[T.sign].time = time
                end
            end
        end

    elseif kind == 'like' and T then
        -- validation
        assert(T.sign, "bug found")
        if math.type(T.num)~='integer' or T.num==0 then
            return false, "invalid number : expects non-zero integer"
        end
        if T.target~="post" and T.target~="author" then
            return false, "invalid target : expects 'post' or 'author'"
        end
        if T.target=="post" and (not G.posts[T.id]) then
            return false, "invalid target : post not found"
        end
        local reps = (G.authors[T.sign] and G.authors[T.sign].reps) or 0
        if reps <= 0 then
            return false, "insufficient reputation"
        end

        -- mutation
        G.authors[T.sign].reps = G.authors[T.sign].reps - math.abs(T.num)
        local num = T.num * (100 - C.like.tax) // 100
        if T.target == "post" then
            local a = G.posts[T.id].author
            G.authors[a] = G.authors[a] or { reps=0 }
            G.authors[a].reps = G.authors[a].reps + num//C.like.split
            G.posts[T.id].reps = G.posts[T.id].reps + num//C.like.split
            if T.beg then
                G.posts[T.id].state = "00-12"
                G.posts[T.id].time = time
            end
        else
            G.authors[T.id] = G.authors[T.id] or { reps=0 }
            G.authors[T.id].reps = G.authors[T.id].reps + num
        end
    end

    -- cap all authors at max
    for k, v in pairs(G.authors) do
        if v.reps > C.reps.max then
            v.reps = C.reps.max
        end
    end

    return true
end
