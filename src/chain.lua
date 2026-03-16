local C = require "constants"

local REPO = ARGS.root .. "/chains/" .. ARGS.alias .. "/"

local function write (T, file)
    local f = io.open(file, "w")
    f:write(serial(T))
    f:close()
end

-- stage: advance time effects
local fc_reps_authors, fc_time_posts, fc_time_authors
do
    local L = REPO .. ".freechains/local/"
    local stored = dofile(L .. "now.lua")

    fc_reps_authors = dofile(REPO .. "/.freechains/reps/authors.lua")
    fc_time_posts   = dofile(REPO .. "/.freechains/time/posts.lua")
    fc_time_authors = dofile(REPO .. "/.freechains/time/authors.lua")

    if ARGS.sign ~= nil or NOW.s > stored then
        -- discount scan
        for i, entry in ipairs(fc_time_posts) do
            if entry.state == "00-12" then
                local subs = {}
                for j, other in ipairs(fc_time_posts) do
                    if j > i then
                        subs[other.author] = true
                    end
                end
                if ARGS.sign then
                    subs[ARGS.sign] = true
                end

                local cur = 0
                for a in pairs(subs) do
                    cur = cur + math.max(0, fc_reps_authors[a] or 0)
                end
                local tot = 0
                for _, v in pairs(fc_reps_authors) do
                    tot = tot + math.max(0, v)
                end

                local ratio = (tot>0 and cur/tot) or 0
                local discount = C.time.half * math.max(0, 1 - 2*ratio)

                if NOW.s >= entry.time + discount then
                    fc_reps_authors[entry.author] = (fc_reps_authors[entry.author] or 0) + C.reps.cost
                    entry.state = "12-24"
                end
            end
        end

        -- consolidation scan
        for _, entry in ipairs(fc_time_posts) do
            if entry.state == "12-24" then
                if NOW.s >= entry.time + C.time.full then
                    local last = fc_time_authors[entry.author]
                    if NOW.s - last >= C.time.full then
                        fc_reps_authors[entry.author] = (fc_reps_authors[entry.author] or 0) + C.reps.cost
                        fc_time_authors[entry.author] = last + C.time.full
                        entry._remove = true
                    end
                end
            end
        end

        -- remove consolidated entries
        local survivors = {}
        for _, entry in ipairs(fc_time_posts) do
            if not entry._remove then
                survivors[#survivors+1] = entry
            end
        end
        fc_time_posts = survivors

        -- cap all authors at max (for query paths)
        if ARGS.sign == nil then
            for k, v in pairs(fc_reps_authors) do
                if v > C.reps.max then
                    fc_reps_authors[k] = C.reps.max
                end
            end
        end

        write(fc_reps_authors, REPO .. "/.freechains/reps/authors.lua")
        write(fc_time_posts,   REPO .. "/.freechains/time/posts.lua")
        write(fc_time_authors, REPO .. "/.freechains/time/authors.lua")
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
        local posts = dofile(REPO .. ".freechains/reps/posts.lua")
        local v = posts[ARGS.key] or 0
        print(ext(v))
    elseif ARGS.target == "author" then
        if not ARGS.key then
            ERROR("chain reps : author requires a pubkey")
        end
        local v = fc_reps_authors[ARGS.key] or 0
        print(ext(v))
    elseif ARGS.target == "authors" then
        local T = {}
        for k, v in pairs(fc_reps_authors) do
            T[#T+1] = { k=k, v=v }
        end
        table.sort(T, function (a, b) return a.v > b.v end)
        for _, e in ipairs(T) do
            print(e.k .. " " .. ext(e.v))
        end
    else
        ERROR("chain reps : invalid target : " .. ARGS.target)
    end
elseif ARGS.post or ARGS.like or ARGS.dislike then
    local kind, files

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
                local hash = exec (true,
                    "printf '%s' '" .. text .. "' | git hash-object --stdin"
                )
                files = "post-" .. NOW.s .. "-" .. hash:sub(1,8) .. ".txt"
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
        local blob = exec (true,
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
        files = files .. " .freechains/reps/authors.lua"

        if kind == "post" then
            if ARGS.sign then
                fc_reps_authors[ARGS.sign] = (fc_reps_authors[ARGS.sign] or 0) - C.reps.cost
                fc_time_posts[#fc_time_posts+1] = {
                    author = ARGS.sign,
                    time   = NOW.s,
                    state  = "00-12",
                }
                if fc_time_authors[ARGS.sign] == nil then
                    fc_time_authors[ARGS.sign] = NOW.s
                end
            end

        elseif kind == "like" then
            local posts = dofile(REPO .. "/.freechains/reps/posts.lua")
            files = files .. " .freechains/reps/posts.lua"

            local num = ARGS.number * C.reps.unit
            fc_reps_authors[ARGS.sign] = (fc_reps_authors[ARGS.sign] or 0) - num

            if ARGS.dislike then
                num = -num
            end

            num = num * (100 - C.like.tax) // 100     -- apply tax

            if ARGS.target == "post" then
                local a = exec (true,
                    "git -C " .. REPO .. " log -1 --format='%GK' " .. ARGS.id
                )
                fc_reps_authors[a] = (fc_reps_authors[a] or 0) + num // C.like.split
                posts[ARGS.id] = (posts[ARGS.id] or 0) + num // C.like.split
                write(posts, REPO.."/.freechains/reps/posts.lua")
            else
                fc_reps_authors[ARGS.id] = (fc_reps_authors[ARGS.id] or 0) + num
            end
        end

        -- cap all authors at max
        for k, v in pairs(fc_reps_authors) do
            if v > C.reps.max then
                fc_reps_authors[k] = C.reps.max
            end
        end

        write(fc_reps_authors, REPO.."/.freechains/reps/authors.lua")
        write(fc_time_posts,   REPO.."/.freechains/time/posts.lua")
        write(fc_time_authors, REPO.."/.freechains/time/authors.lua")
        files = files .. " .freechains/time/posts.lua .freechains/time/authors.lua"
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
