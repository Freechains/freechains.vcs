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
    }

    -- fix tmp ? hash from previous post
    if G.posts["?"] then
        local head = exec("git -C " .. REPO .. " rev-parse HEAD")
        G.posts[head] = G.posts["?"]
        G.posts["?"] = nil
    end

    if ARGS.reps then
        apply(G, 'reps', NOW.s, nil)
        require "freechains.chain.reps"
    elseif ARGS.post then
        require "freechains.chain.post"
    elseif ARGS.like or ARGS.dislike then
        require "freechains.chain.like"
    end
end
