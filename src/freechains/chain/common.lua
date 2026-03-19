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
        if not T.beg then
            assert(T.sign and G.authors[T.sign])
            G.authors[T.sign].reps = G.authors[T.sign].reps - C.reps.cost
            if G.authors[T.sign].time == nil then
                G.authors[T.sign].time = T.time
            end
            G.xas = true
        end
        if T.hash then
            G.posts[T.hash] = {
                author = T.sign,
                time   = T.time,
                state  = (T.beg and 'blocked') or (T.sign and '00-12') or 'blocked',
                reps   = 0,
            }
            G.xps = true
        end

    elseif T.kind == 'like' then
        G.authors[T.sign].reps = G.authors[T.sign].reps - math.abs(T.num)
        local num = T.num * (100 - C.like.tax) // 100
        if T.target == "post" then
            local a = G.posts[T.id].author
            assert(G.authors[a])
            G.authors[a].reps = G.authors[a].reps + num // C.like.split
            G.posts[T.id].reps = G.posts[T.id].reps + num // C.like.split
            G.xps = true
        else
            G.authors[T.id] = G.authors[T.id] or { reps=0 }
            G.authors[T.id].reps = G.authors[T.id].reps + num
        end
        G.xas = true
    end

    -- cap all authors at max
    for k, v in pairs(G.authors) do
        if v.reps > C.reps.max then
            v.reps = C.reps.max
        end
    end
end
