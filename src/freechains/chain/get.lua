require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

do
    local _, code = exec(true, 'stdout',
        "git -C " .. REPO .. " merge-base --is-ancestor " .. ARGS.hash .. " HEAD"
    )
    if code ~= 0 then
        ERROR("chain get : unknown post")
    end
end

local kind = trailer(ARGS.hash)

-- the single tracked file in this commit (post payload or like Lua).
-- --cc reduces to the file(s) present in this commit but absent
-- from every parent — handles both regular commits and merges
-- (without --cc, diff-tree emits nothing for merge commits).
local function commit_file ()
    local files = exec (
        "git -C " .. REPO ..
        " diff-tree --cc --no-commit-id -r --name-only " .. ARGS.hash
    )
    assert(not files:match("\n%S"), "bug found")
    return files:match("^(%S+)")
end

if ARGS.payload then
    if kind ~= "post" then
        ERROR("chain get : unknown post")
    end

    local file = commit_file()
    local out = exec (
        "git -C " .. REPO .. " show " .. ARGS.hash .. ":" .. file
    )
    io.write(out)

elseif ARGS.metadata then
    if kind~='post' and kind~='like' then
        ERROR("chain get : unknown post")
    end

    local file = commit_file()

    local time = tonumber((exec (
        "git -C " .. REPO .. " log -1 --format=%at " .. ARGS.hash
    )))

    -- why: full commit message minus Freechains: trailer
    local why = exec (
        "git -C " .. REPO .. " log -1 --format=%B " .. ARGS.hash
    ):gsub("\n*Freechains:%s*%S+%s*$", "")

    -- post/like ancestors via `backs` in common.lua (walks through
    -- state/merge commits)
    local backs = backs(ARGS.hash)

    -- like: only for like-trailer commits
    local like = false
    if kind == 'like' then
        local f = exec (
            "git -C " .. REPO .. " show " .. ARGS.hash .. ":" .. file
        )
        like = assert(assert(load(f))())
    end

    local T = {
        hash  = ARGS.hash,
        time  = time,
        sign  = ssh.pubkey(REPO, ARGS.hash) or false,
        why   = why,
        backs = backs,
        --
        post  = (kind=='post' and file) or false,
        like  = like,
    }
    io.write(serial(T))
end
