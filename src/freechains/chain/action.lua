-- action files: one per action, inside the action commit itself:
--  - `actions/ab/<aid>.lua` (256 mechanical buckets: git stores
--    a tree object whole, so one flat dir would cost O(n^2))
--  - aid = git blob hash of the file, minted BEFORE the commit

local M = {}

-- tree path of action `aid`

function M.path (aid)
    return "actions/" .. aid:sub(1, 2) .. "/" .. aid .. ".lua"
end

-- `pre` expanded to a full aid: ids are printed abbreviated
-- (`list dag`), so a prefix must resolve, as git does with
-- commit hashes. Two chars name the bucket, so anything
-- shorter cannot resolve. Unknown or ambiguous prefixes are
-- returned unchanged: the caller fails on the id it was given

function M.full (pre)
    if (#pre == 40) or (#pre < 2) or (not pre:match("^%x+$")) then
        return pre
    end
    -- an action in history sits in its bucket; a pending beg
    -- is outside HEAD's tree, on its own ref
    local dir = exec { err=false, stderr=false,
        cmd = "ls " .. REPO .. "actions/" .. pre:sub(1, 2) .. "/" ..
            pre .. "*.lua",
    } or ""
    local begs = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " for-each-ref --format='%(refname)'" ..
            " 'refs/begs/beg-" .. pre .. "*'",
    } or ""
    local aid = nil
    for l in (dir .. "\n" .. begs):gmatch("[^\n]+") do
        local a = l:match("(%x+)%.lua$") or l:match("beg%-(%x+)$")
        if a and aid and (a ~= aid) then
            return pre      -- ambiguous
        end
        aid = a or aid
    end
    return aid or pre
end,

-- aid(cid): cid -> aid : aid of the action commit cid

function M.aid (cid)
    local out = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO ..
            " diff-tree --cc --no-commit-id -r --name-only " .. cid,
    }
    return out and out:match("actions/%x+/(%x+)%.lua")
end,

-- cid(aid): aid -> cid : the commit that added action `aid`,

function M.cid (aid)
    local out = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO ..
            " log --all --full-history -m --diff-filter=A --format=%H" ..
            " -- " .. ACTION.path(aid),
    }
    if not out then
        return nil
    end
    -- `-m` also lists a MERGE whose side brought the file in
    -- (its parent-1 diff shows it as added): the true adder is
    -- the OLDEST listed commit
    local cid
    for h in out:gmatch("%x+") do
        cid = h
    end
    return cid
end,

-- the action ancestors (as sorted aids) of the commit about to
-- be created, from its parents `ps` (revs). Structural: an
-- action IS a commit adding its action file; anything else
-- (genesis, plumbing merge) is transparent

function M.backs (ps)
    local ret = {}
    local see = {}
    local function rec (h)
        local a = ACTION.aid(h)
        if a then
            if not see[a] then
                see[a] = true
                ret[#ret+1] = a
            end
        else
            for _, p in ipairs(parents(h)) do
                rec(p)
            end
        end
    end
    for _, p in ipairs(ps) do
        rec(p)
    end
    table.sort(ret)
    return ret
end,

-- mint `T`'s aid: the file waits in `.git/` (worktree
-- untouched) until `pos` places it after `apply` accepts

function M.pre (T)
    local tmp = REPO .. ".git/action-tmp.lua"
    local f = io.open(tmp, "w")
    f:write(serial(T))
    f:close()
    return (exec {
        cmd = "git -C " .. REPO .. " hash-object " .. tmp,
    })
end,

-- place + stage the minted action file (the bucket dir may
-- not exist yet -- or may have been emptied by a reset)

function M.pos (aid)
    local path = ACTION.path(aid)
    exec {
        cmd = "mkdir -p " .. REPO .. "actions/" .. aid:sub(1, 2) .. "/",
    }
    os.rename(REPO .. ".git/action-tmp.lua", REPO .. path)
    exec {
        cmd = "git -C " .. REPO .. " add " .. path,
    }
end,

return M
