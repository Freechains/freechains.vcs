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

require "freechains.chain.consensus"

--[[
-- Hard fork protects my current order.
-- Find `set` as highest SETTLED index (crossing fork.time or fork.actions).
-- The new order must reproduce that prefix verbatim.
-- Inputs:
--  - our   [table]: current order (cids), before replay
--  - their [table]: new order (cids), after replay
-- Outputs:
--  - [boolean]: true = settled prefix reordered (hard fork)
-- Errors:
--  - assert: window entry without a time (bug)
-- Callers:
--  - recv (sync.lua): only when the remote wins
--]]
local function hardfork (our, their)
    if #our == 0 then
        return false
    end

    -- window [low, #our] with at most 100 actions
    local low = math.max(1, #our-C.fork.actions+1)

    -- times from the action files, and the newest among them
    local ts  = {}
    local max = 0
    for i=low, #our do
        ts[our[i]] = ACTION.read(true, our[i]).time
        max = math.max(max, ts[our[i]])
    end

    -- determine highest settled `set` index, if any
    local set
    do
        -- index of the last entry that is already settled
        if #our >= C.fork.actions then
            set = low   -- at least action count, but time may trigger before
        end

        -- walk from the tip until first entry older than `fork.time`
        for i=#our, low, -1 do
            if (max-assert(ts[our[i]])) >= C.fork.time then
                set = i
                break
            end
        end
    end

    if set then
        -- backwards: reorder near boundary far more often
        for i=set, 1, -1 do
            if their[i] ~= our[i] then
                return true
            end
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

        -----------------------------------------------------------------------

        -- 3. need common ancestor

        local oct = octopus(loc, rem)
        local G_oct = STATE.read(oct)

        -- needs fst/winner - snd/loser (do now b/c replay mutates G_oct)
        local fst, snd = consensus(G_oct, loc, rem)

        -- remote validation: always replay oct -> rem
        -- malformed commits reject the whole sync
        local G_rem = G_oct -- (G_oct no longer required)
        do
            local ok, err = pcall(replay, G_rem, oct, rem, false)
            if not ok then
                ERROR("chain sync : " .. err)
            end
        end

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
        local merge, err = replay(G_fst, fst, snd, true)
        if err then
            io.stderr:write("ERROR : " .. err .. "\n")
        end

        -- only when the remote wins
        if fst == rem then
            -- check hardfork
            local ord = STATE.read(GIT.deref("HEAD")).order
            if hardfork(ord, G_fst.order) then
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
            GIT.commit {
                parents = { GIT.deref("HEAD"), merge },
            }
            -- the merge tip is new: snapshot the final state there
            -- (a merge adds no time: fold its parents' actions)
            G_fst.now = NOW(G_fst, ACTION.backs {
                GIT.deref("HEAD^1"),
                GIT.deref("HEAD^2"),
            })
            STATE.write(G_fst, GIT.deref("HEAD"))
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
                    keep = pcall(ACTION.apply, STATE.read(ps[1]), cid, true)
                end
            end
            if not keep then
                exec {
                    cmd = "git -C " .. REPO .. " update-ref -d " .. refname
                }
            end
        end
    end

    -- Payload anchors follow the final sums (fetch + reconcile):
    -- removed bytes must not return (negative refspecs), lingering
    -- bytes re-anchor (restore), and a REVOKED action loses its
    -- anchor. The final sums decide ONCE, here
    do
        local G = STATE.read(GIT.deref("HEAD"))

        local exc = {}
        for cid, e in pairs(G.actions) do
            if is_revoked(e) then
                exc[#exc+1] = " '^refs/payloads/" .. cid .. "'"
            end
        end
        exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " fetch " .. URL(ARGS.remote, ARGS.alias) ..
                " 'refs/payloads/*:refs/payloads/*'" .. table.concat(exc)
        }

        local has = {}
        do
            local out = exec {
                cmd = "git -C " .. REPO ..
                    " for-each-ref refs/payloads/ --format='%(refname)'"
            }
            for a in out:gmatch("refs/payloads/(%x+)") do
                has[a] = true
            end
        end

        for cid, e in pairs(G.actions) do
            if is_revoked(e) then
                if has[cid] then
                    exec {
                        cmd = "git -C " .. REPO ..
                            " update-ref -d refs/payloads/" .. cid
                    }
                end
            elseif not has[cid] then
                local t = ACTION.read(false, cid)
                if t and t.blob then
                    local have = exec { err=false, stderr=false,
                        cmd = "git -C " .. REPO .. " cat-file -e " .. t.blob
                    }
                    if have then
                        exec {
                            cmd = "git -C " .. REPO .. " update-ref refs/payloads/" ..
                                cid .. " " .. t.blob
                        }
                    end
                end
            end
        end
    end
end
