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

    -- collect_linear: append post/like entries from a linear (no-merge) segment
    local function collect_linear (list, old, new)
        if old == new then return end
        local out = exec (
            "git -C " .. REPO .. " log --reverse --no-merges --format='%H %at %GK' " .. old .. ".." .. new
        )
        for line in out:gmatch("[^\n]+") do
            local hash, time, key = line:match("^(%S+) (%S+) ?(.*)")
            if key == "" then key = nil end
            local trailer = exec (
                "git -C " .. REPO .. " log -1 --format='%(trailers:key=Freechains,valueonly)' " .. hash
            )
            trailer = trailer:match("(%S+)") or ""
            if trailer == "like" then
                local files = exec (
                    "git -C " .. REPO .. " diff-tree --no-commit-id -r --name-only " .. hash
                )
                local like_file
                for f in files:gmatch("[^\n]+") do
                    if f:match("^%.freechains/likes/") then
                        like_file = f
                        break
                    end
                end
                assert(like_file, "bug found: like commit without like file")
                local src = exec (
                    "git -C " .. REPO .. " show " .. hash .. ":" .. like_file
                )
                local payload = load(src)()
                list[#list + 1] = {
                    kind   = 'like',
                    sign   = key,
                    num    = payload.number,
                    target = payload.target,
                    id     = payload.id,
                    time   = tonumber(time),
                }
            elseif trailer == "post" then
                list[#list + 1] = {
                    kind = 'post',
                    hash = hash,
                    sign = key,
                    time = tonumber(time),
                    beg  = (key == nil),
                }
            else
                assert(trailer == "state")
            end
        end
    end

    -- collect: recursive DAG decomposition respecting consensus order at merges
    local function collect (list, old, new)
        if old == new then return end
        local merge = exec (
            "git -C " .. REPO .. " rev-list --topo-order --merges --max-count=1 " .. old .. ".." .. new
        )
        if merge == "" then
            collect_linear(list, old, new)
            return
        end
        local parents = exec (
            "git -C " .. REPO .. " rev-parse " .. merge .. "^1 " .. merge .. "^2"
        )
        local p1, p2 = parents:match("^(%S+)\n(%S+)")
        local base = exec (
            "git -C " .. REPO .. " merge-base " .. p1 .. " " .. p2
        )
        -- if base is ancestor of old, skip prefix and use old as cutoff
        local eff = base
        if base ~= old then
            local mb = exec (
                "git -C " .. REPO .. " merge-base " .. base .. " " .. old
            )
            if mb == base then
                eff = old
            end
        end
        collect(list, old, eff)
        local fst, snd = consensus(base, p1, p2)
        collect(list, eff, fst)
        collect(list, eff, snd)
        collect_linear(list, merge, new)
    end

    -- replay: collect entries in consensus order, then apply
    local function replay (G, old, new)
        local list = {}
        collect(list, old, new)
        for _, entry in ipairs(list) do
            if entry.kind == 'like' and entry.target == "post" and G.posts[entry.id] and G.posts[entry.id].state == "blocked" then
                entry.beg = true
            end
            apply(G, entry)
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
            authors = F(".freechains/authors.lua"),
            posts   = F(".freechains/posts.lua"),
        }
        if chk ~= com then
            replay(G_com, chk, com)
        end
    end

    -- verify remote: replay remote branch from copy of G_com
    local G_rem = { authors = {}, posts = {} }
    for k, v in pairs(G_com.authors) do
        G_rem.authors[k] = { reps = v.reps, time = v.time }
    end
    for k, v in pairs(G_com.posts) do
        G_rem.posts[k] = { author = v.author, time = v.time, state = v.state, reps = v.reps }
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
        .. " stash push -- .freechains/authors.lua .freechains/posts.lua"
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
