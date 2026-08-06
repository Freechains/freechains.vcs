require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

-- ARGS.aid is an action ID; git ops below need its commit
local cid = CID(ARGS.aid)
if not cid then
    ERROR("chain get : unknown post")
end

local kind = trailer(cid)

-- the single tracked file in this commit (post payload or like Lua).
-- --cc reduces to the file(s) present in this commit but absent
-- from every parent — handles both regular commits and merges
-- (without --cc, diff-tree emits nothing for merge commits).
-- The action file and state the commit also carries are excluded.
local function commit_file ()
    local files = exec {
        cmd = "git -C " .. REPO ..
        " diff-tree --cc --no-commit-id -r --name-only " .. cid ..
        " -- . ':(exclude).freechains'",
    }
    assert(not files:match("\n%S"), "bug found")
    return files:match("^(%S+)")
end

if ARGS.payload then
    if kind ~= "post" then
        ERROR("chain get : unknown post")
    end

    local p = G.posts[ARGS.aid]
    if p and is_revoked(p) then
        ERROR("chain get : revoked post")
    end

    local file = commit_file()
    local out = exec { trim=false,
        cmd = "git -C " .. REPO .. " show " .. cid .. ":" .. file,
    }
    io.write(out)

elseif ARGS.metadata then
    if kind~='post' and kind~='like' and kind~='revoke' then
        ERROR("chain get : unknown post")
    end

    local file = commit_file()

    -- the action file self-describes: time, sign, backs, vote data
    local A = dofile(FC .. "actions/" .. ARGS.aid .. ".lua")

    -- why: full commit message minus Freechains: trailer
    local why = exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%B " .. cid,
    } :gsub("\n*Freechains:%s*%S+%s*$", "")

    -- `val`/`T` only preserve the pre-redesign output shape
    -- value keyed by kind: post -> filename; like/revoke -> vote table
    local val = file
    if kind=='like' or kind=='revoke' then
        val = {
            post   = A.post,
            author = A.author,
            n      = A.n,
        }
    end

    local T = {
        aid   = ARGS.aid,
        time  = A.time,
        sign  = A.sign or false,
        why   = why,
        backs = A.backs,
        --
        [kind] = val,
    }
    io.write(serial(T))
end
