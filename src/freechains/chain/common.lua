C    = require "freechains.constants"
REPO = ARGS.root .. "/chains/" .. ARGS.alias .. "/"
FC   = REPO .. ".freechains/"

function write (T, file)
    local f = io.open(file, "w")
    f:write(serial(T))
    f:close()
end

function apply (G, T)
    if T.kind == 'post' then
        G.xps = true
        G.posts[T.hash] = {
            author = T.sign,
            time   = T.time,
            state  = (T.beg and 'blocked') or (T.sign and '00-12') or 'blocked',
            reps   = 0,
        }
        if T.sign then
            G.xas = true
            G.authors[T.sign] = G.authors[T.sign] or { reps=0 }
            if not T.beg then
                G.authors[T.sign].reps = G.authors[T.sign].reps - C.reps.cost
                if G.authors[T.sign].time == nil then
                    -- do not set for beg, bc not available to others
                    G.authors[T.sign].time = T.time
                end
            end
        end

    elseif T.kind == 'like' then
        G.xas = true
        G.authors[T.sign].reps = G.authors[T.sign].reps - math.abs(T.num)
        local num = T.num * (100 - C.like.tax) // 100
        if T.target == "post" then
            local a = G.posts[T.id].author
            G.authors[a] = G.authors[a] or { reps=0 }
            G.authors[a].reps = G.authors[a].reps + num // C.like.split
            G.posts[T.id].reps = G.posts[T.id].reps + num // C.like.split
            if T.beg then
                G.posts[T.id].state = "00-12"
                G.posts[T.id].time = T.time
            end
            G.xps = true
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
end
