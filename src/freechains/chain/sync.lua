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
        --  - higher sum wins, hash tiebreaker (smaller wins)
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
                for hash in out:gmatch("%x+") do
                    local key = ssh.pubkey(REPO, hash)
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
            local our = dofile(FC .. "state/order.lua")
            if #our == 0 then
                return false
            end

            local low = math.max(1, #our-C.fork.posts+1)
            local hs = table.concat(our, " ", low, #our)

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
            local new = assert(ts[our[#our]])
            for i=#our, low, -1 do
                if (new-assert(ts[our[i]])) >= C.fork.time then
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
        -- detached head and discarded, so `main` never holds one
        local KINDS = { post=true, like=true, revoke=true, state=true }

        local function commit (G, hash, beg)
            local key, err = ssh.verify(REPO, hash)

            local out = exec {
                cmd = "git -C " .. REPO .. " log -1 --format='%at %(trailers:key=Freechains,valueonly)' " .. hash
            }
            local time,kind = out:match("(%S+)%s+(%S+)")
            if not KINDS[kind] then
                error("invalid commit : invalid kind", 0)
            end

            if (not key) and err=='forged' then
                error("invalid " .. kind .. " : invalid signature", 0)
            end

            -- create-mode check (post/like): only additions allowed
            -- state check: closed path set, A or M only (no D)
            -- --cc handles merges and non-merges uniformly
            local diff = exec {
                cmd = "git -C " .. REPO ..
                    " diff-tree --cc --no-commit-id -r --name-status " .. hash
            }
            if kind == 'state' then
                for status, path in diff:gmatch("(%a+)%s+(%S+)") do
                    local ok = (
                        (path == ".freechains/state/authors.lua") or
                        (path == ".freechains/state/posts.lua")   or
                        (path == ".freechains/state/order.lua")   or
                        (path == ".freechains/state/now.lua")
                    )
                    if not ok then
                        error (
                            "invalid state : " .. path
                            , 0
                        )
                    end
                    if status:match("[^AM]") then
                        error (
                            "invalid state : " .. path
                            , 0
                        )
                    end
                end
            else
                for status, path in diff:gmatch("(%a+)%s+(%S+)") do
                    if status:match("[^A]") then
                        error (
                            "invalid " .. kind ..
                                " : mode violation : " ..
                                status .. " " .. path
                            , 0
                        )
                    end
                end
            end

            if kind=='like' or kind=='revoke' then
                if not key then
                    error("invalid " .. kind .. " : missing sign key", 0)
                end

                -- vote metadata lives under .freechains/<kind>s/
                local file = exec {
                    cmd = "git -C " .. REPO .. " diff-tree --no-commit-id -r --name-only " .. hash .. "^1 " .. hash .. " -- .freechains/" .. kind .. "s/"
                }
                file = file:match("(%S+)")
                if not file then
                    error("invalid " .. kind .. " : missing metadata file", 0)
                end
                local src = exec {
                    cmd = "git -C " .. REPO .. " show " .. hash .. ":" .. file
                }
                local f = load(src)
                if not f then
                    error("invalid " .. kind .. " : invalid lua metadata", 0)
                end
                local ok, t = pcall(f)
                if (not ok) or type(t)~='table' then
                    error("invalid " .. kind .. " : invalid lua metadata", 0)
                end
                -- only a positive `like` accepts a beg
                local to_beg = (
                    kind == 'like' and t.n > 0
                    and t.post and (G.posts[t.post] and G.posts[t.post].maturity=="beg")
                )
                local ok, err = apply(G, kind, tonumber(time), {
                    hash   = hash,
                    sign   = key,
                    n      = t.n,
                    post   = t.post,
                    author = t.author,
                    beg    = to_beg,
                })
                if not ok then
                    error("invalid " .. kind .. " : " .. err, 0)
                end
                G.order[#G.order+1] = hash
            elseif kind == 'post' then
                local ok, err = apply(G, 'post', tonumber(time), {
                    hash = hash,
                    sign = key,
                    beg  = beg or (key == nil),
                })
                if not ok then
                    error("invalid post : " .. err, 0)
                end
                G.order[#G.order+1] = hash
            else
                assert(kind == 'state')
                -- need to check now, since it is derived, not trusted
                local mx = PEAKS(parents(hash))
                if PEAK(hash) ~= mx then
                    error("invalid state : now", 0)
                end
            end
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
            local their = load(exec {
                cmd = "git -C " .. REPO .. " show " .. rem ..
                        ":.freechains/state/order.lua"
            })()
            if hardfork(their) then
                ERROR("chain sync : hard fork")
            end
        end

        -- 3,4: need common ancestor

        local oct, G_oct
        do
            oct = octopus(loc, rem)
            local function F (path)
                local src = exec {
                    cmd = "git -C " .. REPO .. " show " .. oct .. ":" .. path
                }
                return load(src)()
            end
            G_oct = {
                authors = F(".freechains/state/authors.lua"),
                posts   = F(".freechains/state/posts.lua"),
                order   = F(".freechains/state/order.lua"),
                now     = F(".freechains/state/now.lua"),
            }
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
            for _, h in ipairs(G_rem.order) do
                visited[h] = true
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
                        local is_beg_merge = (trailer(cur) == "like")
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
                G_rem.now = PEAKS(parents("HEAD"))
                write(G_rem)
                local same = exec { stderr=false, err=false,
                    cmd = "git -C " .. REPO ..  " diff --quiet HEAD -- .freechains/state/"
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
            local O_snd
            if fst == loc then
                G_fst = {
                    authors = dofile(FC .. "state/authors.lua"),
                    posts   = dofile(FC .. "state/posts.lua"),
                    order   = dofile(FC .. "state/order.lua"),
                    now     = dofile(FC .. "state/now.lua"),
                }
                O_snd = G_rem.order
            else
                G_fst = G_rem
                O_snd = dofile(FC .. "state/order.lua")
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

            for _, hash in ipairs(O_snd) do
                local kind = trailer(hash)

                if kind~='state' then
                    ok = exec { stderr=false, err=false,
                        cmd = "git -C " .. REPO .. " merge --no-commit " .. hash
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
                        .. " --trailer 'Freechains: merge'"
                    }
                end

                ok, err = pcall(commit, G_fst, hash, nil)
                if not ok then
                    goto DONE
                end

                merge = hash
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
            for hash in out:gmatch("%x+") do
                if trailer(hash) ~= 'state' then
                    print("voided : " .. hash)
                end
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
                -- the peak we record is DERIVED from the parents of the
                -- commit we are about to create, never from `G.now`: a
                -- commit voided by a cascade advances the accumulator but
                -- leaves no trace in the DAG, and the stored value has to
                -- stay reproducible by every peer that replays this merge.
                G_fst.now = PEAKS { "HEAD", "MERGE_HEAD" }
                write(G_fst)
                exec {
                    cmd = "git -C " .. REPO .. " add .freechains/state/"
                }
                exec {
                    cmd = CMD.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
                    .. " --no-edit --trailer 'Freechains: state'"
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
