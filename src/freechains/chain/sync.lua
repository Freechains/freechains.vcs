require "freechains.chain.common"

if ARGS.send then
    -- TODO(b): this should move away from here
    -- commit state if dirty
    do
        exec (
            "git -C " .. REPO .. " add .freechains/authors.lua .freechains/posts.lua"
        )
        local _, code = exec (true,
            "git -C " .. REPO .. " diff --cached --quiet"
        )
        if code ~= 0 then
            exec (
                NOW.git .. "git -C " .. REPO .. " commit --allow-empty-message"
                    .. " --trailer 'freechains: state' -m ''"
            )
        end
    end

    error "TODO: not implemented"
    exec (
        "git -C " .. REPO .. " push " .. ARGS.remote .. " main"
        , "chain sync : push failed"
    )

elseif ARGS.recv then
    exec (
        "git -C " .. REPO .. " fetch " .. ARGS.remote .. " main"
        , "chain sync : fetch failed"
    )

    local loc = exec("git -C " .. REPO .. " rev-parse HEAD")
    local rem = exec("git -C " .. REPO .. " rev-parse FETCH_HEAD")

    if loc == rem then
        goto RECV
    end

    local com = exec (
        "git -C " .. REPO .. " merge-base " .. loc .. " " .. rem
    )

    local function git_load (ref, path)
        local src = exec("git -C " .. REPO .. " show " .. ref .. ":" .. path)
        return load(src)()
    end

    -- replay commits from range onto state G
    local function replay (G, old, new)
        local out = exec (
            "git -C " .. REPO ..
                " log --reverse --no-merges --format='%H %at %GK' " ..
                (old .. ".." .. new)
        )
        for line in out:gmatch("[^\n]+") do
            local hash, time, key = line:match("^(%S+) (%S+) ?(.*)")
            if key == "" then key = nil end

            local trailer = exec("git -C " .. REPO .. " log -1 --format='%(trailers:key=freechains,valueonly)' " .. hash)
            if trailer == "state" then
                -- skip
            elseif trailer == "like" then
                -- TODO: replay likes via apply
            else
                apply(G, {
                    kind = 'post',
                    hash = hash,
                    sign = key,
                    time = tonumber(time),
                    beg  = (key == nil),
                })
            end
        end
    end

    -- Phase 1: verify remote
    local G_rem     -- reused if remote wins
    do
        G_rem = {
            authors = git_load(com, ".freechains/authors.lua"),
            posts   = git_load(com, ".freechains/posts.lua"),
        }
        replay(G_rem, com, rem)
        -- TODO: compare G_rem with remote's last state commit
        -- if mismatch -> ERROR("chain sync : dishonest remote")
    end

    -- Phase 2: consensus
    local fst, snd = loc, rem

    if com == loc then
        -- fast forward
    else
        local function first (old, new)
            return exec (
                "git -C " .. REPO .. " rev-list --reverse --max-count=1 "
                    .. old .. ".." .. new
            )
        end
        local l = tonumber((exec(
            "git -C " .. REPO .. " log -1 --format=%at " .. first(com,loc)
        )))
        local r = tonumber((exec(
            "git -C " .. REPO .. " log -1 --format=%at " .. first(com,rem)
        )))
        if l < r then
            fst, snd = loc, rem
        elseif l > r then
            fst, snd = rem, loc
        elseif loc < rem then
            fst, snd = loc, rem
        else
            fst, snd = rem, loc
        end
    end

    -- load winner state + replay loser
    local G
    if fst == loc then
        -- winner is local: use disk state, replay remote
        G = {
            authors = dofile(FC .. "/authors.lua"),
            posts   = dofile(FC .. "/posts.lua"),
        }
        replay(G, com, rem)
    else
        -- winner is remote: reuse verified state, replay local
        G = G_rem
        replay(G, com, loc)
    end

    -- merge
    local _, code = exec (true,
        "git -C " .. REPO .. " merge --no-edit FETCH_HEAD"
    )
    if code ~= 0 then
        exec(true, "git -C " .. REPO .. " merge --abort")
        ERROR("chain sync : merge conflict")
        -- TODO(a): conflict is not error, just one of the sides is lost
    end

    -- write replayed state
    write(G.authors, FC .. "/authors.lua")
    write(G.posts,   FC .. "/posts.lua")

    ::RECV::
end
