require "freechains.chain.common"
local ssh = require "freechains.chain.ssh"

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

-- Replay commits from range onto state G.
-- In case of error, partial replay has been applied.
-- fst: if provided, trial-merge each non-state commit (detached HEAD).
-- Returns: ok, last, err

local function replay (G, com, fst, snd)
    local last = com
    local out = exec (
        "git -C " .. REPO ..
            " log --reverse --no-merges --format='%H %at' " ..
            (com .. ".." .. snd)
    )

    if fst then
        exec ('stdout',
            "git -C " .. REPO .. " checkout --detach " .. fst
        )
    end
    local _ <close> = setmetatable({}, {__close=function()
        if fst then
            exec ('stdout',
                "git -C " .. REPO .. " checkout main"
            )
        end
    end})

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

        if fst and kind~='state' then
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
            local ok, err = apply(G, 'like', tonumber(time), {
                sign   = key,
                num    = like.number,
                target = like.target,
                id     = like.id,
            })
            if not ok then
                return false, last, "invalid like : " .. err
            end
        elseif kind == 'post' then
            local ok, err = apply(G, 'post', tonumber(time), {
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
            now     = NOW(com),
        }
    end

    -- verify remote: replay remote branch from G_com
    local G_rem = G_com -- (G_com no longer required)
    do
        local ok, _, err = replay(G_rem, com, nil, rem)
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
    local G_end, merge
    do
        local ok, err
        if fst == loc then
            G_end = {
                authors = dofile(FC .. "state/authors.lua"),
                posts   = dofile(FC .. "state/posts.lua"),
                now     = NOW(loc),
            }
        else
            G_end = G_rem
        end
        ok, merge, err = replay(G_end, com, fst, snd)
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
            write(G_end)
            exec("git -C " .. REPO .. " add .freechains/state/")
            exec (
                CMD.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
                .. " --no-edit --trailer 'Freechains: state'"
            )
        end
    end

    ::RECV::
end
