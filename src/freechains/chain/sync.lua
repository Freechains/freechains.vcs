require "freechains.chain.common"

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
            " log --reverse --no-merges --format='%H %at %GF' " ..
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
            local ok, err = apply(G, 'post', tonumber(time), {
                hash = hash,
                sign = key,
                beg  = (key == nil),
            })
            if not ok then
                return false, err .. " : " .. hash
            end
        else
            assert(trailer == "state")
        end
    end
    return true
end

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

    local com, G_com
    do
        com = exec (
            "git -C " .. REPO .. " merge-base " .. loc .. " " .. rem
        )
        if com == loc then
            G_com = {
                authors = dofile(FC .. "state/authors.lua"),
                posts   = dofile(FC .. "state/posts.lua"),
                now     = dofile(FC .. "state/now.lua"),
            }
        else
            local trailer = exec (
                "git -C " .. REPO .. " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. com
            )
            assert (
                trailer:match("state")
                , "bug found: merge-base is not a state commit"
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
                now     = F(".freechains/state/now.lua"),
            }
        end
    end

    -- verify remote: replay remote branch from copy of G_com
    local G_rem = { authors={}, posts={}, now=G_com.now }
    do
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
        local ok, err = replay(G_rem, com, rem)
        if not ok then ERROR("chain sync : replay : " .. err) end
    end

    -- final state
    local G_end
    do
        if com == loc then
            -- fast-forward: load local, replay remote
            G_end = G_com
            local ok, err = replay(G_end, loc, rem)
            if not ok then ERROR("chain sync : replay : " .. err) end
        else
            -- divergent: winner already computed, replay loser
            local fst, snd = consensus(com, loc, rem)
            if fst == loc then
                G_end = {
                    authors = dofile(FC .. "state/authors.lua"),
                    posts   = dofile(FC .. "state/posts.lua"),
                    now     = dofile(FC .. "state/now.lua"),
                }
                local fst_now = G_end.now
                G_end.now = G_com.now
                local ok, err = replay(G_end, com, rem)
                if not ok then ERROR("chain sync : replay : " .. err) end
                G_end.now = math.max(G_end.now, fst_now)
            else
                G_end = G_rem
                local fst_now = G_end.now
                G_end.now = G_com.now
                local ok, err = replay(G_end, com, loc)
                if not ok then ERROR("chain sync : replay : " .. err) end
                G_end.now = math.max(G_end.now, fst_now)
            end
        end
    end

    -- merge
    do
        -- stash state files to avoid merge conflicts
        exec (
            "git -C " .. REPO
            .. " stash push -- .freechains/state/authors.lua .freechains/state/posts.lua"
        )
        --exec(true, "git -C " .. REPO .. " stash drop")
        local _, code = exec (true,
            "git -C " .. REPO .. " merge --no-edit FETCH_HEAD"
        )
        if code ~= 0 then
            exec(true, "git -C " .. REPO .. " merge --abort")
            ERROR("chain sync : merge conflict")
            -- TODO(a): conflict is not error, just one of the sides is lost
        end
    end

    -- write replayed state to disk
    do
        write(G_end.authors, FC .. "state/authors.lua")
        write(G_end.posts,   FC .. "state/posts.lua")
    end

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
