--[[
-- `chain <alias> like|dislike|revoke|unrevoke`
-- Mint a vote, accept it via the pipeline, handle beg promotion and the
-- REMOVAL/LIFT payload crossings, move HEAD.
-- Inputs:
--  - ARGS.like/dislike/revoke/unrevoke [boolean]: the vote
--  - ARGS.number [integer]: magnitude (> 0)
--  - ARGS.target [string]: "action"|"author"
--  - ARGS.id  [string]: target cid (may be short) or pubkey
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

-- revoke/unrevoke are content-removal votes:
-- for action payloads, never authors.
-- CLI `action` -> `cid`: ARGS.target names the message FIELD;
-- the value stays ARGS.id (a cid or a pubkey)
if (ARGS.target == "action") or ARGS.revoke or ARGS.unrevoke then
    ARGS.target = "cid"
end

ARGS.id = ARGS.id:match("^%s*(.-)%s*$")

-- num: dislike and revoke remove reps; like and unrevoke add reps
local num = ARGS.number
if ARGS.dislike or ARGS.revoke then
    num = -num
end

-- the message verb distinguishes a revoke-axis vote from a
-- like/dislike; the sign of `n` picks the direction
local kind = (ARGS.revoke or ARGS.unrevoke) and "revoke" or "like"

-- for errors
local vote = (ARGS.unrevoke and "unrevoke") or (ARGS.revoke and "revoke") or
             (ARGS.dislike and "dislike") or "like"

if (ARGS.target ~= "cid") and (ARGS.target ~= "author") then
    ERROR("chain " .. vote .. " : invalid target")
end

-- an action target may be abbreviated (`list dag` prints it so);
-- an author target is a pubkey and passes through untouched
if ARGS.target == "cid" then
    ARGS.id = ACTION.full(ARGS.id)
        or ERROR("chain " .. vote .. " : invalid target")
end

if ARGS.target == "author" then
    -- key string or key file (cli.md "Keys:")
    ARGS.id = SSH.pub(ARGS.id) or ARGS.id
    if #ARGS.id~=80 or (not ARGS.id:match("^ssh%-ed25519 %S+$")) then
        ERROR("chain " .. vote .. " : invalid author key")
    end
end

-- detect if a positive `like` targets a beg on refs/begs/
-- (only `like` accepts begs; dislike/revoke/unrevoke do not)
local to_beg = (
    ARGS.like and (ARGS.target == "cid") and
        exec { err=false,
            cmd = "git -C " .. REPO .. " rev-parse --verify refs/begs/beg-" .. ARGS.id,
        } and true
)

-- beg: validate parent, merge into main, load beg entry
-- (the ref is named by the beg's cid)
local ref = "refs/begs/beg-" .. ARGS.id
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
    G.order[#G.order+1] = ARGS.id   -- beg post
    G.actions[ARGS.id] = STATE.read(GIT.deref(ref)).actions[ARGS.id]
end

-- a bad key fails EARLY and clean: nothing reaches git
if not SSH.pub(ARGS.sign) then
    ERROR("chain " .. vote .. " : invalid sign key")
end

-- save payload (--why) and commit
-- both UNANCHORED: rejection leaves them gc-able

local blob
if ARGS.why then
    local path = REPO .. "payload-tmp"   -- why staging file (git dir)
    local f = io.open(path, "w")
    f:write(ARGS.why)
    f:close()
    blob = exec {
        cmd = "git -C " .. REPO .. " hash-object -w " .. path,
    }
    os.remove(path)
end

local cid = ACTION.commit(
    "chain " .. vote .. " : invalid sign key",
    {
        parents = to_beg and { GIT.deref("HEAD"), GIT.deref(ref) }
                          or { GIT.deref("HEAD") },
        action  = kind,
        n       = num,
        [ARGS.target] = ARGS.id,
        blob    = blob,
        sign    = ARGS.sign,
    }
)

-- entry/was_revoked used after the pipeline
local entry = (ARGS.target == "cid") and G.actions[ARGS.id] or nil
local was_revoked = entry and RULES.is_revoked(entry)

-- ONE pipeline for write and replay:
--  - re-reads the action from minted commit
--  - applies, orders, snapshots state

local ok, err = pcall(ACTION.apply, G, cid, false)
if not ok then
    ERROR("chain " .. vote .. " : " .. err:gsub("^invalid %a+ : ", ""))
end

-- the vote landed, so `entry` now carries the final sums, and
-- only a CROSSING matters:
--  - it entered REVOKED -> the bytes go (REMOVAL)
--  - it left REVOKED    -> the bytes must be here (LIFT)
if entry then
    if (not was_revoked) and RULES.is_revoked(entry) then
        exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " update-ref -d refs/payloads/" .. ARGS.id,
        }
    elseif was_revoked and (not RULES.is_revoked(entry)) then
        -- every post carries a payload, a vote only with `--why`:
        -- with no bytes to restore there is nothing to gate
        local T = ACTION.read(true, ARGS.id)
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
                    ARGS.id .. " " .. T.blob,
            }
        end
    end
end

-- accepted: the why is anchored at its final name
if blob then
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/payloads/" .. cid .. " " .. blob,
    }
end

-- ACCEPTED: anchor payload, post

if to_beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
    }
end

exec {
    cmd = "git -C " .. REPO .. " update-ref HEAD " .. cid,
}
STATE.tip_write(G, cid)

print(cid)
