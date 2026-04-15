require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

-- Forward DAG builder: parent -> child via childs
-- G = { root=fr, [hash] = { hash=hash, childs={...} } }
local function graph (dir, fr, to)
    local log = exec (
        "git -C " .. dir .. " rev-list --topo-order --reverse --parents " ..
            fr .. ".." .. to
    )
    local G = {
        root = fr,
        [fr] = { hash=fr, childs={} },
    }
    for l in log:gmatch("[^\n]+") do
        local hs = {}
        for h in l:gmatch("%x+") do
            hs[#hs+1] = h
        end
        local me = hs[1]
        G[me] = { hash=me, childs={} }
        for i=2, #hs do
            local up = G[hs[i]].childs
            up[#up+1] = me
        end
    end
    return G
end

-- Consensus: prefix reps from G_com decide winner
--  - traverse com..tip, collect signed keys
--  - sum G_com.authors[key].reps for each side
--  - higher sum wins, hash tiebreaker (smaller wins)
local function consensus (G_com, com, a, b)
    local function collect_keys (tip)
        local keys = {}
        local out = exec (
            "git -C " .. REPO .. " log --reverse --format=%H " .. com .. ".." .. tip
        )
        for hash in out:gmatch("%x+") do
            local key = ssh.verify(REPO, hash)
            if key then
                keys[key] = true
            end
        end
        return keys
    end
    local function reps (keys)
        local n = 0
        for key in pairs(keys) do
            local T = G_com.authors[key]
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

-- Replay remote commits from range onto state G_rem.
-- In case of error, partial replay has been applied.
-- Returns: ok, last, err

local function replay_remote (G_rem, com, rem)
    local last = com
    local out = exec (
        "git -C " .. REPO ..
            " log --reverse --no-merges --format='%H %at' " ..
            (com .. ".." .. rem)
    )

    for line in out:gmatch("[^\n]+") do
        local hash, time = line:match("^(%S+) (%S+)")
        local key, err = ssh.verify(REPO, hash)

        local trailer = exec (
            "git -C " .. REPO .. " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. hash
        )
        local kind = trailer:match("(%S+)") or ""

        if (not key) and (err == 'forged') then
            return false, last, "invalid " .. kind .. " : invalid signature"
        end

        if kind == 'like' then
            if not key then
                return false, last, "invalid like : missing sign key"
            end

            local file = exec (
                "git -C " .. REPO .. " diff-tree --no-commit-id -r --name-only " .. hash .. " -- .freechains/likes/"
            )
            file = file:match("(%S+)")
            if not file then
                return false, last, "invalid like : missing metadata file"
            end
            local src = exec (
                "git -C " .. REPO .. " show " .. hash .. ":" .. file
            )
            local f = load(src)
            if not f then
                return false, last, "invalid like : invalid lua metadata"
            end
            local ok, like = pcall(f)
            if (not ok) or type(like)~='table' then
                return false, last, "invalid like : invalid lua metadata"
            end
            local ok, err = apply(G_rem, 'like', tonumber(time), {
                hash   = hash,
                sign   = key,
                num    = like.number,
                target = like.target,
                id     = like.id,
            })
            if not ok then
                return false, last, "invalid like : " .. err
            end
        elseif kind == 'post' then
            local ok, err = apply(G_rem, 'post', tonumber(time), {
                hash = hash,
                sign = key,
                beg  = (key == nil),
            })
            if not ok then
                return false, last, "invalid post : " .. err
            end
        else
            assert(kind == 'state')
        end
        G_rem.order[#G_rem.order+1] = hash
        last = hash
    end

    return true, last, nil
end

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
        local time = NOW(hash)
        local key  = ssh.pubkey(REPO, hash)

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

        if kind == 'like' then
            local file = exec (
                "git -C " .. REPO .. " diff-tree --no-commit-id -r --name-only " .. hash .. " -- .freechains/likes/"
            )
            file = assert(file:match("(%S+)"))
            local src = exec (
                "git -C " .. REPO .. " show " .. hash .. ":" .. file
            )
            local like = assert(assert(load(src))())
            local ok, err = apply(G_fst, 'like', time, {
                hash   = hash,
                sign   = key,
                num    = like.number,
                target = like.target,
                id     = like.id,
            })
            if not ok then
                return false, last, "invalid like : " .. err
            end
        elseif kind == 'post' then
            local ok, err = apply(G_fst, 'post', time, {
                hash = hash,
                sign = key,
                beg  = (key == nil),
            })
            if not ok then
                return false, last, "invalid post : " .. err
            end
        else
            assert(kind == 'state')
        end
        G_fst.order[#G_fst.order+1] = hash
        last = hash
    end

    return true, last, nil
end

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

    if loc == rem then
        goto RECV
    end

    -- reject unrelated histories (different genesis)
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

    local com, G_com
    do
        com = exec (
            "git -C " .. REPO .. " merge-base " .. loc .. " " .. rem
        )
        local function F (path)
            local src = exec (
                "git -C " .. REPO .. " show " .. com .. ":" .. path
            )
            return load(src)()
        end
        G_com = {
            authors = F(".freechains/state/authors.lua"),
            posts   = F(".freechains/state/posts.lua"),
            order   = F(".freechains/state/order.lua"),
            now     = NOW(com),
        }
        G_com.order[#G_com.order+1] = com
    end

    -- verify remote: replay remote branch from G_com
    local G_rem = G_com -- (G_com no longer required)
    do
        local H = graph(REPO, com, rem)
        local ok, err = replay_remote(G_rem, H, com, nil)
        if not ok then
            ERROR("chain sync : " .. err)
        end
    end

    if com == loc then
        exec("git -C " .. REPO .. " merge --ff-only FETCH_HEAD")
        goto RECV
    end

    -- final state: consensus + replay loser
    local fst, snd = consensus(G_com, com, loc, rem)
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
        ok, merge, err = replay_loser(G_fst, O_snd, com, fst)
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

        if merge ~= com then
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
