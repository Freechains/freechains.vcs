#!/usr/bin/env lua5.4

math.randomseed()

local argparse = require "freechains.argparse"
local common   = require "freechains.common"

local parser = argparse()

parser
    :name "freechains"
    :description "Freechains: Permissionless Peer-to-peer Content Dissemination"
    :epilog [[
For more information, please visit our website:

    https://www.freechains.org/
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
    chains = {
        _ = parser:command("chains"),
        add = {
            init  = {
                file   = {},
                inline = {},
            },
            clone = {},
        },
        rem = {},
        dir = {},
    },
    chain = {
        _ = parser:command("chain"),
        order = {},
        reps = {},
        post = {
            file = {},
            inline = {},
        },
        like = {},
        dislike = {},
        sync = {
            recv = {},
            send = {},
        },
    },
}

-- cmd.chains
do
    -- cmd.chains.add
    cmd.chains.add._ = cmd.chains._:command("add")
    do
        cmd.chains.add._:argument("alias")
        cmd.chains.add.init._ = cmd.chains.add._:command("init")
        do
            cmd.chains.add.init.file._ = cmd.chains.add.init._:command("file")
            cmd.chains.add.init.file._:argument("path")

            cmd.chains.add.init.inline._ = cmd.chains.add.init._:command("inline")
            cmd.chains.add.init.inline._:option("--sign"):count(1)
        end
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

    -- cmd.chain.order
    cmd.chain.order._ = cmd.chain._:command("order")

    -- cmd.chain.reps
    cmd.chain.reps._ = cmd.chain._:command("reps")
    cmd.chain.reps._:argument("target")
    cmd.chain.reps._:argument("key"):args("?")

    -- cmd.chain.post
    cmd.chain.post._ = cmd.chain._:command("post")
    cmd.chain.post._:option("--sign")
    cmd.chain.post._:option("--why")
    cmd.chain.post._:flag("--beg")
    do
        -- cmd.chain.post.file
        cmd.chain.post.file._ = cmd.chain.post._:command("file")
        cmd.chain.post.file._:argument("path")

        -- cmd.chain.post.inline
        cmd.chain.post.inline._ = cmd.chain.post._:command("inline")
        cmd.chain.post.inline._:argument("text")
        cmd.chain.post.inline._:option("--file")
    end

    local function positive (s)
        local n = math.tointeger(s)
        if n and n>0 then
            return n
        else
            return nil, "expected positive integer : got '" .. s .. "'"
        end
    end

    -- cmd.chain.like
    cmd.chain.like._ = cmd.chain._:command("like")
    cmd.chain.like._:argument("number"):convert(positive)
    cmd.chain.like._:argument("target")
    cmd.chain.like._:argument("id")
    cmd.chain.like._:option("--sign"):count(1)
    cmd.chain.like._:option("--why")

    -- cmd.chain.dislike
    cmd.chain.dislike._ = cmd.chain._:command("dislike")
    cmd.chain.dislike._:argument("number"):convert(positive)
    cmd.chain.dislike._:argument("target")
    cmd.chain.dislike._:argument("id")
    cmd.chain.dislike._:option("--sign"):count(1)
    cmd.chain.dislike._:option("--why")

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

CMD = { now=os.time(), git="" }
if ARGS.now then
    CMD.now = ARGS.now
    CMD.git = (
        "GIT_AUTHOR_DATE=$(date -u -d @" .. CMD.now .. " --iso-8601=seconds) " ..
        "GIT_COMMITTER_DATE=$(date -u -d @" .. CMD.now .. " --iso-8601=seconds) "
    )
end

if ARGS.chains then
    require "freechains.chains"
elseif ARGS.chain then
    require "freechains.chain"
end
