require "freechains.chain.common"

if ARGS.send then
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

            local trailer = exec (
                "git -C " .. REPO .. " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. hash
            )
            trailer = trailer:match("(%S+)") or ""
            if trailer == "like" then
                error "TODO: replay likes via apply"
            elseif trailer == "post" then
                apply(G, {
                    kind = 'post',
                    hash = hash,
                    sign = key,
                    time = tonumber(time),
                    beg  = (key == nil),
                })
            else
                assert(trailer == "state")
                error "bug found: should never reach state commit"
            end
        end
    end

    -- Find checkpoint (chk) and `apply` up to merge-base (com):
    --  - load state at merge-base
    --  - walk back to last state commit (or genesis)
    --  - load from there, replay forward to merge-base
    local G_com
    do
        local chk   -- state commit
        do
            local out = exec (
                "git -C " .. REPO
                .. " log --format='%H %(trailers:key=Freechains,valueonly)' "
                .. com
            )
            for line in out:gmatch("[^\n]+") do
                local hash, trailer = line:match("^(%S+) ?(%S*)")
                if trailer == "state" then
                    chk = hash
                    break
                end
            end
            assert(chk, "bug found: no state commit in history")
        end

        local function F (path)
            local src = exec (
                "git -C " .. REPO .. " show " .. chk .. ":" .. path
            )
            return load(src)()
        end

        G_com = {
            authors = F(".freechains/authors.lua"),
            posts   = F(".freechains/posts.lua"),
        }
        if chk ~= com then
            replay(G_com, chk, com)
        end
    end

    -- verify remote: replay remote branch from G_com
    local G_rem = G_com
    replay(G_com, com, rem)

    -- consensus
    local fst, snd
    do
        -- fast forward
        if com == loc then
            fst, snd = loc, rem

        -- merge
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

    -- write replayed state to disk
    write(G.authors, FC .. "/authors.lua")
    write(G.posts,   FC .. "/posts.lua")

    -- commit state if non-ff merge
    if com ~= loc then
        exec (
            "git -C " .. REPO
            .. " add .freechains/authors.lua .freechains/posts.lua"
        )
        exec (
            NOW.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
            .. " --trailer 'Freechains: state'"
        )
    end

    ::RECV::
end
