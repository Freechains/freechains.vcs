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

-- metadata: apply immediate effects
if ARGS.post then
    apply(G, {
        kind = 'post',
        sign = ARGS.sign,
        beg  = ARGS.beg,
        time = NOW.s,
    })
else
    apply(G, {
        kind   = 'like',
        sign   = ARGS.sign,
        num    = num,
        target = ARGS.target,
        id     = ARGS.id,
    })
end

-- write state + commit
do
    -- detect if like targets a blocked beg
    local is_beg = (
        kind == 'like' and ARGS.target == "post" and
        G.posts[ARGS.id] and G.posts[ARGS.id].state == "blocked"
    )

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
        G.xps = true
    elseif ARGS.beg then
        exec (
            "git -C " .. REPO .. " update-ref refs/begs/beg-" .. hash .. " HEAD"
        )
        exec (
            "git -C " .. REPO .. " reset --hard HEAD~1"
        )
    end

    -- register post with actual commit hash
    if kind == 'post' then
        G.posts[hash] = {
            author = ARGS.sign,
            time   = NOW.s,
            state  = (ARGS.beg and 'blocked') or '00-12',
            reps   = 0,
        }
        G.xps = true
    end

    print(hash)
end
