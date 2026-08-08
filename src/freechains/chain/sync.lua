require "freechains.chain.common"
require "freechains.chain.consensus"

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

        -- needs fst/winner - snd/loser (do now b/c replay mutates G_oct)
        local fst, snd = consensus(G_oct, loc, rem)

        -- remote validation: replay remote branch from G_oct
        local G_rem = G_oct -- (G_oct no longer required)
        do
            local ok, err = pcall(replay, G_rem, oct, rem)
            if not ok then
                ERROR("chain sync : " .. err)
            end
        end

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
                G_fst.now = PEAKS { "HEAD", "MERGE_HEAD" }
                write(G_fst)
                exec {
                    cmd = "git -C " .. REPO .. " add .freechains/state/"
                }
                exec {
                    cmd = CMD.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
                    .. " --no-edit --trailer 'Freechains: state'"
                }
            elseif fst ~= loc then
                -- remote wins and no merge: need to verify state
                -- 1. FF (remote always wins: case 2 rules out the
                --    converse, ancestor rule in `consensus` decides)
                -- 2. failing merge at first commit
                G_fst.now = PEAKS(parents("HEAD"))
                write(G_fst)
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
