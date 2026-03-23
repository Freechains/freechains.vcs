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

    -- Consensus (common, left, right)
    --  - tip hash as simplest criteria
    local function consensus (com, a, b)
        if a < b then
            return a, b
        elseif b < a then
            return b, a
        else
            error "bug found"
        end
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

            local trailer = exec (
                "git -C " .. REPO .. " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. hash
            )
            trailer = trailer:match("(%S+)") or ""
            if trailer == "like" then
                error "TODO: replay likes via apply"
            elseif trailer == "post" then
                apply(G, 'post', tonumber(time), {
                    hash = hash,
                    sign = key,
                    beg  = (key == nil),
                })
            else
                assert(trailer == "state")
                --error "bug found: should never reach state commit"
            end
        end
    end

    -- Find checkpoint (chk) and `apply` up to merge-base (com):
    --  - load state at merge-base
    --  - walk back to last state commit (or genesis)
    --  - load from there, replay forward to merge-base
    --  - guaranteed that no merges appear betwen chk <- com
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
            authors = F(".freechains/state/authors.lua"),
            posts   = F(".freechains/state/posts.lua"),
            now     = F(".freechains/state/now.lua"),
        }
        if chk ~= com then
            replay(G_com, chk, com)
        end
    end

    -- verify remote: replay remote branch from copy of G_com
    local G_rem = { authors={}, posts={}, now=G_com.now }
    for k, v in pairs(G_com.authors) do
        G_rem.authors[k] = { reps=v.reps, time=v.time }
    end
    for k, v in pairs(G_com.posts) do
        G_rem.posts[k] = {
            author = v.author,
            time   = v.time,
            state  = v.state,
            reps   = v.reps,
        }
    end
    replay(G_rem, com, rem)

    -- consensus
    local fst, snd
    if com == loc then
        fst, snd = loc, rem
    else
        fst, snd = consensus(com, loc, rem)
    end

    -- load winner state + replay loser
    local G
    if fst == loc then
        -- winner is local: replay both
        G = G_com
        replay(G, com, loc)
        replay(G, com, rem)
    else
        -- winner is remote: reuse verified state, replay local
        G = G_rem
        replay(G, com, loc)
    end

    -- stash state files to avoid merge conflicts
    exec (
        "git -C " .. REPO
        .. " stash push -- .freechains/state/authors.lua .freechains/state/posts.lua"
    )
    --exec(true, "git -C " .. REPO .. " stash drop")

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
    write(G.authors, FC .. "state/authors.lua")
    write(G.posts,   FC .. "state/posts.lua")

    -- commit state if non-ff merge
    if com ~= loc then
        exec (
            "git -C " .. REPO
            .. " add .freechains/state/authors.lua .freechains/state/posts.lua"
        )
        exec (
            NOW.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
            .. " --trailer 'Freechains: state'"
        )
    end

    ::RECV::
end
