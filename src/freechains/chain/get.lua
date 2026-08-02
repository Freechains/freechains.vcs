require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

do
    local _, code = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. ARGS.hash .. " HEAD",
    }
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
    local files = exec {
        cmd = "git -C " .. REPO ..
        " diff-tree --cc --no-commit-id -r --name-only " .. ARGS.hash,
    }
    assert(not files:match("\n%S"), "bug found")
    return files:match("^(%S+)")
end

if ARGS.payload then
    if kind ~= "post" then
        ERROR("chain get : unknown post")
    end

    if G.posts[ARGS.hash] and is_revoked(G.posts[ARGS.hash]) then
        ERROR("chain get : revoked post")
    end

    local file = commit_file()
    -- Not revoked, so we SHOULD hold it -- sync and clone both refuse a
    -- peer that cannot serve a live payload. Reaching here means the
    -- object store lost it some other way; say so, rather than letting
    -- `git show` fail and surface as a raw traceback.
    local out, code = exec { stderr=false, err=false, trim=false,
        cmd = "git -C " .. REPO .. " show " .. ARGS.hash .. ":" .. file,
    }
    if not out then
        ERROR("chain get : payload unavailable")
    end
    io.write(out)

elseif ARGS.metadata then
    if kind~='post' and kind~='like' and kind~='revoke' then
        ERROR("chain get : unknown post")
    end

    local file = commit_file()

    local time = tonumber((exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%at " .. ARGS.hash,
    }))

    -- why: full commit message minus Freechains: trailer
    local why = exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%B " .. ARGS.hash,
    } :gsub("\n*Freechains:%s*%S+%s*$", "")

    -- post/like ancestors via `backs` in common.lua (walks through
    -- state/merge commits)
    local backs = backs(ARGS.hash)

    -- value keyed by kind: post -> filename; like/revoke -> vote table
    local val = file
    if kind=='like' or kind=='revoke' then
        local f = exec {
            cmd = "git -C " .. REPO .. " show " .. ARGS.hash .. ":" .. file,
        }
        val = assert(assert(load(f))())
    end

    local T = {
        hash  = ARGS.hash,
        time  = time,
        sign  = ssh.pubkey(REPO, ARGS.hash) or false,
        why   = why,
        backs = backs,
        --
        [kind] = val,
    }
    io.write(serial(T))
end
