#!/usr/bin/env lua5.4

--[[
-- The freechains CLI entry point.
-- Builds the argparse tree into global ARGS.
-- Dispatches daemon/chains/chain.
-- Inputs:
--  - arg [table]: the command line (see cli.md)
-- Outputs:
--  - globals: ARGS (with ARGS.now defaulted to os.time())
--  - whatever the dispatched command prints
-- Errors:
--  - argparse usage errors (bad command/argument), exit(1)
-- Callers:
--  - the `freechains` executable (make install)
--  - pre-receive hook (hooks/): recv on push
--  - chains add clone (chains.lua): re-execs `sync recv`
--]]

math.randomseed()

local argparse = require "freechains.argparse"
require "freechains.common"

--[[
-- argparse action for `--sign [key]`: defaults to ~/.ssh/id_ed25519.
-- Inputs:
--  - T  [table]: the args table being filled
--  - k  [string]: "sign" (the option key)
--  - vs [string*]: given value(s)
-- Outputs:
--  - none: sets T.sign
-- Errors:
--  - assert "bug found" : multiple values
-- Callers:
--  - argparse (freechains.lua): post/like/... --sign
--]]
local function sign (T, k, vs)
    local v = os.getenv("HOME") .. "/.ssh/id_ed25519"
    if vs == nil then
        -- default
    elseif type(vs) == "table" then
        assert(#vs <= 1, "bug found")
        if #vs == 0 then
            -- default
        else
            v = vs[1]
        end
    else
        assert(type(vs) == 'string')
        v = vs
    end
    T[k] = v
end

--[[
-- argparse action for `--pioneer`/`--dictator` [key]:
-- defaults to ~/.ssh/id_ed25519.
-- Inputs:
--  - T  [table]: the args table being filled
--  - k  [string]: "pioneer" or "dictator" (the option key)
--  - vs [string*]: given value(s)
-- Outputs:
--  - none: appends to T.pioneer
-- Errors:
--  - assert "bug found" : multiple values
-- Callers:
--  - argparse (freechains.lua): chains add init --pioneer
--  - argparse (freechains.lua): chains add init --dictator
--]]
local function pioneer (T, k, vs)
    local v = os.getenv("HOME") .. "/.ssh/id_ed25519"
    if vs == nil then
        -- default
    elseif type(vs) == "table" then
        assert(#vs <= 1, "bug found")
        if #vs == 0 then
            -- default
        else
            v = vs[1]
        end
    else
        assert(type(vs) == 'string')
        v = vs
    end
    T[k] = T[k] or {}
    table.insert(T[k], v)
end

local parser = argparse()

parser
    :name "freechains"
    :description "Freechains: Permissionless Peer-to-Peer Forums"
    :epilog [[
More Information:

    https://github.com/Freechains/freechains.vcs/

Please report bugs:

    https://github.com/Freechains/freechains.vcs/issues
]]

parser
    :flag("-v --version", "Show version.")
    :action(function()
        print("freechains " .. version())
        os.exit(0)
    end)

parser
    :option("--root")
    :default(os.getenv("HOME") .. "/.freechains/")

parser
    :option("--now")
    :convert(tonumber)

local cmd = {
    daemon = {
        _ = parser:command("daemon"),
        start = {},
        stop  = {},
    },
    chains = {
        _ = parser:command("chains"),
        add = {
            init  = {},
            clone = {},
        },
        rem = {},
        dir = {},
    },
    chain = {
        _ = parser:command("chain"),
        list = {
            tips    = {},
            begs    = {},
            revokes = {},
            dag     = {},
            order   = {},
        },
        reps = {},
        post = {
            file = {},
            inline = {},
        },
        get = {
            metadata = {},
            payload = {},
        },
        like = {},
        dislike = {},
        revoke = {},
        unrevoke = {},
        abandon = {},
        sweep = {},
        sync = {
            recv = {},
            send = {},
        },
    },
}

-- cmd.daemon
do
    cmd.daemon.start._ = cmd.daemon._:command("start")
    cmd.daemon.start._:option("--port"):convert(tonumber)
    cmd.daemon.start._:flag("--hub")
    cmd.daemon.start._:argument("xtra"):args("*")

    cmd.daemon.stop._ = cmd.daemon._:command("stop")
    cmd.daemon.stop._:option("--port"):convert(tonumber)
end

-- cmd.chains
do
    -- cmd.chains.add
    cmd.chains.add._ = cmd.chains._:command("add")
    do
        cmd.chains.add._:argument("alias")
        cmd.chains.add.init._ = cmd.chains.add._:command("init")
        cmd.chains.add.init._:option("--pioneer"):args("?"):count("*"):action(pioneer)
        cmd.chains.add.init._:option("--dictator"):args("?"):count("*"):action(pioneer)
        cmd.chains.add.clone._ = cmd.chains.add._:command("clone")
        cmd.chains.add.clone._:argument("url")
    end

    -- cmd.chains.rem
    cmd.chains.rem._ = cmd.chains._:command("rem")
    cmd.chains.rem._:argument("alias")

    -- cmd.chains.dir
    cmd.chains.dir._ = cmd.chains._:command("dir")
end

-- cmd.chain
do
    cmd.chain._:argument("alias")

    -- cmd.chain.list
    cmd.chain.list._ = cmd.chain._:command("list")
    do
        cmd.chain.list.tips._    = cmd.chain.list._:command("tips")
        cmd.chain.list.begs._    = cmd.chain.list._:command("begs")
        cmd.chain.list.revokes._ = cmd.chain.list._:command("revokes")
        cmd.chain.list.dag._     = cmd.chain.list._:command("dag")
        cmd.chain.list.order._   = cmd.chain.list._:command("order")
    end

    -- cmd.chain.reps
    cmd.chain.reps._ = cmd.chain._:command("reps")
    cmd.chain.reps._:argument("target")
    cmd.chain.reps._:argument("key"):args("?")

    -- cmd.chain.post
    cmd.chain.post._ = cmd.chain._:command("post")
    cmd.chain.post._:option("--sign"):args("?"):action(sign)
    cmd.chain.post._:flag("--beg")
    do
        -- cmd.chain.post.file
        cmd.chain.post.file._ = cmd.chain.post._:command("file")
        cmd.chain.post.file._:argument("path")

        -- cmd.chain.post.inline
        cmd.chain.post.inline._ = cmd.chain.post._:command("inline")
        cmd.chain.post.inline._:argument("text")
    end

    --[[
    -- argparse convert: a strictly positive integer.
    -- Inputs:
    --  - s [string]: the raw argument
    -- Outputs:
    --  - [integer]: the value, or
    --  - [nil, string]: argparse error message
    -- Errors:
    --  - none
    -- Callers:
    --  - argparse (freechains.lua): like/dislike/revoke number
    --]]
    local function positive (s)
        local n = math.tointeger(s)
        if n and n>0 then
            return n
        else
            return nil, "expected positive integer : got '" .. s .. "'"
        end
    end

    -- cmd.chain.get
    cmd.chain.get._ = cmd.chain._:command("get")
    do
        cmd.chain.get.metadata._ = cmd.chain.get._:command("metadata")
        cmd.chain.get.metadata._:argument("id"):target("cid")

        cmd.chain.get.payload._ = cmd.chain.get._:command("payload")
        cmd.chain.get.payload._:argument("id"):target("cid")
    end

    -- cmd.chain.like / dislike : target is a post OR member
    for _,c in ipairs { "like", "dislike" } do
        cmd.chain[c]._ = cmd.chain._:command(c)
        cmd.chain[c]._:argument("number"):convert(positive)
        cmd.chain[c]._:argument("target")
        cmd.chain[c]._:argument("id")
        cmd.chain[c]._:option("--sign"):args("?"):count(1):action(sign)
        cmd.chain[c]._:option("--why")
    end
    cmd.chain.like._:option("--file")

    -- cmd.chain.revoke / unrevoke : any action (no target argument)
    for _,c in ipairs { "revoke", "unrevoke" } do
        cmd.chain[c]._ = cmd.chain._:command(c)
        cmd.chain[c]._:argument("number"):convert(positive)
        cmd.chain[c]._:argument("id")
        cmd.chain[c]._:option("--sign"):args("?"):count(1):action(sign)
        cmd.chain[c]._:option("--why")
    end
    cmd.chain.unrevoke._:option("--file")

    -- cmd.chain.abandon : local only (no sign, no network)
    cmd.chain.abandon._ = cmd.chain._:command("abandon")
    cmd.chain.abandon._:argument("id"):target("cid")
    cmd.chain.abandon._:flag("--keep")

    -- cmd.chain.sweep : local only (no sign, no network)
    cmd.chain.sweep._ = cmd.chain._:command("sweep")

    -- cmd.chain.sync
    cmd.chain.sync._ = cmd.chain._:command("sync")
    do
        cmd.chain.sync.recv._ = cmd.chain.sync._:command("recv")
        cmd.chain.sync.recv._:argument("remote")
        cmd.chain.sync.send._ = cmd.chain.sync._:command("send")
        cmd.chain.sync.send._:argument("remote")
    end
end

ARGS = parser:parse()

ARGS.now = ARGS.now or os.time()

if ARGS.daemon then
    require "freechains.daemon"
elseif ARGS.chains then
    require "freechains.chains"
elseif ARGS.chain then
    require "freechains.chain"
end
