local C = require "freechains.constants"

local REPO = ARGS.root .. "/chains/" .. ARGS.alias .. "/"
local FC   = REPO .. ".freechains/"

local G = {
    authors = dofile(FC .. "/authors.lua"),
    posts   = dofile(FC .. "/posts.lua"),
}

local xas, xps = false, false

local function write (T, file)
    local f = io.open(file, "w")
    f:write(serial(T))
    f:close()
end

do
    local f = io.open(FC .. "/genesis.lua")
    if not f then
        ERROR("chain " .. ARGS.alias .. " : not found")
    end
    f:close()
end

-- local time effects: advance discount + consolidation
do
    local stored = dofile(FC .. "/now.lua")

    if ARGS.sign~=nil or NOW.s>stored then
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

        write(NOW.s, FC .. "/now.lua")
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
    local kind = (ARGS.post and 'post') or 'like'
    local file

    local rand = math.random(0, 9999999999)

    local num = (ARGS.number or 0) * C.reps.unit
    if ARGS.dislike then
        num = -num
    end

    -- signing gate
    if ARGS.sign then
        G.authors[ARGS.sign] = G.authors[ARGS.sign] or { reps=0 }

        if G.authors[ARGS.sign].reps <= 0 then
            if not ARGS.beg then
                ERROR("chain post : insufficient reputation")
            end
        else
            if ARGS.beg then
                ERROR("chain post : --beg error : author has sufficient reputation")
            end
        end
    else
        if not ARGS.beg then
            ERROR("chain post : requires --sign or --beg")
        end
    end

    -- post payload
    if ARGS.post then
        if ARGS.inline then
            local text = ARGS.text .. (ARGS.text:match("\n$") and "" or "\n")
            file = ARGS.file or "post-" .. NOW.s .. "-" .. rand .. ".txt"
            local f = io.open(REPO.."/"..file, (ARGS.file and "a") or "w")
            f:write(text)
            f:close()
        else
            assert(ARGS.file)
            file = ARGS.path:match("[^/]+$")
            exec (
                "cp " .. ARGS.path .. " " .. REPO .. "/"
                , "chain post : copy failed: " .. ARGS.path
            )
        end

    -- like payload
    else
        assert(ARGS.like or ARGS.dislike)
        if ARGS.number <= 0 then
            ERROR("chain like : expected positive integer")
        end
        if ARGS.target ~= "post" and ARGS.target ~= "author" then
            ERROR("chain like : target must be 'post' or 'author'")
        end
        if ARGS.target == "post" then
            local tp = exec (true,
                "git -C " .. REPO .. " cat-file -t " .. ARGS.id
            )
            if tp ~= "commit" then
                ERROR("chain like : post not found : " .. ARGS.id)
            end
        end

        local payload = [[
            return {
                target = "]] .. ARGS.target .. [[",
                id     = "]] .. ARGS.id     .. [[",
                number = ]]  .. num         .. [[,
            }
        ]]
        file = ".freechains/likes/like-" .. NOW.s .. "-" .. rand .. ".lua"
        local f = io.open(REPO .. file, "w")
        f:write(payload)
        f:close()
    end

    -- monotonic timestamp validation
    do
        local date = tonumber((
            exec (
                "git -C " .. REPO .. " log -1 --format=%at"
            )
        ))
        assert(date, "bug found : date is not a number")
        if NOW.s < date - C.time.future then
            ERROR("chain " .. kind .. " : cannot be older than parent")
        end
    end

    -- metadata: post/like: reps
    do
        if kind == 'post' then
            if not ARGS.beg then
                G.authors[ARGS.sign].reps = G.authors[ARGS.sign].reps - C.reps.cost
                if G.authors[ARGS.sign].time == nil then
                    G.authors[ARGS.sign].time = NOW.s
                end
            end
        elseif kind == 'like' then
            G.authors[ARGS.sign].reps = G.authors[ARGS.sign].reps - math.abs(num)
            num = num * (100 - C.like.tax) // 100
            if ARGS.target == "post" then
                local a = exec (
                    "git -C " .. REPO .. " log -1 --format='%GK' " .. ARGS.id
                )
                G.authors[a] = G.authors[a] or { reps=0 }
                G.authors[a].reps = G.authors[a].reps + num // C.like.split
                G.posts[ARGS.id] = G.posts[ARGS.id] or { reps=0, author=a }
                G.posts[ARGS.id].reps = G.posts[ARGS.id].reps + num // C.like.split
                xps = true
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

        xas = true
    end

    -- detect if like targets a blocked beg
    local is_beg = (
        kind == 'like' and ARGS.target == "post" and
        G.posts[ARGS.id] and G.posts[ARGS.id].state == "blocked"
    )

    -- write state + commit
    do
        if is_beg then
            exec (
                "git -C " .. REPO .. " checkout " .. ARGS.id
            )
        end

        exec (
            "git -C " .. REPO .. " add " .. file
        )

        local s1, s2 = "", ""
        if ARGS.sign then
            s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=openpgp"
            s2 = " -S"
        end

        local msg = ARGS.why or ""
        exec (
            NOW.git .. "git -C " .. REPO .. s1 .. " commit" .. s2 ..
                " --trailer 'freechains: " .. kind .. "'" ..
                " --allow-empty-message" .. " -m '" .. msg .. "'"
        )

        local hash = exec (
            "git -C " .. REPO .. " rev-parse HEAD"
        )

        if is_beg then
            local ref = "refs/begs/beg-" .. ARGS.id
            exec (
                "git -C " .. REPO .. " update-ref " .. ref .. " " .. hash
            )
            exec (
                "git -C " .. REPO .. " checkout main"
            )
            exec (
                "git -C " .. REPO .. " merge --no-edit " .. ref
            )
            exec (
                "git -C " .. REPO .. " update-ref -d " .. ref
            )
            G.posts[ARGS.id].state = "00-12"
            G.posts[ARGS.id].time = NOW.s
            xps = true
        elseif ARGS.beg then
            exec (
                "git -C " .. REPO .. " update-ref refs/begs/beg-" .. hash .. " HEAD"
            )
            exec (
                "git -C " .. REPO .. " reset --hard HEAD~1"
            )
        end

        if kind == 'post' then
            G.posts[hash] = {
                author = ARGS.sign,
                time   = NOW.s,
                state  = (ARGS.beg and 'blocked') or '00-12',
                reps   = 0,
            }
            xps = true
        end

        print(hash)
    end
end

if xas then
    write(G.authors, FC .. "/authors.lua")
end
if xps then
    write(G.posts, FC .. "/posts.lua")
end
