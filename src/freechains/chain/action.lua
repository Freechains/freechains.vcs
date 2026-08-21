local GIT = require "freechains.chain.git"

-- an ACTION is a commit whose MESSAGE is the action table:
--  - its ID is the commit hash: one cid space for actions,
--    merges, states, payloads, begs
--  - a sync MERGE has an empty message: transparent
--  - the GENESIS is the root (no parents): not an action
--    (its message carries the genesis table)

local M = {}

-- the action table of `aid`: the commit's message body
--  - asr = true  : asserts (my own history, so it is a bug)
--  - asr = false : nil if it does not load (untrusted input)

function M.read (asr, aid)
    local out = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. REPO .. " cat-file commit " .. cid
    }
    local body = out and out:match("\n\n(.*)$")
    if body and #body > 0 then
        -- "t": text only (a binary chunk can crash the VM)
        -- {} : no globals (the message is DATA, not a program)
        local f = load(body, "=action", "t", {})
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
        error("bug found : no action : " .. cid)
    end
    return nil
end

-- `pre` expanded to a full aid: ids are printed abbreviated
-- (`list dag`), so a prefix must resolve, as git does with any
-- object. Unknown or ambiguous prefixes are returned unchanged:
-- the caller fails on the cid it was given

function M.full (pre)
    if (#pre == 40) or (not pre:match("^%x+$")) then
        return pre
    end
    -- ^{commit}: states/payloads are blobs in the same object db
    local out = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " rev-parse --verify --quiet" ..
            " '" .. pre .. "^{commit}'",
    }
    return out or pre
end

-- aid(cid): is `cid` an ACTION? returns the cid itself, or nil:
-- a merge has an empty message, the genesis has no parents

function M.aid (cid)
    local out = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. REPO .. " cat-file commit " .. cid,
    }
    if not out then
        return nil
    end
    if not out:match("\nparent %x+") then
        return nil                          -- genesis
    end
    local body = out:match("\n\n(.*)$")
    if body and #body > 0 then
        return cid
    end
    return nil                              -- sync merge
end

-- the action ancestors (as sorted aids) of the commit about to
-- be created, from its parents `ps` (revs). Structural: an
-- action IS a commit with a message; anything else (genesis,
-- sync merge) is transparent

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

-- mint `T`'s action commit UNREFERENCED (aid == cid needs the
-- parents): `apply` runs on the aid; only acceptance moves HEAD
-- (GIT.tip). A rejected action stays one loose commit, gc-able.
-- t = { act=T, parents={...}, sign=keypath|nil, err=msg|nil }

function M.pre (t)
    local tmp = REPO .. "action-tmp"
    local f = io.open(tmp, "w")
    f:write(serial(t.act))
    f:close()
    local cid = GIT.commit {
        parents = t.parents,
        msg     = tmp,
        ref     = false,
        sign    = t.sign,
        err     = t.err,
    }
    os.remove(tmp)
    return cid
end

return M
