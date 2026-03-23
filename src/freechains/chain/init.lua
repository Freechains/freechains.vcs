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
        now     = dofile(FC .. "state/now.lua"),
        xas     = false,
        xps     = false,
    }

    if ARGS.reps then
        apply(G, nil)
        require "freechains.chain.reps"
    elseif ARGS.post then
        require "freechains.chain.post"
    elseif ARGS.like or ARGS.dislike then
        require "freechains.chain.like"
    end

    write(G.now, FC .. "state/now.lua")
    if G.xas then
        write(G.authors, FC .. "state/authors.lua")
    end
    if G.xps then
        write(G.posts, FC .. "state/posts.lua")
    end
end
