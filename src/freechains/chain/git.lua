-- immutable commit facts, straight from git, memoized:
--  - a commit's parents never change
--  - only derefed cids are accepted (`HEAD^1` moves): deref first

local M = {}

-- Every commit carries the EMPTY tree: the protocol lives in the
-- commit MESSAGE (an action table; empty for a sync merge). Trees
-- and blobs are not used by actions at all (the cid IS the commit).
local TREE = nil
function M.tree ()
    TREE = TREE or exec {
        cmd = "git -C " .. REPO .. " hash-object -t tree /dev/null",
    }
    return TREE
end
local tree = M.tree

-- Mint a commit (no worktree, no index):
--  - `msg`: path of the message file (the action), or nil (merge)
--  - `date`: unix secs -> the action's signed TIME (author +
--    committer date); nil = the neutral @0 (merges)
--  - `ref` = false: mint the loose object only, do NOT move HEAD
--    (an action is minted BEFORE `apply`; a rejected one stays
--    unreferenced, one gc away from gone)
-- t = { parents={cid [, cid]}, msg=path | nil, date=secs | nil,
--       ref=false | nil, sign=keypath | nil, err=msg | nil }

function M.commit (t)
    local dt = "GIT_AUTHOR_DATE='@"    .. (t.date or 0) .. " +0000' " ..
               "GIT_COMMITTER_DATE='@" .. (t.date or 0) .. " +0000' "
    local sig = t.sign and
        (" -c user.signingkey=" .. t.sign .. " -c gpg.format=ssh") or ""
    local ps = ""
    for _, p in ipairs(t.parents) do
        ps = ps .. " -p " .. p
    end
    local cid = exec {
        cmd = dt .. "git -C " .. REPO .. sig .. " commit-tree" ..
            (t.sign and " -S" or "") .. ps .. " " .. tree() ..
            " < " .. (t.msg or "/dev/null"),
        err = t.err,
    }
    if t.ref ~= false then
        exec {
            cmd = "git -C " .. REPO .. " update-ref HEAD " .. cid,
        }
    end
    return cid
end

-- point HEAD at a minted commit (the accepted-action second half)

function M.tip (cid)
    exec {
        cmd = "git -C " .. REPO .. " update-ref HEAD " .. cid,
    }
end

local MEMO = {}

-- ref (HEAD) -> derefed cid

function M.deref (rev)
    -- parenthesized: exec returns (out, code)
    return (exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. rev,
    })
end

-- the git parents of `cid`: one step back in the DAG, no time
-- involved. Returns an array (empty for a root).
-- NEVER mutate the result

function M.parents (cid)
    if MEMO[cid] then
        return MEMO[cid]
    end
    local out = exec {
        cmd = "git -C " .. REPO .. " rev-list --parents -1 " .. cid,
        -- $ git rev-list --parents -1 a1b2c3...
        -- a1b2c3... d4e5f6... 7890ab...  # merge: 2 parents
    }
    local ps = {}
    for h in out:gmatch("%x+") do
        ps[#ps+1] = h
    end
    table.remove(ps, 1)
    MEMO[cid] = ps
    return ps
end

return M
