#!/usr/bin/env lua5.4

local VERSION = "v0.20"

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
        print("freechains " .. VERSION)
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
            dir = {},
        },
        rem = {},
        dir = {},
    },
    chain = {
        _ = parser:command("chain"),
        post = {
            file = {},
            inline = {},
        },
        like = {},
        dislike = {},
        reps = {},
    },
}

-- cmd.chains
do
    -- cmd.chains.add
    cmd.chains.add._ = cmd.chains._:command("add")
    do
        -- cmd.chains.add.lua
        cmd.chains.add._:argument("alias")
        cmd.chains.add.dir._ = cmd.chains.add._:command("dir")
        cmd.chains.add.dir._:argument("path")
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

    -- cmd.chain.like
    cmd.chain.like._ = cmd.chain._:command("like")
    cmd.chain.like._:argument("number"):convert(tonumber)
    cmd.chain.like._:argument("target")
    cmd.chain.like._:argument("id")
    cmd.chain.like._:option("--sign")
    cmd.chain.like._:option("--why")

    -- cmd.chain.dislike
    cmd.chain.dislike._ = cmd.chain._:command("dislike")
    cmd.chain.dislike._:argument("number"):convert(tonumber)
    cmd.chain.dislike._:argument("target")
    cmd.chain.dislike._:argument("id")
    cmd.chain.dislike._:option("--sign")
    cmd.chain.dislike._:option("--why")

    -- cmd.chain.reps
    cmd.chain.reps._ = cmd.chain._:command("reps")
    cmd.chain.reps._:argument("target")
    cmd.chain.reps._:argument("key"):args("?")
end

ARGS = parser:parse()

NOW = { s = os.time(), git = "" }
if ARGS.now then
    NOW.s = ARGS.now
    NOW.git = (
        "GIT_AUTHOR_DATE=$(date -u -d @" .. NOW.s .. " --iso-8601=seconds) " ..
        "GIT_COMMITTER_DATE=$(date -u -d @" .. NOW.s .. " --iso-8601=seconds) "
    )
end

if ARGS.chains then
    require "freechains.chains"
elseif ARGS.chain then
    require "freechains.chain"
end
