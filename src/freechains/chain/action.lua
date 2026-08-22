local GIT = require "freechains.chain.git"

-- an ACTION is a commit whose MESSAGE is the action table:
--  - its ID is the commit hash: one cid space for actions,
--    merges, states, payloads, begs
--  - a sync MERGE has an empty message: transparent
--  - the GENESIS is the root (no parents): not an action
--    (its message carries the genesis table)

local M = {}

--[[
-- Parse `cid` action from commit:
--  time:  commit DATE
--  backs: commit parents
--  sign:  gpgsig
--  Commit message shape:
--     post ; <payload-blob>
--     like|revoke <n> ; action <cid>|author <pub> [; <why-blob>]
-- Inputs:
--  - asr  [boolean]: on errors, true asserts, false returns nil
--  - cid  [string]: 40-hex commit hash
--  - sign [boolean?]: should fill `t.sign` from the gpgsig (not verified)
-- Outputs:
--  - [table?]: { action, time, blob?, n?, cid?|author?, sign? }
--  - nil, error: parse error (asr=false)
-- Errors:
--  - "bug found : no action : <cid>" : parse error (asr=true)
-- Callers:
--  - apply (action.lua): the accept pipeline
--  - climb (consensus.lua): beg-merge detection
--  - get (get.lua): payload blob and metadata
--  - like (like.lua): payload restore on unrevoke crossing
--  - hardfork/recv (sync.lua): window times, payload re-anchors
--]]
function M.read (asr, cid, sign)
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

--[[
-- Resolve `pre` to full commit cid.
-- Anything git resolves (hex prefix, full hash, HEAD, ...).
-- Inputs:
--  - pre [string]: a rev
-- Outputs:
--  - [string|false]: the full cid; false if it does not resolve
-- Errors:
--  - none
-- Callers:
--  - like (like.lua): action target argument
--  - get (get.lua): id argument
--  - abandon (abandon.lua): id argument
--]]
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

--[[
-- Is `cid` an ACTION?
-- Inputs:
--  - cid [string]: 40-hex commit hash (or any rev)
-- Outputs:
--  - [boolean]: result
-- Errors:
--  - none
-- Callers:
--  - backs/apply (action.lua): stop condition, merge branch
--  - climb (consensus.lua): beg-merge detection
--  - abandon (abandon.lua): range must be all actions
--  - recv (sync.lua): voided-commit listing
--]]
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

--[[
-- The nearest action ancestors reachable from parents `ps`.
-- Skips transparent commits: genesis, sync merges.
-- Structural: derived from the DAG, never claimed.
-- Inputs:
--  - ps [table]: array of parent cids (revs)
-- Outputs:
--  - [table]: sorted array of action cids (the backs)
-- Errors:
--  - none
-- Callers:
--  - apply (action.lua): env.backs and the merge snapshot fold
--  - recv (sync.lua): the loser sync-merge snapshot fold
--  - list dag (list.lua): structural ups of each node
--]]
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

--[[
-- Commit action `t`.
-- Inputs:
--  - t [table]: the action fields
-- Outputs:
--  - [string]: the new action's 40-hex cid
-- Errors:
--  - via exec: t.err or "bug found" on commit-tree failure
-- Callers:
--  - post (post.lua): mint the post
--  - like (like.lua): mint the vote
--]]
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

--[[
-- Accept `cid` into `G`.
-- Single pipeline for write and replay.
-- Everything is read from the commit itself (message, DATE, gpgsig, parents).
-- Checks structure checks, signature, rules `apply`, order, snapshot.
-- Inputs:
--  - G   [table]: chain state (authors/actions/order/now); MUTATED
--  - cid [string]: 40-hex commit hash, already in the object db
--  - beg [boolean?]: force beg admission (post writers, beg sync)
-- Outputs:
--  - none: G holds the action and refs/states/<cid> holds its snapshot
-- Errors:
--  - "malformed commit : ..." : structure (tree/parents/signature)
--  - "invalid <kind> : ..."   : refused by the reputation rules
-- Callers:
--  - post (post.lua): writer accepts its own mint
--  - like (like.lua): writer accepts its own mint
--  - climb (consensus.lua): replay, once per commit
--  - recv (sync.lua): validate an incoming beg head
--]]
return M
