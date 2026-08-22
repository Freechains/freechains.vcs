--[[
-- `chain <alias> like|dislike|revoke|unrevoke`
-- Mint a vote, accept it via the pipeline, handle beg promotion and the
-- REMOVAL/LIFT payload crossings, move HEAD.
-- Inputs:
--  - ARGS.like/dislike/revoke/unrevoke [boolean]: the vote
--  - ARGS.number [integer]: magnitude (> 0)
--  - ARGS.target [string]: "action"|"author"
--  - ARGS.cid  [string]: target cid (may be short) or pubkey
--  - ARGS.why  [string?]: optional reason payload
--  - ARGS.file [string?]: payload restore fallback (LIFT)
--  - ARGS.sign [string]: ssh private key path
--  - ARGS.now  [integer]: the action's TIME (commit DATE)
--  - G    [table]: state at HEAD; MUTATED by the pipeline
--  - REPO [string]: the chain's bare repo dir
-- Outputs:
--  - stdout: the new cid
--  - refs: HEAD -> cid; state at refs/states/<cid>; why blob at
--    refs/payloads/<cid>; the TARGET's payload anchor dropped
--    (entered REVOKED) or restored (left REVOKED); a liked beg's
--    refs/begs/ ref deleted (promotion merge)
-- Errors:
--  - "chain <vote> : invalid target"
--  - "chain <vote> : invalid author key"
--  - "chain <vote> : invalid sign key"
--  - "chain <vote> : invalid path" | "blob mismatch" |
--                    "expected --file" : LIFT payload restore
--  - "chain <vote> : <rules>" : refused by the pipeline
-- Callers:
--  - dispatch (chain/init.lua): ARGS.like/dislike/
--    revoke/unrevoke
--]]

local ssh = require "freechains.chain.ssh"

-- revoke/unrevoke are content-removal votes:
-- for action payloads, never authors
-- CLI: action -> cid
if (ARGS.target == "action") or ARGS.revoke or ARGS.unrevoke then
    ARGS.target = "cid"
end

ARGS.cid = ARGS.cid:match("^%s*(.-)%s*$")

-- an action target may be abbreviated (`list dag` prints it so);
-- an author target is a pubkey and passes through untouched
if ARGS.target == "cid" then
    ARGS.cid = ACTION.full(ARGS.cid)
end

-- num: dislike and revoke remove reps; like and unrevoke add reps
local num = ARGS.number
if ARGS.dislike or ARGS.revoke then
    num = -num
end

-- the action file + vote dir distinguish a revoke-axis vote
-- from a like/dislike (see the commit block below)
local kind = (ARGS.revoke or ARGS.unrevoke) and "revoke" or "like"

-- for errors
local vote = (ARGS.unrevoke and "unrevoke") or (ARGS.revoke and "revoke") or
             (ARGS.dislike and "dislike") or "like"

if (ARGS.target ~= "cid") and (ARGS.target ~= "author") then
    ERROR("chain " .. vote .. " : invalid target")
end

if ARGS.target == "author" then
    -- key string or key file (cli.md "Keys:")
    ARGS.cid = ssh.pub.any(ARGS.cid) or ARGS.cid
    if #ARGS.cid~=80 or (not ARGS.cid:match("^ssh%-ed25519 %S+$")) then
        ERROR("chain " .. vote .. " : invalid author key")
    end
end

-- detect if a positive `like` targets a beg on refs/begs/
-- (only `like` accepts begs; dislike/revoke/unrevoke do not)
local to_beg = (
    ARGS.like and (ARGS.target == "cid") and
        exec { err=false,
            cmd = "git -C " .. REPO .. " rev-parse --verify refs/begs/beg-" .. ARGS.cid,
        } and true
)

