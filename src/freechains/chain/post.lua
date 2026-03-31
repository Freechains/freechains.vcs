-- check sign/beg
do
    if ARGS.sign and ARGS.beg then
        local reps = G.authors[ARGS.sign] and G.authors[ARGS.sign].reps or 0
        if reps > 0 then
            ERROR (
                "chain post : --beg error : author has sufficient reputation"
            )
        end
    end
    if not (ARGS.sign or ARGS.beg) then
        ERROR("chain post : requires --sign or --beg")
    end
end

-- commit post (content only, no state)
local hash
do
    local file
    if ARGS.inline then
        local text = ARGS.text .. (ARGS.text:match("\n$") and "" or "\n")
        local rand = math.random(0, 9999999999)
        file = ARGS.file or "post-" .. CMD.now .. "-" .. rand .. ".txt"
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
    exec (
        "git -C " .. REPO .. " add " .. file
    )
    local s1, s2 = "", ""
    if ARGS.sign then
        s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=openpgp"
        s2 = " -S"
    end
    local msg = ARGS.why or "(empty message)"
    exec ('stdout',
        CMD.git .. "git -C " .. REPO .. s1 .. " commit" .. s2 .. " -m '" .. msg
        .. "' --trailer 'Freechains: post'"
        , "chain post : invalid sign key"
    )
    hash = exec (
        "git -C " .. REPO .. " rev-parse HEAD"
    )
end

-- apply with real hash
do
    local T = {
        hash = hash,
        sign = ARGS.sign,
        beg  = ARGS.beg,
    }
    local ok, err = apply(G, 'post', CMD.now, T)
    if not ok then
        exec("git -C " .. REPO .. " reset --hard HEAD~1")
        ERROR("chain post : " .. err)
    end
end

-- commit state
do
    write(G)
    exec (
        "git -C " .. REPO .. " add .freechains/state/"
    )
    exec (
        CMD.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
        .. " --trailer 'Freechains: state'"
    )
end

if ARGS.beg then
    exec (
        "git -C " .. REPO .. " update-ref refs/begs/beg-" .. hash .. " HEAD"
    )
    exec (
        "git -C " .. REPO .. " reset --hard HEAD~2"
    )
end

print(hash)
