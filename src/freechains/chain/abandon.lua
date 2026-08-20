
-- Escape hatch for a hard fork: abandon the aid and everything after
-- it, so the settled remote branch can be received again.
-- Local only: no signing, no network, no reps.
-- Chain state lives in local snapshots (`refs/states/*`), keyed by
-- commit: the reset lands on a tip whose snapshot already exists.
--
-- Two forms:
--  - `abandon <aid>`: aid is first DROPPED
--  - `abandon --keep <aid>`: aid is the last KEPT
-- In both cases, only a linear suffix may go (crossing a sync merge would also
-- drop sibling branch).

-- the aid may be abbreviated (`list dag` prints it so)
ARGS.aid = ACTION.full(ARGS.aid)

local cid = ACTION.cid(ARGS.aid)
if not cid then
    ERROR("chain abandon : invalid action")
end

-- a beg is a post outside `main`, alone on its own aid-named ref:
-- nothing follows it, so abandoning it is just deleting the ref
do
    local ref = "refs/begs/beg-" .. ARGS.aid
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
        print(ARGS.aid)
        os.exit(0)
    end
end

-- the commit must be part of our history (resolution already
-- proves it is an action: it adds the aid's file)
do
    local ok = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. cid .. " HEAD",
    }
    if not ok then
        ERROR("chain abandon : invalid action")
    end
end

-- where we land: the kept aid itself, or the dropped aid's parent
-- (a post is always committed on top of a valid tip, no search)
local tip
if ARGS.keep then
    tip = cid
else
    tip = exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. cid .. "^1",
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

-- only a LINEAR suffix may go: a commit without an aid is a sync
-- merge, and crossing it would also drop the sibling branch
local aids = {}
for _, h in ipairs(range) do
    aids[h] = ACTION.aid(h)
    if not aids[h] then
        ERROR("chain abandon : unexpected merge")
    end
end

-- report what is about to be abandoned: one aid per line, like
-- `list` (a beg-like merge is an action too, so merges stay in)
for _, h in ipairs(range) do
    local a = aids[h]
    if a then
        -- payloads go with them
        exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " update-ref -d refs/payloads/" .. a,
        }
        print(a)
    end
end

-- settled posts can be abandoned: the hard-fork rule guards against a
-- REMOTE reorder, never against a deliberate local escape
exec {
    cmd = "git -C " .. REPO .. " reset --hard " .. tip,
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
