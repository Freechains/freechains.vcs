local ssh = require "freechains.chain.ssh"

-- revoke/unrevoke are content-removal votes:
-- for action payloads, never authors
-- CLI: action -> aid
if (ARGS.target == "action") or ARGS.revoke or ARGS.unrevoke then
    ARGS.target = "aid"
end

ARGS.id = ARGS.id:match("^%s*(.-)%s*$")

-- an action target may be abbreviated (`list dag` prints it so);
-- an author target is a pubkey and passes through untouched
if ARGS.target == "aid" then
    ARGS.id = ACTION.full(ARGS.id)
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
local name = (ARGS.unrevoke and "unrevoke") or (ARGS.revoke and "revoke") or
             (ARGS.dislike and "dislike") or "like"

if ARGS.target == "author" then
    -- key string or key file (cli.md "Keys:")
    ARGS.id = ssh.pub.any(ARGS.id) or ARGS.id
    if #ARGS.id~=80 or (not ARGS.id:match("^ssh%-ed25519 %S+$")) then
        ERROR("chain " .. name .. " : invalid author key")
    end
end

-- detect if a positive `like` targets a beg on refs/begs/
-- (only `like` accepts begs; dislike/revoke/unrevoke do not)
local to_beg = (
    ARGS.like and (ARGS.target == "aid") and
        exec { err=false,
            cmd = "git -C " .. REPO .. " rev-parse --verify refs/begs/beg-" .. ARGS.id,
        } and true
)

-- beg: validate parent, merge into main, load beg entry
-- (the ref is named by the beg's aid)
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

-- the writer's own pubkey, read from the `.pub` file BEFORE the
-- commit: a bad key fails early, nothing enters the tree
local pub = ssh.pub.key(ARGS.sign)
if not pub then
    ERROR("chain " .. name .. " : invalid sign key")
end

local path = REPO .. ".git/payload-tmp"   -- why staging file

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

-- the parents of the commit about to be created: `backs` walks
-- them and `apply` folds its time peak over them
local ps = to_beg and { GIT.deref("HEAD"), GIT.deref(ref) }
                   or { GIT.deref("HEAD") }

-- action file: self-description; minted BEFORE the commit;
-- a beg like backs both sides of its merge.
-- ARGS.id is already the aid (or a pubkey): stored as is
local act = {
    action = kind,
    backs  = ACTION.backs(ps),
    sign   = pub,
    time   = tonumber(CMD.now),
    blob   = blob,
    [ARGS.target] = ARGS.id,
    n      = num,
}
local aid = ACTION.pre(act)

-- entry/was_revoked used after apply
local entry = (ARGS.target == "aid") and G.actions[ARGS.id] or nil
local was_revoked = entry and is_revoked(entry)

-- apply BEFORE the commit: a rejected vote leaves nothing
do
    local ok, err = apply(G, kind, act, {
        time = tonumber(CMD.now),
        aid  = aid,
        sign = pub,
        beg  = to_beg,
    })
    if not ok then
        ERROR("chain " .. name .. " : " .. err)
    end
    G.order[#G.order+1] = aid
end

-- the vote landed, so `entry` now carries the final sums, and
-- only a CROSSING matters:
--  - it entered REVOKED -> the bytes go (REMOVAL)
--  - it left REVOKED    -> the bytes must be here (LIFT)
if entry then
    if (not was_revoked) and is_revoked(entry) then
        exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " update-ref -d refs/payloads/" .. ARGS.id,
        }
    elseif was_revoked and (not is_revoked(entry)) then
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
                    ERROR("chain " .. name .. " : invalid path")
                end
                if blob ~= T.blob then
                    ERROR("chain " .. name .. " : blob mismatch")
                end
            end
            if have == false then
                if not ARGS.file then
                    ERROR("chain " .. name .. " : expected --file")
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

-- runs last to avoid --abort on errors
if to_beg then
    exec {
        cmd = "git -C " .. REPO .. " merge --no-ff --no-commit --no-edit " .. ref,
    }
end

ACTION.pos(aid)

-- the why enters the object db anchored at its final name
if blob then
    exec {
        cmd = "git -C " .. REPO .. " hash-object -w " .. path,
    }
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/payloads/" .. aid .. " " .. blob,
    }
    os.remove(path)
end

do
    local s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=ssh"
    exec {
        cmd = CMD.git .. "git -C " .. REPO .. s1 .. " commit -S --allow-empty-message -m ''",
        err = "chain " .. name .. " : invalid sign key",
    }
end

-- snapshot state at the new tip (the action commit itself)
STATE.write(G, GIT.deref("HEAD"))

if to_beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
    }
end

print(aid)
