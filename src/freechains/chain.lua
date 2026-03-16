local C = require "freechains.constants"

local REPO = ARGS.root .. "/chains/" .. ARGS.alias .. "/"

local G = {
    authors = dofile(REPO .. ".freechains/authors.lua"),
    posts   = dofile(REPO .. ".freechains/posts.lua"),
}

local function write (T, file)
    local f = io.open(file, "w")
    f:write(serial(T))
    f:close()
end

do
    local f = io.open(REPO .. ".freechains/genesis.lua")
    if not f then
        ERROR("chain " .. ARGS.alias .. " : not found")
    end
    f:close()
end

-- stage: advance time effects
do
    local L = REPO .. ".freechains/local/"
    local stored = dofile(L .. "now.lua")

    if ARGS.sign ~= nil or NOW.s > stored then
        -- discount scan
        for hash, entry in pairs(G.posts) do
            if entry.state == "00-12" then
                local subs = {}
                for h2, other in pairs(G.posts) do
                    if other.time and other.time > entry.time then
                        subs[other.author] = true
                    end
                end
                if ARGS.sign then
                    subs[ARGS.sign] = true
                end

                local cur = 0
                for a in pairs(subs) do
                    cur = cur + math.max(0, (G.authors[a] and G.authors[a].reps) or 0)
                end
                local tot = 0
                for _, v in pairs(G.authors) do
                    tot = tot + math.max(0, v.reps)
                end

                local ratio = (tot>0 and cur/tot) or 0
                local discount = C.time.half * math.max(0, 1 - 2*ratio)

                if NOW.s >= entry.time + discount then
                    G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                    entry.state = "12-24"
                end
            end
        end

        -- consolidation scan
        for hash, entry in pairs(G.posts) do
            if entry.state == "12-24" then
                if NOW.s >= entry.time + C.time.full then
                    local last = G.authors[entry.author].time
                    if NOW.s - last >= C.time.full then
                        G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                        G.authors[entry.author].time = last + C.time.full
                        entry.state = nil
                        entry.time  = nil
                    end
                end
            end
        end

        -- cap all authors at max (for query paths)
        if ARGS.sign == nil then
            for k, v in pairs(G.authors) do
                if v.reps > C.reps.max then
                    v.reps = C.reps.max
                end
            end
        end

        write(G.authors, REPO .. ".freechains/authors.lua")
        write(G.posts,   REPO .. ".freechains/posts.lua")
        write(NOW.s, L .. "now.lua")
    end
end

