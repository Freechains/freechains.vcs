require "freechains.chain.common"

do
    local f = io.open(FC .. "/genesis.lua")
    if not f then
        ERROR("chain " .. ARGS.alias .. " : not found")
    end
    f:close()
end

if ARGS.sync then
    require "freechains.chain.sync"
else
    G = {
        authors = dofile(FC .. "state/authors.lua"),
        posts   = dofile(FC .. "state/posts.lua"),
        xas     = false,
        xps     = false,
    }

    -- local time effects: advance discount + consolidation
    do
        local stored = dofile(FC .. "state/now.lua")

        if ARGS.sign~=nil or NOW.s>stored then
            -- discount scan
            for hash, entry in pairs(G.posts) do
                if entry.state == "00-12" then
                    local subs = {}
                    for h2, other in pairs(G.posts) do
                        if other.time and other.time > entry.time then
                            subs[other.author] = true
                        end
                    end
                    if ARGS.sign then
                        subs[ARGS.sign] = true
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

                    if NOW.s >= entry.time + discount then
                        G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                        entry.state = "12-24"
                    end
                end
            end

            -- consolidation scan
            for hash, entry in pairs(G.posts) do
                if entry.state == "12-24" then
                    if NOW.s >= entry.time + C.time.full then
                        local last = G.authors[entry.author].time
                        if NOW.s - last >= C.time.full then
                            G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                            G.authors[entry.author].time = last + C.time.full
                            entry.state = nil
                            entry.time  = nil
                        end
                    end
                end
            end

            -- cap all authors at max (for query paths)
            if ARGS.sign == nil then
                for k, v in pairs(G.authors) do
                    if v.reps > C.reps.max then
                        v.reps = C.reps.max
                    end
                end
            end

            write(NOW.s, FC .. "state/now.lua")
        end
    end

    if ARGS.reps then
        require "freechains.chain.reps"
    elseif ARGS.post or ARGS.like or ARGS.dislike then
        require "freechains.chain.post"
    end

    if G.xas then
        write(G.authors, FC .. "state/authors.lua")
    end
    if G.xps then
        write(G.posts, FC .. "state/posts.lua")
    end
end
