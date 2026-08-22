--[[
-- `chain <alias> post`
-- Mint a post action, accept it via pipeline, anchor its payload, move HEAD
-- (or park as a beg).
-- Inputs:
--  - ARGS.inline/ARGS.text [string?]: inline payload
--  - ARGS.file/ARGS.path   [string?]: payload file path
--  - ARGS.sign [string?]: ssh private key path
--  - ARGS.beg  [boolean?]: park on refs/begs/, HEAD untouched
--  - ARGS.now  [integer]: the action's TIME (commit DATE)
--  - G    [table]: state at HEAD; MUTATED by the pipeline
--  - REPO [string]: the chain's bare repo dir
-- Outputs:
--  - stdout: the new cid
--  - refs: payload blob at refs/payloads/<cid>; HEAD -> cid,
--    or refs/begs/beg-<cid> (--beg); state at refs/states/<cid>
-- Errors:
--  - "chain post : requires --sign or --beg"
--  - "chain post : invalid sign key"
--  - "chain post : invalid path"
--  - "chain post : <rules>" : refused by the pipeline
-- Callers:
--  - dispatch (chain/init.lua): ARGS.post
--]]

local ssh = require "freechains.chain.ssh"

if not (ARGS.sign or ARGS.beg) then
    ERROR("chain post : requires --sign or --beg")
end

-- the writer's own pubkey, read from the `.pub` file BEFORE the
-- commit: a bad key fails early, nothing enters the object db
local pub = nil
if ARGS.sign then
    pub = ssh.pub.key(ARGS.sign)
    if not pub then
        ERROR("chain post : invalid sign key")
    end
end

-- the payload lives OUTSIDE the commit: a loose blob, anchored by
-- `refs/payloads/<cid>`. The action's `blob` field is what binds
-- it: the cid transitively commits to the content

local path = REPO .. "payload-tmp"   -- payload staging file (git dir)

-- the parents of the commit about to be minted: `backs` derives
-- from them (parents ARE the backs: the cid IS the commit)
local ps = { GIT.deref("HEAD") }

local act
local cid
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
    -- DRY hash: the payload enters the object db only after
    -- `apply` accepts, so a rejection leaves nothing to clean
    blob = exec {
        cmd = "git -C " .. REPO .. " hash-object " .. path,
    }

    -- the action IS the commit message; minted UNREFERENCED
    -- (the cid IS the commit), so a rejection leaves one gc-able loose commit.
    act = {
        action = 'post',
        sign   = pub,
        time   = tonumber(CMD.now),
        blob   = blob,
    }
    cid = ACTION.pre {
        act     = act,
        parents = ps,
        sign    = ARGS.sign,
        err     = ARGS.sign and "chain post : invalid sign key" or nil,
    }
end

-- apply BEFORE HEAD moves: a rejected post leaves nothing anchored
do
    local ok, err = apply(G, 'post', act, {
        cid   = cid,
        time  = tonumber(CMD.now),
        sign  = pub,
        beg   = ARGS.beg,
        backs = ACTION.backs(ps),
    })
    if not ok then
        ERROR("chain post : " .. err)
    end
    G.order[#G.order+1] = cid
end

-- the payload enters the object db anchored at its final name:
-- `refs/payloads/<cid>` -> blob. (A crash between the two calls
-- leaves one loose blob for the gc grace period)
exec {
    cmd = "git -C " .. REPO .. " hash-object -w " .. path,
}
exec {
    cmd = "git -C " .. REPO .. " update-ref refs/payloads/" .. cid .. " " .. blob,
}
os.remove(path)

-- snapshot state at the action commit itself
STATE.write(G, cid)

if ARGS.beg then
    -- a beg parks on its own ref, outside `main`: HEAD never moves
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/begs/beg-" .. cid .. " " .. cid,
    }
else
    GIT.tip(cid)
end

print(cid)
