--[[
-- `chain <alias> abandon [--keep] <id>`
-- Drops a linear suffix of actions (the hard-fork escape hatch), or delete a
-- parked beg.
-- Inputs:
--  - ARGS.cid  [string]: the boundary cid (may be short)
--  - ARGS.keep [boolean?]: cid is the last KEPT (or first DROPPED)
--  - REPO [string]: the chain's repo dir
-- Outputs:
--  - stdout: the dropped cids, oldest first (or the beg cid)
--  - refs: HEAD reset to the kept tip; the dropped commits'
--    refs/states/ + refs/payloads/ deleted; stale begs deleted
-- Errors:
--  - "chain abandon : invalid action" : not action, not in history, --keep beg
--  - "chain abandon : unexpected merge" : suffix not linear
-- Callers:
--  - dispatch (chain/init.lua): ARGS.abandon
--]]

-- Escape hatch for a hard fork: abandon the cid and everything after
-- it, so the settled remote branch can be received again.
-- Local only: no signing, no network, no reps.
-- Chain state: the landing tip's state is re-derived on the next
-- command (CONSENSUS.state: nearest anchor + bounded replay).
--
-- Two forms:
--  - `abandon <cid>`: cid is first DROPPED
--  - `abandon --keep <cid>`: cid is the last KEPT
-- In both cases, only a linear suffix may go (crossing a sync merge would also
-- drop sibling branch).

-- the cid may be abbreviated (`list dag` prints it so)
ARGS.cid = ACTION.full(ARGS.cid)

if not (ARGS.cid and ACTION.is(ARGS.cid)) then
    ERROR("chain abandon : invalid action")
end

-- a beg is a post outside `main`, alone on its own cid-named ref:
-- nothing follows it, so abandoning it is just deleting the ref
do
    local ref = "refs/begs/beg-" .. ARGS.cid
    local ok = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " show-ref --verify --quiet " .. ref,
    }
    if ok then
        -- a beg is not in `main`: there is nothing to keep up to
        if ARGS.keep then
            ERROR("chain abandon : invalid action")
        end
        exec {
            cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
        }
        print(ARGS.cid)
        os.exit(0)
    end
end

-- the commit must be part of our history (resolution already
-- proves it is an action)
do
    local ok = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. ARGS.cid .. " HEAD",
    }
    if not ok then
        ERROR("chain abandon : invalid action")
    end
end

-- where we land: the kept cid itself, or the dropped cid's parent
-- (a post is always committed on top of a valid tip, no search)
local tip
if ARGS.keep then
    tip = ARGS.cid
else
    tip = exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. ARGS.cid .. "^1",
    }
end

-- the dropped range, oldest first
local range = {}
do
    local out = exec {
        cmd = "git -C " .. REPO .. " " ..
            "log --reverse --format='%H' " ..
            (tip .. "..HEAD"),
    }
    for h in out:gmatch("%x+") do
        range[#range+1] = h
    end
end

-- only a LINEAR suffix may go: a commit without an cid is a sync
-- merge, and crossing it would also drop the sibling branch
for _, h in ipairs(range) do
    if not ACTION.is(h) then
        ERROR("chain abandon : unexpected merge")
    end
end

-- report what is about to be abandoned: one cid per line, like
-- `list` (every commit in range is an action: checked above)
for _, h in ipairs(range) do
    -- the dropped commit's state blob loses its anchor, so gc can
    -- reclaim it (state lives in refs/states/<cid>, keyed by commit)
    exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " update-ref -d refs/states/" .. h,
    }
    -- payloads go with them
    exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " update-ref -d refs/payloads/" .. h,
    }
    print(h)
end

-- settled posts can be abandoned: the hard-fork rule guards against a
-- REMOTE reorder, never against a deliberate local escape
exec {
    cmd = "git -C " .. REPO .. " update-ref HEAD " .. tip,
}

-- stale-beg cleanup: a beg is one commit (the post) on top of the
-- `main` it was created from. If that base is gone, the beg can no
-- longer attach to `main`, so abandon it.
do
    local out = exec {
        cmd = "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(refname) %(objectname)'",
    }
    for refname, beg in out:gmatch("(%S+)%s+(%S+)") do
        local ok = exec { stderr=false, err=false,
            cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. beg .. "~1 HEAD",
        }
        if not ok then
            exec {
                cmd = "git -C " .. REPO .. " update-ref -d " .. refname,
            }
        end
    end
end
