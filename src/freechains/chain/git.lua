local M = {}

--[[
-- The empty tree's hash, memoized.
-- All commits carry EMPTY trees, since all data lives in the commit MESSAGE.
-- Trees and blobs are not used by actions at all (the cid IS the commit).
-- Inputs:
--  - none
-- Outputs:
--  - [string]: 40-hex empty-tree hash
-- Errors:
--  - none
-- Callers:
--  - commit (git.lua): every minted commit uses it
--  - apply (action.lua): the anti-smuggling tree check
--]]
local tree
function M.tree ()
    if not tree then
        tree = exec {
            cmd = "git -C " .. REPO .. " hash-object -t tree /dev/null",
        }
    end
    return tree
end

--[[
-- Mint a commit via commit-tree (no worktree, no index).
-- Inputs:
--  - t [table]: commit data
--      - parents [table]:  {cid [, cid]} parent hashes
--      - msg [string?]:    message metadata or nil (merge)
--      - date [integer?]:  unix secs, author+committer DATE or nil (merge, genesis)
--      - sign [string?]:   ssh private key path -> -S gpgsig
--  - ref [boolean?]:   false, mints loose object only; else also moves HEAD
--  - err [string?]:    exec err message on failure
-- Outputs:
--  - [string]: the new commit's 40-hex cid
-- Errors:
--  - via exec: t.err or "bug found" on commit-tree failure
-- Callers:
--  - commit (action.lua): action mint
--  - recv (sync.lua): the loser-branch sync merge
--]]
function M.commit (t, ref, err)
    local dt = "GIT_AUTHOR_DATE='@"    .. (t.date or 0) .. " +0000' " ..
               "GIT_COMMITTER_DATE='@" .. (t.date or 0) .. " +0000' "
    local sig = t.sign and
        (" -c user.signingkey=" .. t.sign .. " -c gpg.format=ssh") or ""
    local ps = ""
    for _, p in ipairs(t.parents) do
        ps = ps .. " -p " .. p
    end
    local cid = exec {
        cmd = "printf '%s' '" .. (t.msg or "") .. "' | " ..
            dt .. "git -C " .. REPO .. sig .. " commit-tree" ..
            (t.sign and " -S" or "") .. ps .. " " .. M.tree(),
        err = err,
    }
    if ref ~= false then
        exec {
            cmd = "git -C " .. REPO .. " update-ref HEAD " .. cid,
        }
    end
    return cid
end

local MEMO = {}

--[[
-- Resolve a ref/rev (HEAD, HEAD^1, refs/...) to its cid.
-- Inputs:
--  - rev [string]: anything rev-parse accepts
-- Outputs:
--  - [string]: 40-hex commit hash
-- Errors:
--  - via exec: "bug found" if rev-parse fails
-- Callers:
--  - init (chain/init.lua): G = state at HEAD
--  - post/like: parents of the mint
--  - sync (sync.lua): tips and merge parents
--]]
function M.deref (rev)
    -- parenthesized: exec returns (out, code)
    return (exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. rev,
    })
end

--[[
-- The git parents of `cid`: one step back in the DAG, memoized
-- (immutable fact, so only pass DEREFED cids: HEAD^1 moves).
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed
-- Outputs:
--  - [table]: array of parent cids, empty for a root;
--    the MEMOIZED table itself: NEVER mutate it
-- Errors:
--  - via exec: "bug found" if rev-list fails (unknown cid)
-- Callers:
--  - backs/apply (action.lua): structural ancestry
--  - climb (consensus.lua): replay descent
--  - recv (sync.lua): beg parent validation
--  - list dag (list.lua): ups of each node
--]]
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
