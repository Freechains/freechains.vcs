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

-- Replay commits from range onto state G.
-- In case of error, partial replay has been applied.

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
                return false, hash .. " : " .. err
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
        local ok, err = replay(G_rem, com, rem)
        if not ok then
            ERROR("chain sync : invalid remote : " .. err)
        end
    end

    if com == loc then
        exec("git -C " .. REPO .. " merge --ff-only FETCH_HEAD")
        goto RECV
    end

    -- final state: consensus + replay looser
    local G_end
    do
        -- fst wins, use it as base, replay snd looser
        local fst, snd = consensus(com, loc, rem)
        local ok, err
        if fst == loc then
            G_end = {
                authors = dofile(FC .. "state/authors.lua"),
                posts   = dofile(FC .. "state/posts.lua"),
                now     = NOW(loc),
            }
            ok, err = replay(G_end, com, rem)
        else
            G_end = G_rem
            ok, err = replay(G_end, com, loc)
        end
        if not ok then
            -- TODO: replay returns the failing hash, but we need the last successful hash
            -- use that to merge winner with last-successful-commit instead of full branch tip
            -- if loser is local, signal "removal" for commits after last successful
            error("TODO : replay fail : " .. err)
        end
    end

    -- merge + write state + commit
    do
        local _, code = exec(true,
            "git -C " .. REPO .. " merge --no-commit --no-edit FETCH_HEAD"
        )
        if code ~= 0 then
            exec(true, "git -C " .. REPO .. " merge --abort")
            error("TODO : merge conflict (content)")
        end

        write(G_end)
        exec("git -C " .. REPO .. " add .freechains/state/")
        exec("git -C " .. REPO .. " commit --no-edit")
    end

    ::RECV::
end
