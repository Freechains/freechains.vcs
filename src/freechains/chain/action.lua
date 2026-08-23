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
--  - asr [boolean]: on errors, true asserts, false returns nil
--  - cid [string]: 40-hex commit hash
--  - opt [table?]: ENVELOPE extractions to also fill, each one
--    extra git call:
--      - sign=true:  claimed pubkey from the gpgsig (NOT
--        verified: display only; replay uses SSH.verify)
--      - backs=true: structural back-links from the parents
-- Outputs:
--  - [table?]: { action, time, blob?, n?, cid?|author?, sign?, backs? }
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
function M.read (asr, cid, opt)
    opt = opt or {}
    do
        local out = exec { trim=false, err=false, stderr=false,
            cmd = "git -C " .. REPO .. " cat-file commit " .. cid
        }
        if not out then
            goto ERR
        end

        -- "author - <-> 1780088002 +0000"
        local time = tonumber(out:match("\nauthor [^\n]* (%d+) [%+%-]%d+\n"))
        if not time then
            goto ERR
        end

        local ls = {}
        -- "...committer - <-> 1780088002 +0000\n\nlike 1000\n..."
        for l in (out:match("\n\n(.*)$") or ""):gmatch("[^\n]+") do
            ls[#ls+1] = l
        end
        if not ls[1] then
            goto ERR
        end

        -- post shape: `blob` reaches a shell: a hash, or nothing
        if ls[1] == 'post' then
            if #ls ~= 2 then
                goto ERR
            end
            -- "90c7c77a05dc37cb04ca75b6247a92c0d5451208"
            if not ls[2]:match("^%x+$") then
                goto ERR
            end
            return {
                action = 'post',
                time   = time,
                blob   = ls[2],
                sign   = (opt.sign and SSH.signer(REPO, cid)) or nil,
                backs  = (opt.backs and M.backs(GIT.parents(cid))) or nil,
            }

        -- vote shape
        else
            -- "like 1000" | "revoke -1000"
            local kind, n = ls[1]:match("^(%a+) (%-?%d+)$")
            if not kind then
                goto ERR
            end
            if #ls > 3 then
                goto ERR
            end
            local ty, tgt
            if ls[2] then
                -- "action 4b2080cf..." | "author ssh-ed25519 AAAA..."
                ty, tgt = ls[2]:match("^(%a+) (.+)$")
            end
            if (ty ~= 'action') and (ty ~= 'author') then
                goto ERR
            end
            local why = ls[3]
            -- "9ae2f1b35c88f0a3d7e6d41f2b90c477aa105523"
            if why and (not why:match("^%x+$")) then
                goto ERR
            end
            return {
                action = kind,
                time   = time,
                n      = tonumber(n),
                blob   = why,
                sign   = (opt.sign and SSH.signer(REPO, cid)) or nil,
                backs  = (opt.backs and M.backs(GIT.parents(cid))) or nil,
                [ty == 'action' and 'cid' or 'author'] = tgt,
            }
        end
        ::ERR::
    end

    if asr then
        error("bug found : no action : " .. cid)
    end
    return nil
end

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
    -- ^{commit}: states/payloads are blobs in the same object db
    return exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " rev-parse --verify --quiet" ..
            " '" .. pre .. "^{commit}'",
    }
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
function M.is (cid)
    local out = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. REPO .. " cat-file commit " .. cid,
    }
    if not out then
        return false
    end
    if not out:match("\nparent %x+") then
        return false    -- genesis
    end
    if #out:match("\n\n(.*)$") == 0 then
        return false    -- sync merge
    end
    return true
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
            if M.is(h) then
                if not see[h] then
                    see[h] = true
                    ret[#ret+1] = h
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
-- Commit action `t` with inline message metadata.
-- Inputs:
--  - err [string?]: exec err message on failure (nil: bug found)
--  - t [table]: action, n, cid?|author?, blob?
--    + parents={...}, sign=keypath?
-- Outputs:
--  - [string]: the new action's 40-hex cid
-- Errors:
--  - via exec: `err` or "bug found" on commit-tree failure
-- Callers:
--  - post (post.lua): mint the post
--  - like (like.lua): mint the vote
--]]
function M.commit (err, t)
    local msg
    if t.action == 'post' then
        msg = "post\n" .. t.blob .. "\n"
    else
        msg = t.action .. " " .. t.n .. "\n"
        if t.cid then
            msg = msg .. "action " .. t.cid .. "\n"
        else
            msg = msg .. "author " .. t.author .. "\n"
        end
        if t.blob then
            msg = msg .. t.blob .. "\n"
        end
    end
    return GIT.commit(false, err, {
        parents = t.parents,
        msg     = msg,
        date    = ARGS.now,
        sign    = t.sign,
    })
