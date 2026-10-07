local M = {}

--[[
-- The empty tree's hash.
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
-- the SHA-1 of the empty tree is a constant of git itself
-- (`git hash-object -t tree /dev/null`); every chain repo is SHA-1
local tree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
function M.tree ()
    return tree
end

--[[
-- Mint a commit via commit-tree (no worktree, no index).
-- Inputs:
--  - ref [boolean]:    true also moves HEAD; false mints loose only
--  - err [string?]:    exec err message on failure (nil: bug found)
--  - t [table]: commit data (what shapes the commit BYTES)
--      - parents [table]:  {cid [, cid]} parent hashes
--      - msg [string?]:    message metadata or nil (merge)
--      - date [integer?]:  unix secs, author+committer DATE or nil (merge, genesis)
--      - sign [string?]:   ssh private key path -> -S gpgsig
-- Outputs:
--  - [string]: the new commit's 40-hex cid
-- Errors:
--  - via exec: `err` or "bug found" on commit-tree failure
-- Callers:
--  - commit (action.lua): action mint
--  - recv (sync.lua): the loser-branch sync merge
--]]
function M.commit (ref, err, t)
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
    if ref then
        exec {
            cmd = "git -C " .. REPO .. " update-ref HEAD " .. cid,
        }
    end
    return cid
end

local MEMO = {}
local OBJS = {}

--[[
-- The raw commit object of `cid` (headers, blank line, message),
-- memoized: one `cat-file` serves every parse of the same commit
-- (ACTION.is/read, the parents, the tree, the signature).
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed (immutable fact)
-- Outputs:
--  - [string?]: the object text, nil if `cid` is not a commit
--    (misses are not memoized: a fetch may bring it later)
-- Errors:
--  - none
-- Callers:
--  - parents/tree_of (git.lua): the header lines
--  - is/read (action.lua): the message
--  - signer (ssh.lua): the gpgsig header
--]]
function M.cat (cid)
    local out = OBJS[cid]
    if out == nil then
        out = exec { trim=false, err=false, stderr=false,
            cmd = "git -C " .. REPO .. " cat-file commit " .. cid,
        }
        if out then
            OBJS[cid] = out
        else
            out = nil
        end
    end
    return out
end

--[[
-- Memoize many commit objects in ONE `cat-file --batch` (a pull
-- reads every new commit several times: parents, parse, signature).
-- Inputs:
--  - cids [table]: array of 40-hex commit hashes
-- Outputs:
--  - none: `cat` serves them from memory
-- Errors:
--  - via exec: "bug found" if cat-file fails
-- Callers:
--  - recv (sync.lua): the remote's new commits
--]]
function M.cats (cids)
    local want = {}
    for _, cid in ipairs(cids) do
        if not OBJS[cid] then
            want[#want+1] = cid
        end
    end
    if #want == 0 then
        return
    end
    local path = REPO .. "git-stdin"
    local f = assert(io.open(path, "w"))
    f:write(table.concat(want, "\n"), "\n")
    f:close()
    local out = exec { trim=false,
        cmd = "git -C " .. REPO .. " cat-file --batch < " .. path,
    }
    os.remove(path)
    -- "<sha> <type> <size>\n<bytes>\n" per object, or "<sha> missing\n"
    local pos = 1
    while pos <= #out do
        local nl = out:find("\n", pos, true)
        local sha, ty, size = out:sub(pos, nl-1):match("^(%x+) (%a+) (%d+)$")
        if sha then
            size = tonumber(size)
            if ty == "commit" then
                OBJS[sha] = out:sub(nl+1, nl+size)
            end
            pos = nl + size + 2
        else
            pos = nl + 1
        end
    end
end

--[[
-- The tree of commit `cid`, from its header.
-- Inputs:
--  - cid [string]: 40-hex commit hash, derefed
-- Outputs:
--  - [string?]: 40-hex tree hash, nil if not a commit
-- Errors:
--  - none
-- Callers:
--  - apply (action.lua): the anti-smuggling tree check
--]]
function M.tree_of (cid)
    local out = M.cat(cid)
    return out and out:match("^tree (%x+)\n")
end

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
--  - "bug found : not a commit" : unknown cid
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
    -- the header lines, before the first blank line:
    --   tree <hash>
    --   parent <hash>      (0: root, 1: action, 2: merge)
    local out = M.cat(cid)
    if not out then
        error("bug found : not a commit : " .. cid)
    end
    local ps = {}
    for h in out:match("^(.-)\n\n"):gmatch("\nparent (%x+)") do
        ps[#ps+1] = h
    end
    MEMO[cid] = ps
    return ps
end

return M
