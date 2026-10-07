--[[
-- `chain <alias> sync send|recv <remote>`
-- Push my chain, or fetch remote, validate/replay it, and reconcile refs.
-- Inputs:
--  - ARGS.send|ARGS.recv [boolean]: direction
--  - ARGS.remote [string]: path, host[:port], or URL
--  - ARGS.alias  [string]: the chain (appended to bare hosts)
--  - REPO [string]: the chain's bare repo dir (recv reads its
--    states; G is never preloaded here)
-- Outputs:
--  - send: my main + refs/begs/* pushed (receiver's hook recvs)
--  - recv: stdout "voided : <cid>" per losing action; HEAD
--    moved/merged; states snapshotted; begs validated or
--    dropped; payload anchors follow the final revoke sums
-- Errors:
--  - "chain sync : freechains.url not set" (send)
--  - "chain sync : fetch failed"
--  - "chain sync : incompatible genesis"
--  - "chain sync : hard fork"
--  - "chain sync : <replay>" : malformed/invalid remote commit
-- Callers:
--  - dispatch (chain/init.lua): ARGS.sync
--  - chains add clone (chains.lua): re-execs `sync recv`
--  - pre-receive hook: runs recv on the receiver
--]]

local CONSENSUS = require "freechains.chain.consensus"

--[[
-- The order chunks of the snapshot at `cid`, by blob id.
-- Inputs:
--  - cid [string]: 40-hex commit hash, snapshotted
-- Outputs:
--  - [table]: { [k] = blob sha } for `order/<k>.txt` (k from 0)
-- Errors:
--  - via exec: "bug found" if ls-tree fails
-- Callers:
--  - hardfork (sync.lua): find where two orders split
--]]
local function chunks (cid)
    local out = exec {
        cmd = "git -C " .. REPO .. " ls-tree " .. STATE.ref(cid) .. " order/",
    }
    local T = {}
    for sha, k in out:gmatch("blob (%x+)\torder/(%d+)%.txt") do
        T[tonumber(k)] = sha
    end
    return T
end

--[[
-- The cids of one order chunk.
-- Inputs:
--  - sha [string]: the chunk's blob id
-- Outputs:
--  - [table]: array of cids
-- Errors:
--  - via exec: "bug found" if cat-file fails
-- Callers:
--  - hardfork (sync.lua): the first differing chunk
--]]
local function cids (sha)
    local T = {}
    local out = exec { trim=false,
        cmd = "git -C " .. REPO .. " cat-file blob " .. sha,
    }
    for cid in out:gmatch("%x+") do
        T[#T+1] = cid
    end
    return T
end

--[[
-- Hard fork protects my current order: the new order must keep my
-- SETTLED entries, those whose order time (`time.apply`) is
-- `time.fork` behind the chain time (`G.now`).
-- Consensus time is set at replay, so a loser merged today is
-- loose for `time.fork` whatever its declared dates.
-- Inputs:
--  - G   [table]: current state (order, actions[*].time.apply, now)
--  - loc [string]: my tip, snapshotted (G's commit)
--  - rem [string]: the winning remote tip, snapshotted
--  - G2  [table]: the new state (order), after replay
-- Outputs:
--  - [boolean]: true = settled prefix reordered (hard fork)
-- Errors:
--  - assert: order entry without a state or `time.apply` (bug)
-- Callers:
--  - recv (sync.lua): only when the remote wins
--]]
-- The new order starts with rem's order, the loser replay only
-- appends: so the split point is the first index where the orders
-- of the two SNAPSHOTS differ. Chunks are append-only and shared by
-- blob id, so equal ids = equal prefixes: only the first differing
-- chunk is read. `time.apply` grows along the order, so settled
-- entries form a prefix: one read at the split decides.
local function hardfork (G, loc, rem, G2)
    local K = STATE.ORDER_K
    local A, B = chunks(loc), chunks(rem)
    local k = 0
    while A[k] and (A[k] == B[k]) do
        k = k + 1
    end

    local s
    if not A[k] then
        return false        -- my order is a prefix of the new one
    elseif B[k] then
        local a, b = cids(A[k]), cids(B[k])
        for j = 1, #a do
            if b[j] == nil then
                break       -- rem's order ends inside my chunk
            elseif a[j] ~= b[j] then
                s = k*K + j
                break
            end
        end
        if (not s) and (#a <= #b) then
            return false    -- my order is a prefix of the new one
        end
    end

    if s then
        local e = assert(G.actions[G.order[s]])
        return G.now-assert(e.time.apply) >= C.time.fork
    end

    -- rem's order is a strict prefix of mine (rare: its new commits
    -- add no order entry): the split is inside the loser replay,
    -- compare against the new order itself
    STATE.order(G)
    STATE.order(G2)
    local our, their = G.order, G2.order
    for i = 1, #our do
        if their[i] ~= our[i] then
            local e = assert(G.actions[our[i]])
            return G.now-assert(e.time.apply) >= C.time.fork
        end
    end
    return false
end

if ARGS.send then
    local url = exec {
        cmd = "git -C " .. REPO .. " config freechains.url",
        err = "chain sync : freechains.url not set",
    }
    local _, Q, err = exec { err=false,
        cmd = "git -C " .. REPO ..  " push -o freechains=true"
            .. " -o 'url=" .. url .. "'"
            .. " " .. URL(ARGS.remote, ARGS.alias)
            .. " +main +refs/begs/*:refs/begs/*"
    }
    if err and err:find("Freechains: OK") then
        -- success: receiver's hook ran recv and rejected the push
    elseif Q ~= 0 then
        io.stderr:write(err)
        os.exit(1)
    end

elseif ARGS.recv then
    -- for the payload pass: my tip before, the remote tip, and
    -- whether the remote brought anything
    local OLD, NEW, FRESH
    do
        exec {
            cmd = "git -C " .. REPO .. " fetch " .. URL(ARGS.remote, ARGS.alias) ..
                " main refs/begs/*:refs/begs/*",
            err = "chain sync : fetch failed",
        }

        local loc = exec {
            cmd = "git -C " .. REPO .. " rev-parse HEAD"
        }
        local rem = exec {
            cmd = "git -C " .. REPO .. " rev-parse FETCH_HEAD"
        }
        OLD, NEW = loc, rem

        --[[
        -- Three cases:
        --  1. unrelated histories (different genesis)
        --      - ERROR
        --  2. local contains remote (remote is ancestor of local)
        --      - DONE
        --  3. remote has new commits (FF or diverge)
        --      - common ancestor, remote validation/replay: climb / meet
        --      - FF degenerates: ancestor rule in `consensus` picks
        --        remote, loser set filters to empty, reset == FF merge
        ]]

        -----------------------------------------------------------------------

        -- 1. reject unrelated histories
        do
            local loc_root = exec {
                cmd = "git -C " .. REPO .. " rev-list --max-parents=0 " .. loc
            }
            local rem_root = exec {
                cmd = "git -C " .. REPO .. " rev-list --max-parents=0 " .. rem
            }
            if loc_root ~= rem_root then
                ERROR("chain sync : incompatible genesis")
            end
        end

        -- 2. remote has nothing new
        do
            local ok = exec { stderr=false, err=false,
                cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. rem .. " " .. loc
            }
            if ok then
                goto RECV
            end
        end
        FRESH = true

        -----------------------------------------------------------------------

        -- 3. need common ancestor

        -- remote validation: the remote tip's own-lineage state
        -- (snapshots every new commit), malformed commits reject the
        -- whole sync
        local G_rem
        do
            local ok, ret = pcall(CONSENSUS.state, rem)
            if not ok then
                ERROR("chain sync : " .. ret)
            end
            G_rem = ret
        end

        -- fst/winner - snd/loser: reps at their merge-base
        local fst, snd = CONSENSUS.winner(loc, rem)

        -- winner state:
        --  me: as is
        --  he: the replayed remote
        local G_fst
        if fst == loc then
            G_fst = STATE.read(GIT.deref("HEAD"))
        else
            G_fst = G_rem
        end

        -- loser state: replay snd from fst.
        -- The first failure voids the rest: the action is valid in
        -- its own branch, but not in this order
        local merge, err = CONSENSUS.replay(G_fst, fst, snd, true)
        if err then
            io.stderr:write("ERROR : " .. err .. "\n")
        end

        -- only when the remote wins
        if fst == rem then
            -- check hardfork: my current state vs the new order
            local G_loc = STATE.read(GIT.deref("HEAD"))
            if hardfork(G_loc, loc, rem, G_fst) then
                ERROR("chain sync : hard fork")
            end

            -- list voided local commits
            if merge ~= loc then
                local from = merge or fst
                local out = exec {
                    cmd = "git -C " .. REPO .. " " ..
                        "log --reverse --no-merges --format='%H' " ..
                        (from .. ".." .. loc)
                }
                for cid in out:gmatch("%x+") do
                    if ACTION.is(cid) then
                        print("voided : " .. cid)
                    end
                end
            end

            -- move HEAD to remote tip
            exec {
                cmd = "git -C " .. REPO .. " update-ref HEAD " .. rem
            }
        end

        -- merge the last non-failing loser
        if merge then
            GIT.commit(true, nil, {
                parents = { GIT.deref("HEAD"), merge },
            })
            -- the merge tip is new: snapshot it as any peer derives it
            -- from the DAG (not from this replay's path)
            CONSENSUS.state(GIT.deref("HEAD"))
        end
    end

    ::RECV::

    -- begs, one pass over refs/begs/*:
    --  - already merged into main (someone liked it): drop it
    --  - fetched, so unsnapshotted: a beg's state = its parent's
    --    snapshot + the beg post itself (what the writer saved)
    -- An invalid beg cannot be liked: its ref drops
    do
        local out = exec {
            cmd = "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(refname) %(objectname)'"
        }
        for refname, cid in out:gmatch("(%S+)%s+(%S+)") do
            local merged = exec { stderr=false, err=false,
                cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. cid .. " main"
            }
            local keep = true
            if merged then
                keep = false
            elseif not STATE.has(cid) then
                local ps = GIT.parents(cid)
                keep = (#ps == 1) and STATE.has(ps[1])
                if keep then
                    keep = pcall(ACTION.apply, STATE.read(ps[1]), cid, true, true)
                end
            end
            if not keep then
                exec {
                    cmd = "git -C " .. REPO .. " update-ref -d " .. refname
                }
            end
        end
    end

    -- Payload anchors follow the final sums, for the AFFECTED cids
    -- only (a pull pays for what it brings, not for the chain):
    --  - the remote side's actions, and the targets of its votes
    --  - the targets of my side's votes (a voided vote moves them)
    --  - the cids still missing their bytes (heal from any peer)
    --  - the begs (their bytes ride the same anchors)
    -- A REVOKED action loses its anchor; the others re-anchor from
    -- bytes already here, else fetch their own ref (never `*`, so
    -- removed bytes never return)
    -- No missing-bytes file yet (older repo): one full pass builds it
    do
        local MISS = REPO .. "payloads-missing"
        local S, n, B = {}, 0, {}
        local function add (cid)
            if cid and (not S[cid]) then
                S[cid] = true
                n = n + 1
                S[n] = cid
            end
        end

        local G = STATE.read(GIT.deref("HEAD"))

        local f = io.open(MISS)
        if f then
            for l in f:lines() do
                add(l:match("%x+"))
            end
            f:close()
        else
            STATE.all(G)
            for cid in pairs(G.actions) do
                add(cid)
            end
        end

        if FRESH then
            local base = exec {
                cmd = "git -C " .. REPO .. " merge-base " .. OLD .. " " .. NEW
            }
            for _, side in ipairs { {NEW,true}, {OLD,false} } do
                local out = exec {
                    cmd = "git -C " .. REPO .. " rev-list " .. base .. ".." .. side[1]
                }
                for cid in out:gmatch("%x+") do
                    local t = ACTION.read(false, cid)
                    if t then
                        if side[2] then
                            add(cid)
                        end
                        add(t.cid)
                    end
                end
            end
        end

        do
            local out = exec {
                cmd = "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(objectname)'"
            }
            for cid in out:gmatch("%x+") do
                B[cid] = true
                add(cid)
            end
        end

        STATE.fetch(G, table.move(S, 1, n, 1, {}))

        -- the anchors I hold: payload ref -> blob
        local function anchors ()
            local T = {}
            local out = exec {
                cmd = "git -C " .. REPO ..
                    " for-each-ref refs/payloads/ --format='%(refname) %(objectname)'"
            }
            for a, sha in out:gmatch("refs/payloads/(%x+) (%x+)") do
                T[a] = sha
            end
            return T
        end
        local has = anchors()

        local want = {}     -- cid -> blob, still to fetch
        local specs = {}
        for i = 1, n do
            local cid = S[i]
            local e = G.actions[cid]
            if e and RULES.is_revoked(e) then
                if has[cid] then
                    exec {
                        cmd = "git -C " .. REPO ..
                            " update-ref -d refs/payloads/" .. cid
                    }
                end
            elseif (e or B[cid]) and (not has[cid]) then
                local t = ACTION.read(false, cid)
                if t and t.blob then
                    local here = exec { err=false, stderr=false,
                        cmd = "git -C " .. REPO .. " cat-file -e " .. t.blob
                    }
                    if here then
                        exec {
                            cmd = "git -C " .. REPO .. " update-ref refs/payloads/" ..
                                cid .. " " .. t.blob
                        }
                    else
                        want[cid] = t.blob
                        specs[#specs+1] = " 'refs/payloads/" .. cid ..
                            "*:refs/payloads/" .. cid .. "*'"
                    end
                end
            end
        end

        -- one fetch; a glob per cid: a ref the remote lacks is no error
        local miss = {}
        if #specs > 0 then
            exec { err=false, stderr=false,
                cmd = "git -C " .. REPO .. " fetch " .. URL(ARGS.remote, ARGS.alias) ..
                    table.concat(specs)
            }
            has = anchors()
            for cid, blob in pairs(want) do
                if has[cid] ~= blob then
                    -- absent, or not the bytes the action names
                    if has[cid] then
                        exec {
                            cmd = "git -C " .. REPO ..
                                " update-ref -d refs/payloads/" .. cid
                        }
                    end
                    miss[#miss+1] = cid
                end
            end
        end

        table.sort(miss)
        local f = assert(io.open(MISS, "w"))
        f:write(table.concat(miss, "\n"), (#miss > 0) and "\n" or "")
        f:close()
    end
end
