local GIT = require "freechains.chain.git"

-- action files: one per action, inside the action commit itself:
--  - `actions/ab/<aid>.lua` (256 mechanical buckets: git stores
--    a tree object whole, so one flat dir would cost O(n^2))
--  - aid = git blob hash of the file, minted BEFORE the commit

local M = {}

-- tree path of action `aid`

function M.path (aid)
    return "actions/" .. aid:sub(1, 2) .. "/" .. aid .. ".lua"
end

-- the action table of `aid`: the aid IS the blob hash, so the
-- object is the file
--  - asr = true  : asserts (my own history, so it is a bug)
--  - asr = false : nil if it does not load (untrusted input)

function M.read (asr, aid)
    local out = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " cat-file blob " .. aid
    }
    if out then
        -- "t": text only (a binary chunk can crash the VM)
        -- {} : no globals (the file is DATA, not a program)
        local f = load(out, "=action", "t", {})
        if f then
            local ok, t = pcall(f)
            if ok then
                if type(t) == 'table' then
                    -- `blob` is the one field no rule checks, and it
                    -- reaches a shell: a hash, or nothing
                    local b = t.blob
                    if b==nil or (type(b)=='string' and b:match("^%x+$")) then
                        return t
                    end
                end
            end
        end
    end
    if asr then
        error("bug found : no action : " .. aid)
    end
    return nil
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
    -- an action in history sits in its bucket (in HEAD's tree);
    -- a pending beg is outside HEAD's tree, on its own ref
    local dir = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " ls-tree --name-only" ..
            " 'HEAD:actions/" .. pre:sub(1, 2) .. "'",
    } or ""
    local begs = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " for-each-ref --format='%(refname)'" ..
            " 'refs/begs/beg-" .. pre .. "*'",
    } or ""
    local aid = nil
    for l in (dir .. "\n" .. begs):gmatch("[^\n]+") do
        local a = l:match("^(%x+)%.lua$") or l:match("beg%-(%x+)$")
        if a and (a:sub(1, #pre) == pre) then
            if aid and (a ~= aid) then
                return pre      -- ambiguous
            end
            aid = a
        end
    end
    return aid or pre
end

-- aid(cid): cid -> aid : aid of the action commit cid

function M.aid (cid)
    local out = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO ..
            " diff-tree --cc --no-commit-id -r --name-only " .. cid,
    }
    return out and out:match("actions/%x+/(%x+)%.lua")
end

-- cid(aid): aid -> cid : the commit that added action `aid`,

function M.cid (aid)
    local out = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO ..
            " log --all --full-history -m --diff-filter=A --format=%H" ..
            " -- " .. M.path(aid),
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
end

-- the action ancestors (as sorted aids) of the commit about to
-- be created, from its parents `ps` (revs). Structural: an
-- action IS a commit adding its action file; anything else
-- (genesis, plumbing merge) is transparent

function M.backs (ps)
    local ret = {}
    local see = {}
    local function rec (hs)
        for _, h in ipairs(hs) do
            local a = M.aid(h)
            if a then
                if not see[a] then
                    see[a] = true
                    ret[#ret+1] = a
                end
            else
                rec(GIT.parents(h))
            end
        end
    end
    rec(ps)
    table.sort(ret)
    return ret
end

-- mint `T`'s aid: the file waits in the git dir (object db
-- untouched) until `pos` writes it after `apply` accepts

function M.pre (T)
    local tmp = REPO .. "action-tmp.lua"
    local f = io.open(tmp, "w")
    f:write(serial(T))
    f:close()
    return (exec {
        cmd = "git -C " .. REPO .. " hash-object " .. tmp,
    })
end

-- the minted action file enters the object db (repos are bare:
-- no file to place); `GIT.commit` stages it into the new tree

function M.pos (aid)
    exec {
        cmd = "git -C " .. REPO .. " hash-object -w " .. REPO .. "action-tmp.lua",
    }
    os.remove(REPO .. "action-tmp.lua")
end

return M
