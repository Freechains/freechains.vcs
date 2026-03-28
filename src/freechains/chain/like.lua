-- check sign
if not ARGS.sign then
    ERROR("chain like : requires --sign")
end

-- num
local num = ARGS.number * C.reps.unit
if ARGS.dislike then
    num = -num
end

-- detect if like targets a blocked beg
local to_beg = (
    ARGS.target == "post" and
    G.posts[ARGS.id] and G.posts[ARGS.id].state == "blocked"
)

-- payload
do
    local payload = [[
        return {
            target = "]] .. ARGS.target .. [[",
            id     = "]] .. ARGS.id     .. [[",
            number = ]]  .. num         .. [[,
        }
    ]]
    local rand = math.random(0, 9999999999)
    local file = ".freechains/likes/like-" .. NOW.s .. "-" .. rand .. ".lua"
    local f = io.open(REPO .. file, "w")
    f:write(payload)
    f:close()

    exec (
        "git -C " .. REPO .. " add .freechains/state/ " .. file
    )
end

-- commit
local hash
do
    if to_beg then
        exec (
            "git -C " .. REPO .. " checkout " .. ARGS.id
        )
    end
    local s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=openpgp"
    local msg = ARGS.why or "(empty message)"
    exec (
        NOW.git .. "git -C " .. REPO .. s1 .. " commit -S -m '" .. msg
        .. "' --trailer 'Freechains: like'"
    )
    hash = exec (
        "git -C " .. REPO .. " rev-parse HEAD"
    )
end

-- apply
do
    local T = {
        sign   = ARGS.sign,
        num    = num,
        target = ARGS.target,
        id     = ARGS.id,
        beg    = to_beg,
    }
    local ok, err = apply(G, 'like', NOW.s, T)
    if not ok then
        exec("git -C " .. REPO .. " reset --hard HEAD~1")
        write(G.now,     FC .. "state/now.lua")
        write(G.authors, FC .. "state/authors.lua")
        write(G.posts,   FC .. "state/posts.lua")
        ERROR("chain like : " .. err)
    end
end

if to_beg then
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
end

print(hash)
