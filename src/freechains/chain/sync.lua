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
    -- for the payload pass: my tip before, the remote tip, their
    -- merge-base (nil: the remote brought nothing), the remote's new
    -- commits
    local OLD, NEW, BASE, NEWS
    -- the state at the final HEAD, when the merge left it in memory
    local GNEW
    -- the begs kept by the begs pass (cid -> true)
    local BEGS = {}
    do
        exec {
            cmd = "git -C " .. REPO .. " fetch " .. URL(ARGS.remote, ARGS.alias) ..
                " main refs/begs/*:refs/begs/*",
            err = "chain sync : fetch failed",
        }

        local loc = HEAD
        -- the remote tip: the fetch just wrote it to FETCH_HEAD (the
        -- `main` line; the begs are "not-for-merge"), no rev-parse
        local rem
        do
            local f = io.open(REPO .. "FETCH_HEAD")
            if f then
                rem = f:read("a"):match("(%x+)\t\tbranch 'main' of ")
                f:close()
            end
            rem = rem or exec {
                cmd = "git -C " .. REPO .. " rev-parse FETCH_HEAD"
            }
        end
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

        -- 1. reject unrelated histories (my root IS the genesis)
        do
            local rem_root = exec {
                cmd = "git -C " .. REPO .. " rev-list --max-parents=0 " .. rem
            }
            if rem_root ~= GENESIS then
                ERROR("chain sync : incompatible genesis")
            end
        end

        -- 2. remote has nothing new: the merge-base is the remote tip
        -- (and a base at my tip is a plain fast-forward)
        local base = exec {
            cmd = "git -C " .. REPO .. " merge-base " .. loc .. " " .. rem
        }
        if base == rem then
            goto RECV
        end
        BASE = base

        -- the remote's new commits, oldest last, with their parents:
        -- one call serves the fast-forward test and the payload pass.
        -- A plain fast-forward keeps my order as a prefix of the new
        -- one, UNLESS a sync merge among the new commits put a branch
        -- before my settled posts (tst/hardfork-ff.lua)
        local ff = (base == loc)
        NEWS = {}
        do
            local out = exec {
                cmd = "git -C " .. REPO .. " rev-list --parents " .. base .. ".." .. rem
            }
            for line in out:gmatch("[^\n]+") do
                NEWS[#NEWS+1] = line:match("^(%x+)")
            end
            -- the new commits' objects and snapshot checks, in one
            -- call each: the replay below reads every one of them,
            -- and the floor (my tip) as the first one's parent
            local pre = table.move(NEWS, 1, #NEWS, 1, { loc })
            GIT.cats(pre)
            STATE.has_all(pre)
            for line in out:gmatch("[^\n]+") do
                local cid = line:match("^(%x+)")
                if ff and line:match("^%x+ %x+ %x+") and (not ACTION.is(cid)) then
                    ff = false
                end
            end
        end

        -----------------------------------------------------------------------

        -- 3. need common ancestor

        -- remote validation: the remote tip's own-lineage state
        -- (snapshots every new commit), malformed commits reject the
        -- whole sync
        -- REFS: the new snapshots' refs and the HEAD move, flushed in
        -- one call; earlier when something must read them
        local REFS = {}
        local function flush ()
            STATE.flush(REFS)
        end
        local G_rem
        do
            local ok, ret = pcall(CONSENSUS.state, rem, REFS)
            if not ok then
                ERROR("chain sync : " .. ret)
            end
            G_rem = ret
        end

        -- fst/winner - snd/loser: reps at their merge-base
        local fst, snd = CONSENSUS.winner(loc, rem, base)

        -- winner state:
        --  me: as is
        --  he: the replayed remote
        local G_fst
        if fst == loc then
            G_fst = STATE.read(loc)
        else
            G_fst = G_rem
        end

        -- loser state: replay snd from fst.
        -- The first failure voids the rest: the action is valid in
        -- its own branch, but not in this order
        -- (a fast-forward has no loser side: nothing to replay)
        local merge, err
        if not ff then
            merge, err = CONSENSUS.replay(G_fst, fst, snd, true)
        end
        if err then
            io.stderr:write("ERROR : " .. err .. "\n")
        end

        -- only when the remote wins
        if fst == rem then
            -- a plain fast-forward cannot reorder my order (a prefix of
            -- the new one) nor void a local commit: nothing to check
            if not ff then
                -- check hardfork: my current state vs the new order
                -- (reads the new snapshots: flush them first)
                flush()
                local G_loc = STATE.read(loc)
                if hardfork(G_loc, loc, rem, G_fst) then
                    ERROR("chain sync : hard fork")
                end
            end

            -- list voided local commits
            if (not ff) and (merge ~= loc) then
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
            REFS[#REFS+1] = "update HEAD " .. rem
            HEAD = rem
        end

        -- the state at the final HEAD: the winner's, with the loser
        -- replayed (nothing, when the loser's first action failed)
        GNEW = G_fst

        -- merge the last non-failing loser
        if merge then
            HEAD = GIT.commit(false, nil, {
                parents = { HEAD, merge },
            })
            REFS[#REFS+1] = "update HEAD " .. HEAD
            -- the merge tip is new: snapshot it as any peer derives it
            -- from the DAG (not from this replay's path); that reads
            -- the parents' snapshots: flush them first
            flush()
            GNEW = CONSENSUS.state(HEAD, REFS)
        end
        flush()
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
            else
                BEGS[cid] = true
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

        local G = GNEW or STATE.read(HEAD)

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

        if BASE then
            -- the remote side's commits and their vote targets
            for _, cid in ipairs(NEWS) do
                local t = ACTION.read(false, cid)
                if t then
                    add(cid)
                    add(t.cid)
                end
            end
            -- my side's vote targets, only past a fork (a fast-forward
            -- has no local side)
            if BASE ~= OLD then
                local out = exec {
                    cmd = "git -C " .. REPO .. " rev-list " .. BASE .. ".." .. OLD
                }
                for cid in out:gmatch("%x+") do
                    local t = ACTION.read(false, cid)
                    if t then
                        add(t.cid)
                    end
                end
            end
        end

        for cid in pairs(BEGS) do
            B[cid] = true
            add(cid)
        end

        STATE.fetch(G, table.move(S, 1, n, 1, {}))

        --[[
        -- One `cat-file --batch-check` over many objects or refs.
        -- Inputs:
        --  - objs [table]: array of "<object> <tag>" lines
        -- Outputs:
        --  - [table]: tag -> object sha, for the objects that exist
        -- Errors:
        --  - via exec: "bug found" if cat-file fails
        --]]
        local function check (objs)
            local T = {}
            if #objs == 0 then
                return T
            end
            local path = REPO .. "sync-stdin"
            local f = assert(io.open(path, "w"))
            f:write(table.concat(objs, "\n"), "\n")
            f:close()
            local out = exec { trim=false,
                cmd = "git -C " .. REPO .. " cat-file --batch-check='%(objectname) %(rest)' < " .. path,
            }
            os.remove(path)
            for sha, tag in out:gmatch("(%x+) (%x+)\n") do
                T[tag] = sha
            end
            return T
        end

        -- the anchors I hold among the affected: payload ref -> blob
        -- (never a listing of every payload ref: flat in the chain)
        local function anchors ()
            local refs = {}
            for i = 1, n do
                refs[i] = "refs/payloads/" .. S[i] .. " " .. S[i]
            end
            return check(refs)
        end
        local has = anchors()

        -- the unanchored actions' blobs: here already, or to fetch
        local blobs = {}    -- cid -> blob
        local objs  = {}
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
                    blobs[cid] = t.blob
                    objs[#objs+1] = t.blob .. " " .. cid
                end
            end
        end
        local here = check(objs)

        local want = {}     -- cid -> blob, still to fetch
        local specs = {}
        for cid, blob in pairs(blobs) do
            if here[cid] then
                exec {
                    cmd = "git -C " .. REPO .. " update-ref refs/payloads/" ..
                        cid .. " " .. blob
                }
            else
                want[cid] = blob
                specs[#specs+1] = " 'refs/payloads/" .. cid ..
                    "*:refs/payloads/" .. cid .. "*'"
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
