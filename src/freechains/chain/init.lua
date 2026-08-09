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
elseif ARGS.destroy then
    require "freechains.chain.destroy"
else
    G = STATE.read(true, "HEAD")

    if ARGS.list then
        require "freechains.chain.list"
    elseif ARGS.reps then
        apply(G, 'reps', CMD.now, nil)
        require "freechains.chain.reps"
    elseif ARGS.post then
        require "freechains.chain.post"
    elseif ARGS.like or ARGS.dislike or ARGS.revoke or ARGS.unrevoke then
        require "freechains.chain.like"
    elseif ARGS.get then
        require "freechains.chain.get"
    end
end
