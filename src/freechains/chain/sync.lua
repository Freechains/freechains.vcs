require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

if ARGS.send then
    error "TODO: not implemented"
    exec (
        "git -C " .. REPO .. " push " .. ARGS.remote .. " main"
        , "chain sync : push failed"
    )

elseif ARGS.recv then
    exec ('stdout',
        "git -C " .. REPO .. " fetch " .. ARGS.remote .. " main"
        , "chain sync : fetch failed"
    )

    local loc = exec("git -C " .. REPO .. " rev-parse HEAD")
    local rem = exec("git -C " .. REPO .. " rev-parse FETCH_HEAD")

    --[[
    -- Four cases:
    --  1. unrelated histories (different genesis)
    --      - ERROR
    --  2. local contains remote (remote is ancestor of local)
    --      - DONE
    --  3,4: need common ancestor, remote validation/replay
    --      - replay_remote: climb / meet
    --  3. remote conains local (local is ancestor of remote)
    --      - merge with fast-forward
    --  4. local and remote diverge
    ]]

    -- 1. reject unrelated histories
    do
        local loc_root = exec (
            "git -C " .. REPO .. " rev-list --max-parents=0 " .. loc
        )
        local rem_root = exec (
            "git -C " .. REPO .. " rev-list --max-parents=0 " .. rem
        )
        if loc_root ~= rem_root then
            ERROR("chain sync : incompatible genesis")
        end
    end

    -- 2. remote has nothing new
    do
        local ok = exec (true, 'stdout',
            "git -C " .. REPO .. " merge-base --is-ancestor " .. rem .. " " .. loc
        )
        if ok then
            goto RECV
        end
    end

    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------

    -- Consensus: prefix reps from G decide winner
    --  - traverse com..tip, collect signed keys
    --  - sum G.authors[key].reps for each side
    --  - higher sum wins, hash tiebreaker (smaller wins)
    local function consensus (G, com, a, b)
        local function collect_keys (tip)
            local keys = {}
            local out = exec (
                "git -C " .. REPO .. " log --reverse --format=%H " .. com .. ".." .. tip
            )
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

    local function commit (G, hash)
        local key, err = ssh.verify(REPO, hash)

        local out = exec (
            "git -C " .. REPO .. " log -1 --format='%at %(trailers:key=Freechains,valueonly)' " .. hash
        )
        local time,kind = out:match("(%S+)%s+(%S+)")

        if (not key) and err=='forged' then
            error("invalid " .. kind .. " : invalid signature", 0)
        end

        if kind == 'like' then
            if not key then
                error("invalid like : missing sign key", 0)
            end

            local file = exec (
                "git -C " .. REPO .. " diff-tree --no-commit-id -r --name-only " .. hash .. " -- .freechains/likes/"
            )
            file = file:match("(%S+)")
            if not file then
                error("invalid like : missing metadata file", 0)
            end
            local src = exec (
                "git -C " .. REPO .. " show " .. hash .. ":" .. file
            )
            local f = load(src)
            if not f then
                error("invalid like : invalid lua metadata", 0)
            end
            local ok, like = pcall(f)
            if (not ok) or type(like)~='table' then
                error("invalid like : invalid lua metadata", 0)
            end
            local ok, err = apply(G, 'like', tonumber(time), {
                hash   = hash,
                sign   = key,
                num    = like.number,
                target = like.target,
                id     = like.id,
            })
            if not ok then
                error("invalid like : " .. err, 0)
            end
        elseif kind == 'post' then
            local ok, err = apply(G, 'post', tonumber(time), {
                hash = hash,
                sign = key,
                beg  = (key == nil),
            })
            if not ok then
                error("invalid post : " .. err, 0)
            end
        else
            assert(kind == 'state')
        end
        G.order[#G.order+1] = hash
    end

    local replay_remote
    do
        local function parents (tip)
            local out = exec (
                "git -C " .. REPO .. " rev-list --parents -1 " .. tip
            )
            local ps = {}
            for h in out:gmatch("%x+") do
                ps[#ps+1] = h
            end
            assert(#ps <= 3, "bug: >2 parents")
            return ps[2], ps[3]
        end

        local climb, meet

        climb = function (G, com, cur)
            if cur == com then
                return
            else
                local p1, p2 = parents(cur)
                if p2 == nil then
                    climb(G, com, p1)
                else
                    meet(G, com, p1, p2)
                end
                commit(G, cur)
            end
        end

        meet = function (G, com, left, right)
            local up = exec (
                "git -C " .. REPO .. " merge-base " .. left .. " " .. right
            )
            climb(G, com, up)
            local w = consensus(G, up, left, right)
            if w == left then
                climb(G, up, left)
                climb(G, up, right)
            else
                climb(G, up, right)
                climb(G, up, left)
            end
        end

          replay_remote = function (G, com, rem)
              return pcall(climb, G, com, rem)
          end
    end

    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------

    -- 3,4: need common ancestor

    local oct, G_oct
    do
        do
            local out = exec (
                "git -C " .. REPO .. " rev-list --boundary " ..
                    loc .. "..." .. rem
            )
            local boundary = {}
            for line in out:gmatch("[^\n]+") do
                local h = line:match("^%-(%x+)")
                if h then
                    boundary[#boundary+1] = h
                end
            end
            oct = exec (
                "git -C " .. REPO .. " merge-base --octopus " ..
                    table.concat(boundary, " ")
            )
        end
        local function F (path)
            local src = exec (
                "git -C " .. REPO .. " show " .. oct .. ":" .. path
            )
            return load(src)()
        end
        G_oct = {
            authors = F(".freechains/state/authors.lua"),
            posts   = F(".freechains/state/posts.lua"),
            order   = F(".freechains/state/order.lua"),
            now     = NOW(oct),
        }
        G_oct.order[#G_oct.order+1] = oct
    end

    -- 4: needs fst/winner - snd/loser (do now b/c 3 mutates G_oct)
    local fst, snd = consensus(G_oct, oct, loc, rem)

    -- 3,4: need remote validation: replay remote branch from G_oct
    local G_rem = G_oct -- (G_oct no longer required)
    do
        local ok, err = replay_remote(G_rem, oct, rem)
        if not ok then
            ERROR("chain sync : " .. err)
        end
    end

    -- 3. local has nothing new
    do
        local ff = exec (true, 'stdout',
            "git -C " .. REPO .. " merge-base --is-ancestor " .. loc .. " " .. rem
        )
        if ff then
            exec("git -C " .. REPO .. " merge --ff-only FETCH_HEAD")
            goto RECV
        end
    end

    --  4. local and remote diverge

    -- Replay loser commits from range onto state G_fst.
    -- Trial-merges each non-state commit against fst (detached HEAD).
    -- In case of error, partial replay has been applied.
    -- Returns: ok, last, err

    local function replay_loser (G_fst, O_snd, com, fst)
        local last = com

        exec ('stdout',
            "git -C " .. REPO .. " checkout --detach " .. fst
        )
        local _ <close> = setmetatable({}, {__close=function()
            exec ('stdout',
                "git -C " .. REPO .. " checkout main"
            )
        end})

        -- find O_snd[I] = first hash after com
        local I = 0
        for i,h in ipairs(O_snd) do
            if h == com then
                I = i + 1
            end
        end

        for i=I, #O_snd do
            local hash = O_snd[i]

            local trailer = exec (
                "git -C " .. REPO .. " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. hash
            )
            local kind = trailer:match("(%S+)") or ""

            if kind~='state' then
                local ok = exec (true, 'stdout',
                    "git -C " .. REPO .. " merge --no-commit " .. hash
                )
                if not ok then
                    exec (true, 'stdout',
                        "git -C " .. REPO .. " merge --abort"
                    )
                    return false, last, "content conflict"
                end
                exec ('stdout',
                    "git -C " .. REPO .. " commit -m 'x'"
                )
            end

            local ok, err = pcall(commit, G_fst, hash)
            if not ok then
                return ok, last, err
            end

            last = hash
        end

        return true, last, nil
    end

    -- TODO: coms

    -- final state: consensus + replay loser
    local G_fst, O_snd, merge
    do
        local ok, err
        if fst == loc then
            G_fst = {
                authors = dofile(FC .. "state/authors.lua"),
                posts   = dofile(FC .. "state/posts.lua"),
                order   = dofile(FC .. "state/order.lua"),
                now     = NOW(loc),
            }
            G_fst.order[#G_fst.order+1] = loc
            O_snd = G_rem.order
        else
            G_fst = G_rem
            O_snd = dofile(FC .. "state/order.lua")
            O_snd[#O_snd+1] = loc
        end
        ok, merge, err = replay_loser(G_fst, O_snd, coms, fst)
        if not ok then
            io.stderr:write("ERROR : " .. err .. "\n")
        end
    end

    -- list voided local commits (only when remote wins)
    if fst==rem and merge~=loc then
        local out = exec (
            "git -C " .. REPO .. " " ..
                "log --reverse --no-merges --format='%H' " ..
                (merge .. ".." .. loc)
        )
        for hash in out:gmatch("%x+") do
            local trailer = exec (
                "git -C " .. REPO .. " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. hash
            )
            local kind = trailer:match("(%S+)") or ""
            if kind ~= 'state' then
                print("voided : " .. hash)
            end
        end
    end

    -- reset HEAD to winner tip, merge last non-conflicting loser + state
    do
        if fst ~= loc then
            exec ("git -C " .. REPO .. " reset --hard " .. fst)
        end

        -- TODO: is it possible to be equal?
        if merge ~= TODO then
            exec ('stdout',
                "git -C " .. REPO .. " merge --no-commit " .. merge
            )
            write(G_fst)
            exec("git -C " .. REPO .. " add .freechains/state/")
            exec (
                CMD.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
                .. " --no-edit --trailer 'Freechains: state'"
            )
        end
    end

    ::RECV::
end
