require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

-- ARGS.aid is an action ID; git ops below need its commit
-- TODO : remove : S11b : db[aid] is membership + cid in one place
local cid = CID(ARGS.aid)
if not cid then
    ERROR("chain get : unknown post")
end

-- the action file self-describes; CID guarantees it is tracked
local A = dofile(FC .. "actions/" .. ARGS.aid .. ".lua")

-- TODO : remove : S10 : payload = db[aid].blob
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
    if A.action ~= "post" then
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
    if A.action~='post' and A.action~='like' and A.action~='revoke' then
        ERROR("chain get : unknown post")
    end

    local file = commit_file()

    -- TODO : redesign : will become a blob
    -- why: the commit message (no trailers left in it)
    local why = exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%B " .. cid,
    } :gsub("%s+$", "")

    -- TODO : remove : S10 : emit the action file itself (+aid/why);
    -- `val`/`T` only preserve the pre-redesign output shape
    -- value keyed by kind: post -> filename; like/revoke -> vote table
    local val = file
    if A.action=='like' or A.action=='revoke' then
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
        [A.action] = val,
    }
    io.write(serial(T))
end
