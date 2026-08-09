require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

local cid = ACTION.cid(ARGS.aid)
if not cid then
    ERROR("chain get : unknown post")
end
do
    local _, code = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. cid .. " HEAD",
    }
    if code ~= 0 then
        ERROR("chain get : unknown post")
    end
end

local kind = trailer(cid)

-- the single tracked file in this commit (post payload or like Lua).
-- --cc reduces to the file(s) present in this commit but absent
-- from every parent — handles both regular commits and merges
-- (without --cc, diff-tree emits nothing for merge commits).
local function commit_file ()
    local files = exec {
        cmd = "git -C " .. REPO ..
        " diff-tree --cc --no-commit-id -r --name-only " .. cid ..
        " -- . ':!.freechains/actions'",    -- TODO : remove
    }
    assert(not files:match("\n%S"), "bug found")
    return files:match("^(%S+)")
end

if ARGS.payload then
    if kind ~= "post" then
        ERROR("chain get : unknown post")
    end

    if G.posts[ARGS.aid] and is_revoked(G.posts[ARGS.aid]) then
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

    local time = tonumber((exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%at " .. cid,
    }))

    -- why: full commit message minus Freechains: trailer
    local why = exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%B " .. cid,
    } :gsub("\n*Freechains:%s*%S+%s*$", "")

    -- action ancestors as aids (the CLI surface): the commit walk,
    -- each back mapped to its action file
    local backs = backs(cid)
    for i, b in ipairs(backs) do
        backs[i] = assert(ACTION.aid(b))
    end

    -- value keyed by kind: post -> filename; like/revoke -> vote table
    local val = file
    if kind=='like' or kind=='revoke' then
        local f = exec {
            cmd = "git -C " .. REPO .. " show " .. cid .. ":" .. file,
        }
        val = assert(assert(load(f))())
    end

    local T = {
        hash  = ARGS.aid,
        time  = time,
        sign  = ssh.pub.commit(REPO, cid) or false,
        why   = why,
        backs = backs,
        --
        [kind] = val,
    }
    io.write(serial(T))
end
