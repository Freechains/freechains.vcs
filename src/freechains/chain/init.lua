-- chain context: constants, modules, and the repo path
C      = require "freechains.constants"
ACTION = require "freechains.chain.action"
STATE  = require "freechains.chain.state"
GIT    = require "freechains.chain.git"
require "freechains.chain.rules"
REPO   = ARGS.root .. "/chains/" .. ARGS.alias .. "/"

do
    local f = io.open(REPO .. "genesis.lua")
    if not f then
        ERROR("chain " .. ARGS.alias .. " : not found")
    end
    f:close()
end

if ARGS.sync then
    require "freechains.chain.sync"
elseif ARGS.abandon then
    require "freechains.chain.abandon"
elseif ARGS.sweep then
    require "freechains.chain.sweep"
else
    G = STATE.read(GIT.deref("HEAD"))

    if ARGS.list then
        require "freechains.chain.list"
    elseif ARGS.reps then
        require "freechains.chain.reps"
    elseif ARGS.post then
        require "freechains.chain.post"
    elseif ARGS.like or ARGS.dislike or ARGS.revoke or ARGS.unrevoke then
        require "freechains.chain.like"
    elseif ARGS.get then
        require "freechains.chain.get"
    end
end