end

-- `merge` is deliberately absent as a kind: a sync merge carries no
-- action message and is pure topology (empty message)
local KINDS = { post=true, like=true, revoke=true }

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
function M.apply (G, cid, beg)
    local ps = GIT.parents(cid)
    local isa = M.is(cid)   -- false: sync merge
    -- a merge adds no time: dates are neutral, the action message
    -- is the one source of truth

    -- EVERY commit carries the empty tree: content in a tree would
    -- be smuggled bytes, relayed forever and un-revocable
    do
        local t = exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " rev-parse " .. cid .. "^{tree}",
        }
        if t ~= GIT.tree() then
            error("malformed commit : unexpected tree", 0)
        end
    end

    -- empty message: must be a 2-parent sync merge (the genesis,
    -- the only root, is below every replay and never gets here)
    if not isa then
        if #ps ~= 2 then
            error("malformed commit : expected 2-parent merge", 0)
        end

    -- action message: check commit
    else
        local act = M.read(false, cid)
        if not act then
            error("malformed commit : invalid action", 0)
        end
        local kind = act.action
        if not KINDS[kind] then
            error("malformed commit : invalid action kind", 0)
        end
        if #ps > 2 then
            error("malformed commit : too many parents", 0)
        end

        if math.type(act.time) ~= 'integer' then
            error("malformed commit : invalid time", 0)
        end

        if G.actions[cid] then
            -- the same action arrived in an earlier commit: already
            -- in G; only the snapshot below matters
            goto SNAP
        end

        local key, err = SSH.verify(REPO, cid)
        if (not key) and err=='forged' then
            error("malformed commit : invalid signature", 0)
        end

        -- backs are STRUCTURAL: derived here from the parents,
        -- never claimed (the cid IS the commit: git's Merkle binds ancestry)
        local backs = M.backs(ps)

        -- beg admission: a post begs when forced by the caller
        -- (writer --beg, beg sync) or unsigned; only a positive
        -- `like` promotes a parked beg target
        local to_beg
        if kind == 'post' then
            to_beg = beg or (key == nil)
        else
            if not key then
                error("malformed commit : expected signature", 0)
            end
            to_beg = (
                kind == 'like'
                and (math.type(act.n)=='integer' and act.n>0)
                and (act.cid and G.actions[act.cid])
                and (G.actions[act.cid].maturity == "beg")
            ) or false
        end

        local ok, err = RULES.apply(G, act, {
            cid   = cid,
            sign  = key,
            beg   = to_beg,
            backs = backs,
        })
        if not ok then
            error("invalid " .. kind .. " : " .. err, 0)
        end
        G.order[#G.order+1] = cid
    end

    ::SNAP::

    -- snapshot: `now` is ancestry-accurate (the replay's G.now may
    -- already include sibling branches applied earlier in consensus
    -- order): an action's own `now` was folded at apply; a merge
    -- adds nothing, so fold its parents' nearest actions.
    -- NEVER overwrite: the first write is the commit's own-lineage
    -- state, and a refused sync must not corrupt local snapshots
    if not STATE.has(cid) then
        local sav = G.now
        if isa then
            G.now = G.actions[cid].now
        else
            G.now = RULES.now(G, M.backs(ps))
        end
        STATE.write(G, cid)
        G.now = sav
    end
end

return M