if ARGS.reps then
    local function ext (int)
        if int > 0 then
            return math.tointeger((int + 999) // 1000)
        elseif int < 0 then
            return -math.tointeger((-int + 999) // 1000)
        else
            return 0
        end
    end

    if ARGS.target == "post" then
        if not ARGS.key then
            ERROR("chain reps : post requires a hash")
        end
        local e = G.posts[ARGS.key]
        local v = (e and e.reps) or 0
        print(ext(v))
    elseif ARGS.target == "posts" then
        local T = {}
        for k, v in pairs(G.posts) do
            T[#T+1] = { k=k, v=v.reps }
        end
        table.sort(T, function (a, b) return a.v > b.v end)
        for _, e in ipairs(T) do
            print(e.k .. " " .. ext(e.v))
        end
    elseif ARGS.target == "author" then
        if not ARGS.key then
            ERROR("chain reps : author requires a pubkey")
        end
        local e = G.authors[ARGS.key]
        local v = (e and e.reps) or 0
        print(ext(v))
    elseif ARGS.target == "authors" then
        local T = {}
        for k, v in pairs(G.authors) do
            T[#T+1] = { k=k, v=v.reps }
        end
        table.sort(T, function (a, b) return a.v > b.v end)
        for _, e in ipairs(T) do
            print(e.k .. " " .. ext(e.v))
        end
    else
        ERROR("chain reps : invalid target : " .. ARGS.target)
    end
elseif ARGS.post or ARGS.like or ARGS.dislike then
    local kind, files, blob

    if G.authors[ARGS.sign].reps < C.reps.unit then
        ERROR("chain post : BLOCKED : insufficient reputation")
    end

    if ARGS.post then
        kind = "post"
        if ARGS.inline then     -- before ambiguous ARGS.file
            local text = ARGS.text
            if not text:match("\n$") then
                text = text .. "\n"
            end

            if ARGS.file then   -- ambiguous with post file
                files = ARGS.file
                local f = io.open(REPO .. ARGS.file, "a")   -- appends
                f:write(text)
                f:close()
            else
                blob = exec (true,
                    "printf '%s' '" .. text .. "' | git hash-object --stdin"
                )
                files = "post-" .. NOW.s .. "-" .. blob:sub(1,8) .. ".txt"
                local f = io.open(REPO .. files, "w")       -- truncates
                f:write(text)
                f:close()
            end
        elseif ARGS.file then   -- after ARGS.inline
            files = ARGS.path:match("[^/]+$")
            exec (
                "cp " .. ARGS.path .. " " .. REPO .. "/"
                , "chain post : copy failed: " .. ARGS.path
            )
        end
        if not blob then
            blob = exec (true,
                "git hash-object " .. REPO .. files
            )
        end
    elseif ARGS.like or ARGS.dislike then
        kind = "like"

        if not ARGS.sign then
            ERROR("chain like : --sign is required")
        end

        if ARGS.number <= 0 then
            ERROR("chain like : expected positive integer")
        end

        if ARGS.target ~= "post" and ARGS.target ~= "author" then
            ERROR(
                "chain like : target must be 'post' or 'author'"
            )
        end

        -- validate target exists
        if ARGS.target == "post" then
            local tp = exec (
                "git -C " .. REPO .. " cat-file -t " .. ARGS.id
            )
            if tp ~= "commit" then
                ERROR("chain like : post not found : " .. ARGS.id)
            end
        end

        -- write like payload
        local num = ARGS.number
        if ARGS.dislike then
            num = -num
        end
        local payload = [[
            return {
                target = "]] .. ARGS.target .. [[",
                id     = "]] .. ARGS.id     .. [[",
                number = ]]  .. num         .. [[,
            }
        ]]
        blob = exec (true,
            "printf '%s' '" .. payload .. "' | git hash-object --stdin"
        )
        files = ".freechains/likes/like-" .. NOW.s .. "-" .. blob:sub(1,8) .. ".lua"
        local f = io.open(REPO .. files, "w")
        f:write(payload)
        f:close()
    end

    -- monotonic timestamp validation
    do
        local date = tonumber ((exec (true,
            "git -C " .. REPO .. " log -1 --format=%at"
        )))
        assert(date, "bug found : date is not a number")
        if NOW.s < date-C.time.future then
            ERROR("chain " .. kind .. " : cannot be older than parent")
        end
    end

    -- update reps on post/like
    do
        files = files .. " .freechains/authors.lua .freechains/posts.lua"

        if kind == "post" then
            if ARGS.sign then
                G.authors[ARGS.sign] = G.authors[ARGS.sign] or { reps=0 }
                G.authors[ARGS.sign].reps = G.authors[ARGS.sign].reps - C.reps.cost
                if G.authors[ARGS.sign].time == nil then
                    G.authors[ARGS.sign].time = NOW.s
                end
                G.posts[blob] = {
                    author = ARGS.sign,
                    time   = NOW.s,
                    state  = "00-12",
                    reps   = 0,
                }
            end

        elseif kind == "like" then
            local num = ARGS.number * C.reps.unit
            G.authors[ARGS.sign] = G.authors[ARGS.sign] or { reps=0 }
            G.authors[ARGS.sign].reps = G.authors[ARGS.sign].reps - num

            if ARGS.dislike then
                num = -num
            end

            num = num * (100 - C.like.tax) // 100     -- apply tax

            if ARGS.target == "post" then
                local a = exec (true,
                    "git -C " .. REPO .. " log -1 --format='%GK' " .. ARGS.id
                )
                G.authors[a] = G.authors[a] or { reps=0 }
                G.authors[a].reps = G.authors[a].reps + num // C.like.split
                G.posts[ARGS.id] = G.posts[ARGS.id] or { reps=0, author=a }
                G.posts[ARGS.id].reps = G.posts[ARGS.id].reps + num // C.like.split
            else
                G.authors[ARGS.id] = G.authors[ARGS.id] or { reps=0 }
                G.authors[ARGS.id].reps = G.authors[ARGS.id].reps + num
            end
        end

        -- cap all authors at max
        for k, v in pairs(G.authors) do
            if v.reps > C.reps.max then
                v.reps = C.reps.max
            end
        end

        write(G.authors, REPO .. ".freechains/authors.lua")
        write(G.posts,   REPO .. ".freechains/posts.lua")
    end

    exec (true,
        "git -C " .. REPO .. " add " .. files
    )

    local s1, s2 = "", ""
    if ARGS.sign then
        s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=openpgp"
        s2 = " -S"
    end

    local msg = ARGS.why or ""
    exec (true,
        NOW.git .. "git -C " .. REPO .. s1 .. " commit" .. s2 .. " --trailer 'freechains: " .. kind .. "'" .. " --allow-empty-message" .. " -m '" .. msg .. "'"
    )

    local hash = exec (true,
        "git -C " .. REPO .. " rev-parse HEAD"
    )
    print(hash)
end
