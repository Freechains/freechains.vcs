require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

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

        -- Boundary octopus:
        -- The common ancestor of every point where the region between `a` and
        -- `b` attaches to shared history.
        -- Sits BELOW every fork inside that region, so a replay starting here
        -- re-derives all of it, including merges nested deeper than the outer
        -- one.
        -- With a single fork it degenerates to the pairwise merge-base.
        local function octopus (a, b)
            local out = exec {
                cmd = "git -C " .. REPO .. " rev-list --boundary " .. a .. "..." .. b
            }
            local boundary = {}
            for line in out:gmatch("[^\n]+") do
                local h = line:match("^%-(%x+)")
                if h then
                    boundary[#boundary+1] = h
                end
            end
            return exec {
                cmd = "git -C " .. REPO .. " merge-base --octopus " .. table.concat(boundary, " ")
            }
        end

        -- Consensus: prefix reps from G decide winner
        --  - traverse com..tip, collect signed keys
        --  - sum G.authors[key].reps for each side
        --  - higher sum wins, cid tiebreaker (smaller wins)
        --
        -- Two ancestors, two different questions:
        --   oct:  how much history must I RE-DERIVE
        --         deep: below every fork in the region
        --   base: what did each side CONTRIBUTE
        --         shallow: disjoint, no shared commits
        --
        -- `com` is the pairwise merge-base, computed HERE so no caller can
        -- pass the octopus `oct` instead: from a deeper point the two
        -- ranges overlap, and since reps are summed over the SET of
        -- authors, a commit both sides already hold hands its author's
        -- full reps to whichever side lacked them -- letting undisputed
        -- history decide a disputed merge.
        local function consensus (G, a, b)
            local com = (exec {
                cmd = "git -C " .. REPO .. " merge-base " .. a .. " " .. b
            }):match("%x+")
            local function collect_keys (tip)
                --[[
                    com..tip = commits reachable from tip but not from com:
                                everything tip added since com
                      com
                      /  \
                    c1    d1    com..a = {c1, c2}    <- what A contributed
                     |     |    com..b = {d1, d2}    <- what B contributed
                    c2    d2
                    (a)   (b)
                ]]
                local keys = {}
                local out = exec {
                    cmd = "git -C " .. REPO .. " log --reverse --format=%H " .. com .. ".." .. tip
                }
                for cid in out:gmatch("%x+") do
                    local key = ssh.pub.commit(REPO, cid)
                    if key then
                        keys[key] = true
                    end
                end
                return keys
            end
            local function reps (keys)
                local n = 0
                for key in pairs(keys) do
                    local T = G.authors[key]
                    if T then
                        n = n + T.reps
                    end
                end
                return n
            end
            local sa, sb = reps(collect_keys(a)), reps(collect_keys(b))
            if sa > sb then
                return a, b
            elseif sb > sa then
                return b, a
            elseif a < b then
                return a, b
            else
                return b, a
            end
        end

        -- Hard fork protects my ORDER.
        -- Walking my order back from the tip, everything older than fork.time
        -- (or fork.posts entries back) is SETTLED.
        -- `their`: the expected order this sync would leave behind
        -- must reproduce that prefix verbatim, or it is a hard fork.
        local function hardfork (their)
            local our = dofile(FC .. "state.lua").order
            if #our == 0 then
                return false
            end

            local low = math.max(1, #our-C.fork.posts+1)
            -- order holds action IDs; timestamps live in commits
            local cs = {}
            for i=low, #our do
                cs[i] = assert(CID(our[i]), "bug found")
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

        -- `merge` is deliberately absent: those commits are built on a
        -- fetched range subsumes ORD + AID + CID
        -- aid -> commit for entries this replay applied; falls back to
        -- history for entries below the octopus (always reachable)
        local ORD = {}
        local function ORD_COMMIT (aid)
            return ORD[aid] or CID(aid)
        end

        local function commit (G, cid, beg)
            local key, err = ssh.verify(REPO, cid)

            local time = tonumber((exec {
                cmd = "git -C " .. REPO .. " log -1 --format=%at " .. cid
            }))

            -- one diff CLASSIFIES and MODE-CHECKS (par.5): the tree
            -- determines everything, no trailer to trust. Closed sets:
            --   A|AA .freechains/actions/<hex>.lua  exactly one (action;
            --        AA: added vs both parents -- beg-merge like)
            --   A    <payload outside .freechains/> posts only
            --                                       (in-tree until S10)
            --   M|MM .freechains/state.lua          joined action, or
            --                                       sync state merge
            local aid, pays, stat
            do
                local diff = exec {
                    cmd = "git -C " .. REPO ..
                        " diff-tree --cc --no-commit-id -r --name-status " .. cid
                }
                local acts = 0
                pays = 0
                for status, path in diff:gmatch("(%a+)%s+(%S+)") do
                    local bad = true
                    if (status=="A" or status=="AA") and
                       path:match("^%.freechains/actions/%x+%.lua$") then
                        acts = acts + 1
                        aid = path:match("actions/(%x+)%.lua")
                        bad = false
                    elseif status=="A" and not path:match("^%.freechains/") then
                        pays = pays + 1
                        bad = false
                    elseif status=="M" or status=="MM" then
                        bad = (path ~= ".freechains/state.lua")
                        stat = not bad
                    end
                    if bad then
                        error (
                            "invalid commit : mode violation : " ..
                                status .. " " .. path
                            , 0
                        )
                    end
                end
                if acts > 1 then
                    error("invalid commit : multiple action files", 0)
                end
            end

            if not aid then
                -- no action file: only a merge is honest (S9.3/S11a);
                -- payloads only ride action commits
                if #parents(cid) < 2 then
                    error("invalid commit : expects one action file", 0)
                end
                if pays > 0 then
                    error("invalid merge : mode violation : payload", 0)
                end
                if stat then
                    -- sync state merge: `now` is derived, not trusted
                    local mx = PEAKS(parents(cid))
                    if PEAK(cid) ~= mx then
                        error("invalid state : now", 0)
                    end
                end
                -- else: plumbing merge ('ours' tree): records nothing
                return
            end

            -- action commit: its own file self-describes the kind
            -- data only: no globals to attacker Lua (see READ)
            local t
            do
                local src = exec {
                    cmd = "git -C " .. REPO .. " show " .. cid ..
                        ":.freechains/actions/" .. aid .. ".lua"
                }
                local f = load(src, nil, "t", {})
                local ok
                if f then
                    ok, t = pcall(f)
                end
                if (not f) or (not ok) or type(t)~='table' then
                    error("invalid commit : invalid lua metadata", 0)
                end
            end
            local kind = t.action
            if kind~='post' and kind~='like' and kind~='revoke' then
                error("invalid commit : invalid action", 0)
            end

            if (not key) and err=='forged' then
                error("invalid " .. kind .. " : invalid signature", 0)
            end
            if pays > 0 and kind ~= 'post' then
                error("invalid " .. kind .. " : mode violation : payload", 0)
            end

            if kind == 'post' then
                local ok, err = apply(G, 'post', time, {
                    aid     = aid,
                    parents = parents(cid),
                    sign    = key,
                    beg     = beg or (key == nil),
                })
                if not ok then
                    error("invalid post : " .. err, 0)
                end
            else
                if not key then
                    error("invalid " .. kind .. " : missing sign key", 0)
                end
                -- only a positive `like` accepts a beg
                local to_beg = (
                    kind == 'like' and t.n > 0
                    and t.post and (G.posts[t.post] and G.posts[t.post].maturity=="beg")
                )
                local ok, err = apply(G, kind, time, {
                    aid     = aid,
                    parents = parents(cid),
                    sign    = key,
                    n       = t.n,
                    post    = t.post,
                    author  = t.author,
                    beg     = to_beg,
                })
                if not ok then
                    error("invalid " .. kind .. " : " .. err, 0)
                end
            end
            ORD[aid] = cid
            G.order[#G.order+1] = aid
        end

        ---------------------------------------------------------------------------
        ---------------------------------------------------------------------------

        -- we need to check an FF hardfork first:
        --  - remote contains all of our history
        --  - so if our settled order diverges
        --  - we need to fail fast, before replay and fail with other error
        local ff = exec { stderr=false, err=false,
            cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. loc .. " " .. rem
        }
        if ff then
            local their = READ(exec {
                cmd = "git -C " .. REPO .. " show " .. rem ..
                        ":.freechains/state.lua"
            }).order
            if hardfork(their) then
                ERROR("chain sync : hard fork")
            end
        end

        -- 3,4: need common ancestor

        local oct, G_oct
        do
            oct = octopus(loc, rem)
            G_oct = READ(exec {
                cmd = "git -C " .. REPO .. " show " .. oct ..
                        ":.freechains/state.lua"
            })
        end

        -- 4: needs fst/winner - snd/loser (do now b/c 3 mutates G_oct)
        local fst, snd = consensus(G_oct, loc, rem)

        -- 3,4: need remote validation: replay remote branch from G_oct
        local G_rem = G_oct -- (G_oct no longer required)
        do
            -- visited: never re-applies a shared commit
            -- ancestor(cur,com): stops climb from descending below its floor
            -- without these the inner meet underflows to a root
            local visited = {}
            for _, i in ipairs(G_rem.order) do
                visited[assert(CID(i), "bug found")] = true
            end
            local function ancestor (a, b)
                return exec { err=false, stderr=false,
                    cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. a .. " " .. b
                }
            end
            local climb, meet

            climb = function (G, com, cur, beg)
                if cur==com or visited[cur] or ancestor(cur,com) then
                    return
                else
                    local ps = parents(cur)
                    assert(#ps <= 2, "bug: >2 parents")
                    local p1, p2 = ps[1], ps[2]
                    if p2 == nil then
                        climb(G, com, p1, beg)
                    else
                        -- like positivity (n>0) is enforced in commit()
                        -- only a beg-merge like is 2-parent WITH an
                        -- action file
                        local is_beg_merge = (AID(cur) ~= nil)
                        meet(G, com, p1, p2, is_beg_merge)
                    end
                    visited[cur] = true
                    commit(G, cur, beg)
                end
            end

            meet = function (G, com, left, right, right_is_beg)
                local up = octopus(left, right)
                climb(G, com, up, false)
                local w = consensus(G, left, right)
                if w == left then
                    climb(G, up, left,  false)
                    climb(G, up, right, right_is_beg)
                else
                    climb(G, up, right, right_is_beg)
                    climb(G, up, left,  false)
                end
            end

            local ok, err = pcall(climb, G_rem, oct, rem, false)
            if not ok then
                ERROR("chain sync : " .. err)
            end
        end

        -- 3. local has nothing new
        if ff then
            exec {
                cmd = "git -C " .. REPO .. " merge --ff-only " .. rem
            }
            -- verify remote state: overwrite with G_rem, diff vs HEAD
            do
                G_rem.now = NOW("HEAD")
                WRITE(G_rem)
                local same = exec { stderr=false, err=false,
                    cmd = "git -C " .. REPO ..  " diff --quiet HEAD -- .freechains/state.lua"
                }
                if not same then
                    exec {
                        cmd = "git -C " .. REPO .. " reset --hard " .. loc
                    }
                    ERROR("chain sync : remote state mismatch")
                end
            end
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
                    G_fst = dofile(FC .. "state.lua")
                    ids = G_rem.order
                else
                    G_fst = G_rem
                    ids = dofile(FC .. "state.lua").order
                end
                -- order holds IDs; the loser replay walks COMMITS
                for _, i in ipairs(ids) do
                    O_snd[#O_snd+1] = assert(ORD_COMMIT(i), "bug found")
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
                if AID(cid) then
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

                ok, err = pcall(commit, G_fst, cid, nil)
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
                print("voided : " .. assert(AID(cid)))
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
                exec { stderr=false,
                    cmd = "git -C " .. REPO .. " merge --no-commit " .. merge
                }
                G_fst.now = PEAKS { "HEAD", "MERGE_HEAD" }
                WRITE(G_fst)
                exec {
                    cmd = "git -C " .. REPO .. " add .freechains/state.lua"
                }
                exec {
                    cmd = CMD.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
                    .. " --no-edit"
                }
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
end