-- beg: validate parent, merge into main, load beg entry
-- (the ref is named by the beg's cid)
local ref = "refs/begs/beg-" .. ARGS.cid
if to_beg then
    local up = exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%P " .. ref,
    }
    local _,ok = exec { err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. up .. " HEAD",
    }
    if ok ~= 0 then
        error("TODO : bug found : branch should not exist in the first place")
        --exec("git -C " .. REPO .. " update-ref -d " .. ref)
        --ERROR("chain like : invalid target : beg post does not exist")
    end
    G.order[#G.order+1] = ARGS.cid   -- beg post
    G.actions[ARGS.cid] = STATE.read(GIT.deref(ref)).actions[ARGS.cid]
end

-- the writer's own pubkey, read from the `.pub` file BEFORE the
-- commit: a bad key fails early, nothing enters the tree
local pub = ssh.pub.key(ARGS.sign)
if not pub then
    ERROR("chain " .. vote .. " : invalid sign key")
end

local path = REPO .. "payload-tmp"   -- why staging file (git dir)

local blob
if ARGS.why then
    local f = io.open(path, "w")
    f:write(ARGS.why)
    f:close()
    -- DRY hash: nothing enters the object db before `apply`
    blob = exec {
        cmd = "git -C " .. REPO .. " hash-object " .. path,
    }
end

-- the parents of the commit about to be minted: `backs` derives
-- from them; a beg like parents both sides of its merge
local ps = to_beg and { GIT.deref("HEAD"), GIT.deref(ref) }
                   or { GIT.deref("HEAD") }

-- the action IS the commit message; minted UNREFERENCED
-- (the cid IS the commit), so a rejection leaves one gc-able loose commit.
-- time = the commit DATE; sign = the gpgsig: not in the message.
-- ARGS.cid is already the cid (or a pubkey): stored as is
local act = {
    action = kind,
    sign   = pub,
    time   = tonumber(CMD.now),
    blob   = blob,
    [ARGS.target] = ARGS.cid,
    n      = num,
}
local cid = ACTION.pre {
    act     = act,
    parents = ps,
    sign    = ARGS.sign,
    err     = "chain " .. vote .. " : invalid sign key",
}

-- entry/was_revoked used after apply
local entry = (ARGS.target == "cid") and G.actions[ARGS.cid] or nil
local was_revoked = entry and is_revoked(entry)

-- apply BEFORE HEAD moves: a rejected vote leaves nothing anchored
do
    local ok, err = apply(G, kind, act, {
        time  = ARGS.now,
        cid   = cid,
        sign  = pub,
        beg   = to_beg,
        backs = ACTION.backs(ps),
    })
    if not ok then
        ERROR("chain " .. vote .. " : " .. err)
    end
    G.order[#G.order+1] = cid
end

-- the vote landed, so `entry` now carries the final sums, and
-- only a CROSSING matters:
--  - it entered REVOKED -> the bytes go (REMOVAL)
--  - it left REVOKED    -> the bytes must be here (LIFT)
if entry then
    if (not was_revoked) and is_revoked(entry) then
        exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " update-ref -d refs/payloads/" .. ARGS.cid,
        }
    elseif was_revoked and (not is_revoked(entry)) then
        -- every post carries a payload, a vote only with `--why`:
        -- with no bytes to restore there is nothing to gate
        local T = ACTION.read(true, ARGS.cid)
        if T.blob then
            local have = exec { err=false, stderr=false,
                cmd = "git -C " .. REPO .. " cat-file -e " .. T.blob,
            }
            -- `--file` is a blind fallback:
            -- 	- caller cannot see the store, redundant is fine
            -- 	- a WRONG one is not
            if ARGS.file then
                local blob = exec { err=false, stderr=false,
                    cmd = "git -C " .. REPO .. " hash-object '" .. ARGS.file .. "'",
                }
                if blob == false then
                    ERROR("chain " .. vote .. " : invalid path")
                end
                if blob ~= T.blob then
                    ERROR("chain " .. vote .. " : blob mismatch")
                end
            end
            if have == false then
                if not ARGS.file then
                    ERROR("chain " .. vote .. " : expected --file")
                end
                -- verified above: only now do the bytes enter the db
                exec {
                    cmd = "git -C " .. REPO .. " hash-object -w '" .. ARGS.file .. "'",
                }
            end
            -- a standing post always has its anchor: the bytes may
            -- still be in the store, but unreferenced they are one
            -- `sweep` away from gone
            exec {
                cmd = "git -C " .. REPO .. " update-ref refs/payloads/" ..
                    ARGS.cid .. " " .. T.blob,
            }
        end
    end
end

-- the why enters the object db anchored at its final name
if blob then
    exec {
        cmd = "git -C " .. REPO .. " hash-object -w " .. path,
    }
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/payloads/" .. cid .. " " .. blob,
    }
    os.remove(path)
end

-- accepted: the minted commit becomes the tip (a beg like IS the
-- merge: `ps` carries both sides as its parents)
GIT.tip(cid)

-- snapshot state at the new tip (the action commit itself)
STATE.write(G, cid)

if to_beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
    }
end

print(cid)
