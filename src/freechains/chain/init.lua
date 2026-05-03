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
        order   = dofile(FC .. "state/order.lua"),
        now     = NOW("HEAD"),
    }
    G.order[#G.order+1] = exec (
        "git -C " .. REPO .. " rev-parse HEAD"
    )

    if ARGS.order then
        require "freechains.chain.order"
    elseif ARGS.reps then
        apply(G, 'reps', CMD.now, nil)
        require "freechains.chain.reps"
    elseif ARGS.post then
        require "freechains.chain.post"
    elseif ARGS.like or ARGS.dislike then
        require "freechains.chain.like"
    elseif ARGS.get then
        require "freechains.chain.get"
    end
end
