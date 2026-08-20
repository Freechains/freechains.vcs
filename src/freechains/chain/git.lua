-- immutable commit facts, straight from git, memoized:
--  - a commit's parents never change
--  - only derefed cids are accepted (`HEAD^1` moves): deref first

local M = {}

-- Commit without a worktree (chain repos are BARE):
--  - tree: the single parent's tree, or `merge-tree` of two parents
--    (trees only ever gain action files, so the merge is clean)
--  - `add`: stages one extra blob (the action file) on top
--  - `commit-tree` + `update-ref HEAD`: replaces porcelain
--    `merge`/`commit`, which require a worktree
--  - message read from /dev/null: empty, as porcelain produced
-- t = { parents={cid [, cid]}, add={blob=,path=} | nil,
--       sign=keypath | nil, err=msg | nil }

function M.commit (t)
    local base
    if t.parents[2] then
        base = exec {
            cmd = "git -C " .. REPO .. " merge-tree --write-tree " ..
                t.parents[1] .. " " .. t.parents[2],
        }
    else
        base = t.parents[1] .. "^{tree}"
    end
    exec {
        cmd = "git -C " .. REPO .. " read-tree '" .. base .. "'",
    }
    if t.add then
        exec {
            cmd = "git -C " .. REPO .. " update-index --add --cacheinfo " ..
                "100644," .. t.add.blob .. "," .. t.add.path,
        }
    end
    local tree = exec {
        cmd = "git -C " .. REPO .. " write-tree",
    }
    local sig = t.sign and
        (" -c user.signingkey=" .. t.sign .. " -c gpg.format=ssh") or ""
    local ps = ""
    for _, p in ipairs(t.parents) do
        ps = ps .. " -p " .. p
    end
    local cid = exec {
        cmd = CMD.git .. "git -C " .. REPO .. sig .. " commit-tree" ..
            (t.sign and " -S" or "") .. ps .. " " .. tree .. " < /dev/null",
        err = t.err,
    }
    exec {
        cmd = "git -C " .. REPO .. " update-ref HEAD " .. cid,
    }
    return cid
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
