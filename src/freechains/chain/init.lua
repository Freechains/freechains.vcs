--[[
-- `chain <alias> ...`
-- Bind the chain globals, check the chain exists, load G, dispatch to
-- subcommand file.
-- Inputs:
--  - ARGS.alias [string]: the chain: "/alias", "<cid>" or "/<cid>"
--  - ARGS.root  [string]: freechains root dir
--  - ARGS.<subcommand> [boolean]: what to dispatch
-- Outputs:
--  - globals: C, ACTION, STATE, GIT, REPO,
--      G (state at HEAD, except sync/abandon/sweep, which read their own)
-- Errors:
--  - "chain <alias> : not found"
-- Callers:
--  - dispatch (freechains.lua): ARGS.chain
--]]

-- chain context: constants, modules, and the repo path
C      = require "freechains.constants"
ACTION = require "freechains.chain.action"
STATE  = require "freechains.chain.state"
GIT    = require "freechains.chain.git"
SSH    = require "freechains.chain.ssh"
RULES  = require "freechains.chain.rules"
CONSENSUS = require "freechains.chain.consensus"
REPO   = ARGS.root .. "/chains/" .. ARGS.alias .. "/"

do
    -- the chain exists <=> its (bare) repo resolves the genesis ref
    local ok = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " cat-file -e refs/genesis",
    }
    if not ok then
        ERROR("chain " .. ARGS.alias .. " : not found")
    end
end

if ARGS.sync then
    require "freechains.chain.sync"
elseif ARGS.abandon then
    require "freechains.chain.abandon"
elseif ARGS.sweep then
    require "freechains.chain.sweep"
else
    G = CONSENSUS.state(GIT.deref("HEAD"))

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
