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

-- a bad key fails EARLY and clean: nothing reaches git
if ARGS.sign and (not ssh.pub.key(ARGS.sign)) then
    ERROR("chain post : invalid sign key")
end

-- the payload lives OUTSIDE the commit: a loose blob, anchored by
-- `refs/payloads/<cid>`. The action's `blob` field is what binds
-- it: the cid transitively commits to the content

local path = REPO .. "payload-tmp"   -- payload staging file (git dir)

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

-- save payload and commit
-- both UNANCHORED: rejection leaves them gc-able

local blob = exec {
    cmd = "git -C " .. REPO .. " hash-object -w " .. path,
}
os.remove(path)

local cid = ACTION.commit(
    (ARGS.sign and "chain post : invalid sign key") or nil,
    {
        parents = { GIT.deref("HEAD") },
        action  = 'post',
        blob    = blob,
        sign    = ARGS.sign,
    }
)

-- ONE pipeline for write and replay:
--  - re-reads the action from minted commit
--  - applies, orders, snapshots state

local ok, err = pcall(ACTION.apply, G, cid, ARGS.beg)
if not ok then
    ERROR("chain post : " .. err:gsub("^invalid %a+ : ", ""))
end

-- ACCEPTED: anchor payload, post

exec {
    cmd = "git -C " .. REPO .. " update-ref refs/payloads/" .. cid .. " " .. blob,
}

if ARGS.beg then
    -- a beg parks on its own ref, outside `main`: HEAD never moves
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/begs/beg-" .. cid .. " " .. cid,
    }
else
    exec {
        cmd = "git -C " .. REPO .. " update-ref HEAD " .. cid,
    }
end

print(cid)
