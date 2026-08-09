require "freechains.chain.common"

-- Escape hatch for a hard fork: destroy the aid and everything after
-- it, so the settled remote branch can be received again.
-- Local only: no signing, no network, no reps.
-- Chain state lives in local snapshots (`.git/states/`), keyed by
-- commit: the reset lands on a tip whose snapshot already exists.

local cid = ACTION.cid(ARGS.aid)
if not cid then
    ERROR("chain destroy : invalid hash")
end

-- a beg is a post outside `main`, alone on its own aid-named ref:
-- nothing follows it, so destroying it is just deleting the ref
do
    local ref = "refs/begs/beg-" .. ARGS.aid
    local ok = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " show-ref --verify --quiet " .. ref,
    }
    if ok then
        exec {
            cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
        }
        print(ARGS.aid)
        os.exit(0)
    end
end

-- the commit must be part of our history, and must be a post/like/revoke:
-- the `state` commits in between are plumbing, never printed by `list`
do
    local ok = exec { stderr=false, err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. cid .. " HEAD",
    }
    local kind = trailer(cid)
    local is_post = (kind=='post' or kind=='like' or kind=='revoke')
    if (not ok) or (not is_post) then
        ERROR("chain destroy : invalid hash")
    end
end

-- a post is always committed on top of a valid tip: an action commit,
-- a merge, or the genesis. So its parent is where we land, no search
local tip = exec {
    cmd = "git -C " .. REPO .. " rev-parse " .. cid .. "^1",
}

-- report what is about to be destroyed: one aid per line, like
-- `list` (a beg-like merge is an action too, so merges stay in)
do
    local out = exec {
        cmd = "git -C " .. REPO .. " " ..
            "log --reverse --format='%H' " ..
            (tip .. "..HEAD"),
    }
    for h in out:gmatch("%x+") do
        if trailer(h) ~= 'state' then
            print(assert(ACTION.aid(h)))
        end
    end
end

-- settled posts can be destroyed: the hard-fork rule guards against a
-- REMOTE reorder, never against a deliberate local escape
exec {
    cmd = "git -C " .. REPO .. " reset --hard " .. tip,
    err = "chain destroy : git reset failed",
}

-- stale-beg cleanup: a beg is one commit (the post) on top of the
-- `main` it was created from. If that base is gone, the beg can no
-- longer attach to `main`, so destroy it.
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
