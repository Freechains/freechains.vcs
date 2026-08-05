require "freechains.chain.common"

-- Escape hatch for a hard fork: destroy `aid` and everything after it, so
-- the settled remote branch can be received again.
-- Local only: no signing, no network, no reps.
-- Chain state lives in-tree (`.freechains/state.lua`), so the reset
-- restores it along with the commits: nothing else to rebuild.

-- a beg is a post outside `main`, alone on its own ref: nothing follows
-- it, so destroying it is just deleting the ref
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

-- the aid must name an action in our history: its commit anchors the
-- reset below
local cid = CID(ARGS.aid)
if not cid then
    ERROR("chain destroy : invalid id")
end

-- a post is always committed on top of a valid tip: a `state` commit, a
-- merge, or the genesis. So its parent is where we land, no search
local tip = exec {
    cmd = "git -C " .. REPO .. " rev-parse " .. cid .. "^1",
}

-- report what is about to be destroyed: one aid per line, like `list`
do
    local out = exec {
        cmd = "git -C " .. REPO .. " " ..
            "log --reverse --no-merges --format='%H' " ..
            (tip .. "..HEAD"),
    }
    for h in out:gmatch("%x+") do
        if trailer(h) ~= 'state' then
            print(assert(COMMIT_ACTION(h)))
        end
    end
end

-- settled posts can be destroyed: the hard-fork rule guards against a
-- REMOTE reorder, never against a deliberate local escape
exec {
    cmd = "git -C " .. REPO .. " reset --hard " .. tip,
    err = "chain destroy : git reset failed",
}

-- stale-beg cleanup: a beg is two commits (post + state) on top of the
-- `main` it was created from. If that base is gone, the beg can no
-- longer attach to `main`, so destroy it.
do
    local out = exec {
        cmd = "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(refname) %(objectname)'",
    }
    for refname, beg in out:gmatch("(%S+)%s+(%S+)") do
        local ok = exec { stderr=false, err=false,
            cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. beg .. "~2 HEAD",
        }
        if not ok then
            exec {
                cmd = "git -C " .. REPO .. " update-ref -d " .. refname,
            }
        end
    end
end
