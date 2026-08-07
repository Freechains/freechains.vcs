require "freechains.chain.common"
local ssh    = require "freechains.chain.ssh"
local replay = require "freechains.chain.replay"

if ARGS.send then
    local url = exec {
        cmd = "git -C " .. REPO .. " config freechains.url",
        err = "chain sync : freechains.url not set",
    }
    -- forward --now as push option so receiver hook pin commit dates
    local now = (ARGS.now and (" -o now=" .. CMD.now) or "")
    local _, Q, err = exec { err=false,
        cmd = "git -C " .. REPO ..  " push -o freechains=true"
            .. " -o 'url=" .. url .. "'" .. now
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
        exec { stderr=false,
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
        -- Four cases:
        --  1. unrelated histories (different genesis)
        --      - ERROR
        --  2. local contains remote (remote is ancestor of local)
        --      - DONE
        --  3,4: need common ancestor, remote validation/replay
        --      - replay_remote: climb / meet
        --  3. remote contains local (local is ancestor of remote)
        --      - merge with fast-forward
        --  4. local and remote diverge
        ]]

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

        ---------------------------------------------------------------------------
        ---------------------------------------------------------------------------

        -- Hard fork protects my ORDER.
        -- Walking my order back from the tip, everything older than fork.time
        -- (or fork.posts entries back) is SETTLED.
        -- `their`: the expected order this sync would leave behind
        -- must reproduce that prefix verbatim, or it is a hard fork.
        local function hardfork (their)
            -- S15.0: healed view, not the worktree file
            local our = replay.state().order
            if #our == 0 then
                return false
            end

            local low = math.max(1, #our-C.fork.posts+1)
            -- TODO : remove : S8.4 : db[aid].time, no commits, no git
            -- order holds action IDs; timestamps live in commits
            local cs = {}
            for i=low, #our do
                cs[i] = assert(DB.cid(our[i]), "bug found")
            end
            local hs = table.concat(cs, " ", low, #our)

            -- ask git for exactly `fork.posts` entries with `--no-walk`
            local ts = {}
            local out = exec {
                cmd = "git -C "..REPO.." log --no-walk --format='%H %at' "..hs
            }
            for h, t in out:gmatch("(%x+)%s+(%d+)") do
                ts[h] = tonumber(t)
            end

            -- index of the last entry that is already settled
            local set
            if #our >= C.fork.posts then
                set = low   -- at least post count, but time may trigger before
            end

            -- walk from the tip until first entry older than `fork.time`
            local new = assert(ts[cs[#our]])
            for i=#our, low, -1 do
                if (new-assert(ts[cs[i]])) >= C.fork.time then
                    set = i
                    break
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

        -- TODO : DONE : S11b : one-pass commit<->ID index over the
        -- fetched range subsumes ORD + AID + CID (DB.cid below)

        ---------------------------------------------------------------------------
        ---------------------------------------------------------------------------

        -- TODO : redesign : review
        -- index the fetched delta before replay (S11c): every
        -- DB.aid/DB.cid below resolves in memory (loc side comes from
        -- the persisted index)
        DB.walk(rem .. " --not " .. loc)

        -- TODO : DONE : S15.2 : no transmitted order to fail
        -- fast on -- the ff hardfork check moves after replay
        local ff = exec { stderr=false, err=false,
            cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. loc .. " " .. rem
        }

        -- 3,4: need common ancestor

        local oct, G_oct
        do
            oct = replay.octopus(loc, rem)
            -- S15.2: own derivation only -- snapshot, or healed
            -- by recursive replay (same path bootstraps clones)
            G_oct = replay.state_at(oct)
        end

        -- 4: needs fst/winner - snd/loser (do now b/c 3 mutates G_oct)
        local fst, snd = replay.consensus(G_oct, loc, rem)

        -- 3,4: need remote validation: replay remote branch from G_oct
        local G_rem = G_oct -- (G_oct no longer required)
        do
            local ok, err = pcall(replay.region, G_rem, oct, rem)
            if not ok then
                ERROR("chain sync : " .. err)
            end
        end

        -- 3. local has nothing new
        if ff then
            -- TODO : DONE : S15.2 : nothing transmitted, nothing
            -- to compare -- G_rem IS the state, snapped by the
            -- replay; hardfork checked here, post-replay
            if hardfork(G_rem.order) then
                ERROR("chain sync : hard fork")
            end
            exec {
                cmd = "git -C " .. REPO .. " merge --ff-only " .. rem
            }
            goto RECV
        end

        --  4. local and remote diverge

        -- final state: consensus + replay loser
        local G_fst, merge
        do
            local O_snd = {}
            do
                local ids
                if fst == loc then
                    G_fst = replay.state()
                    ids = G_rem.order
                else
                    G_fst = G_rem
                    ids = replay.state().order
                end
                -- order holds IDs; the loser replay walks COMMITS
                for _, i in ipairs(ids) do
                    O_snd[#O_snd+1] = assert(DB.cid(i), "bug found")
                end
            end
            O_snd[#O_snd+1] = snd

            -- filter O_snd: keep only commits unreachable from fst
            do
                local keep = {}
                local out = exec {
                    cmd = "git -C " .. REPO .. " rev-list " .. fst .. ".." .. snd
                }
                for h in out:gmatch("%x+") do
                    keep[h] = true
                end
                local filtered = {}
                for _, h in ipairs(O_snd) do
                    if keep[h] then
                        -- consume: a joined action tip appears both as
                        -- its order entry and as `snd` -- merge it once
                        keep[h] = nil   -- TODO : redesign : review
                        filtered[#filtered+1] = h
                    end
                end
                O_snd = filtered
            end

            exec { stderr=false,
                cmd = "git -C " .. REPO .. " checkout --detach " .. fst
            }

            local ok  = true
            local err = nil

            for _, cid in ipairs(O_snd) do
                -- merge action commits; a merge tip re-derives itself
                if DB.aid(cid) then
                    ok = exec { stderr=false, err=false,
                        cmd = "git -C " .. REPO .. " merge --no-commit " .. cid
                    }
                    if not ok then
                        exec { stderr=false, err=false,
                            cmd = "git -C " .. REPO .. " merge --abort"
                        }
                        err = "content conflict"
                        goto DONE
                    end
                    exec { stderr=false,
                        cmd = "git -C " .. REPO .. " commit -m 'x'"
                    }
                end

                ok, err = pcall(replay.commit, G_fst, cid, nil)
                if not ok then
                    goto DONE
                end

                merge = cid
            end

            ::DONE::

            exec { stderr=false,
                cmd = "git -C " .. REPO .. " checkout main"
            }
            if not ok then
                io.stderr:write("ERROR : " .. err .. "\n")
            end
        end

        if hardfork(G_fst.order) then
            ERROR("chain sync : hard fork")
        end

        -- list voided local commits (only when remote wins)
        if fst==rem and merge~=loc then
            local from = merge or fst
            local out = exec {
                cmd = "git -C " .. REPO .. " " ..
                    "log --reverse --no-merges --format='%H' " ..
                    (from .. ".." .. loc)
            }
            -- --no-merges: every remaining commit is an action
            for cid in out:gmatch("%x+") do
                print("voided : " .. assert(DB.aid(cid)))
            end
        end

        -- reset HEAD to winner tip, merge last non-conflicting loser + state
        do
            if fst ~= loc then
                exec {
                    cmd = "git -C " .. REPO .. " reset --hard " .. fst
                }
            end

            if merge then
                -- TODO : DONE : S15.2 : pure topology commit --
                -- no state written, no PEAKS `now` inflation
                exec { stderr=false,
                    cmd = "git -C " .. REPO .. " merge --no-commit " .. merge
                }
                exec {
                    cmd = CMD.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
                    .. " --no-edit"
                }
                -- S15.1b: the final merge is pure by
                -- construction (everything applied = ancestors)
                DB.snap("HEAD", G_fst)
            end
        end
    end

    ::RECV::

    -- stale-beg cleanup: drop refs/begs/* whose post is already in main
    do
        local out = exec {
            cmd = "git -C " .. REPO .. " for-each-ref refs/begs/ --format='%(refname) %(objectname)'"
        }
        for refname, post in out:gmatch("(%S+)%s+(%S+)") do
            local ok = exec { stderr=false, err=false,
                cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. post .. " main"
            }
            if ok then
                exec {
                    cmd = "git -C " .. REPO .. " update-ref -d " .. refname
                }
            end
        end
    end

    -- TODO : redesign : review
    -- the index now covers everything up to the settled HEAD
    DB.tip()
end
