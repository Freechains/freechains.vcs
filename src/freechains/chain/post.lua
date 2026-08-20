local ssh = require "freechains.chain.ssh"

if not (ARGS.sign or ARGS.beg) then
    ERROR("chain post : requires --sign or --beg")
end

-- the writer's own pubkey, read from the `.pub` file BEFORE the
-- commit: a bad key fails early, nothing enters the tree
local pub = nil
if ARGS.sign then
    pub = ssh.pub.key(ARGS.sign)
    if not pub then
        ERROR("chain post : invalid sign key")
    end
end

-- the payload lives OUTSIDE the tree: a loose blob, anchored by
-- `refs/payloads/<aid>`. The action file's `blob` field is what
-- binds it: the aid transitively commits to the content

local path = REPO .. "payload-tmp"   -- payload staging file (git dir)

local act
local aid
local blob
do
    if ARGS.inline then
        local f = io.open(path, "w")
        f:write(ARGS.text)
        f:close()
    else
        assert(ARGS.file)
        -- `cp` runs in the caller's cwd: relative paths just work
        exec {
            cmd = "cp -- '" .. ARGS.path .. "' " .. path,
            err = "chain post : invalid path",
        }
    end
    -- DRY hash: nothing enters the object db before `apply`
    -- accepts, so a rejection leaves nothing to clean
    blob = exec {
        cmd = "git -C " .. REPO .. " hash-object " .. path,
    }

    -- action file: self-description; minted BEFORE the commit
    -- (`pos` places it only after `apply` accepts)
    act = {
        action = 'post',
        backs  = ACTION.backs { "HEAD" },
        sign   = pub,
        time   = tonumber(CMD.now),
        blob   = blob,
    }
    aid = ACTION.pre(act)
end

-- apply BEFORE the commit: a rejected post leaves nothing
do
    local ok, err = apply(G, 'post', act, {
        time = tonumber(CMD.now),
        aid  = aid,
        sign = pub,
        beg  = ARGS.beg,
    })
    if not ok then
        ERROR("chain post : " .. err)
    end
    G.order[#G.order+1] = aid
end

ACTION.pos(aid)

-- the payload enters the object db anchored at its final name:
-- `refs/payloads/<aid>` -> blob. (A crash between the two calls
-- leaves one loose blob for the gc grace period)
exec {
    cmd = "git -C " .. REPO .. " hash-object -w " .. path,
}
exec {
    cmd = "git -C " .. REPO .. " update-ref refs/payloads/" .. aid .. " " .. blob,
}
os.remove(path)

-- unsigned: only a bug fails
GIT.commit {
    parents = { GIT.deref("HEAD") },
    add     = { blob = aid, path = ACTION.path(aid) },
    sign    = ARGS.sign,
    err     = ARGS.sign and "chain post : invalid sign key" or nil,
}

-- snapshot state at the new tip (the action commit itself)
STATE.write(G, GIT.deref("HEAD"))

if ARGS.beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/begs/beg-" .. aid .. " HEAD",
    }
    exec {
        cmd = "git -C " .. REPO .. " update-ref HEAD " .. GIT.deref("HEAD~1"),
    }
end

print(aid)
