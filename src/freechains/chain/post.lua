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

local path = REPO .. ".git/payload-tmp"   -- payload staging file

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
        exec { stderr=false,
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
    aid = ACTION.pre {
        action = 'post',
        backs  = ACTION.backs { "HEAD" },
        sign   = pub,
        time   = tonumber(CMD.now),
        blob   = blob,
    }
end

-- apply BEFORE the commit: a rejected post leaves nothing
do
    local T = {
        aid     = aid,
        parents = { "HEAD" },
        sign    = pub,
        beg     = ARGS.beg,
    }
    local ok, err = apply(G, 'post', CMD.now, T)
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

do
    local s1, s2 = "", ""
    if ARGS.sign then
        s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=ssh"
        s2 = " -S"
    end
    exec { stderr=false,
        cmd = CMD.git .. "git -C " .. REPO .. s1 .. " commit" .. s2 .. " -m '(empty message)'",
        err = "chain post : invalid sign key",
    }
end

-- snapshot state at the new tip (the action commit itself)
STATE.write(G, true, "HEAD")

if ARGS.beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/begs/beg-" .. aid .. " HEAD",
    }
    exec {
        cmd = "git -C " .. REPO .. " reset --hard HEAD~1",
    }
end

print(aid)
