-- check sign
if not ARGS.sign then
    ERROR("chain like : requires --sign")
end

-- num
local num = ARGS.number * C.reps.unit
if ARGS.dislike then
    num = -num
end

-- detect if like targets a blocked beg on refs/begs/
local to_beg = (
    (ARGS.target == "post") and
        exec (true,
            "git -C " .. REPO .. " rev-parse --verify refs/begs/beg-" .. ARGS.id
        ) and true
)

-- beg: validate parent, merge into main, load beg entry
local ref = "refs/begs/beg-" .. ARGS.id
if to_beg then
    local up = exec (
        "git -C " .. REPO .. " log -1 --format=%P " .. ARGS.id
    )
    local _,ok = exec (true,
        "git -C " .. REPO .. " merge-base --is-ancestor " .. up .. " HEAD"
    )
    if ok ~= 0 then
        error("TODO : bug found : branch should not exist in the first place")
        --exec("git -C " .. REPO .. " update-ref -d " .. ref)
        --ERROR("chain like : invalid target : beg post does not exist")
    end
    exec("git -C " .. REPO .. " merge -X ours --no-commit --no-edit " .. ref)
    local src = exec(
        "git -C " .. REPO .. " show " .. ARGS.id .. ":.freechains/state/posts.lua"
    )
    G.posts[ARGS.id] = load(src)()["?"]
end

-- apply (no tmp ? hash, likes dont go to G.posts)
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
        ERROR("chain like : " .. err)
    end
end

-- payload + commit
local hash
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
    write(G)    -- write state
    exec (
        "git -C " .. REPO .. " add .freechains/state/ " .. file
    )
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

if to_beg then
    exec("git -C " .. REPO .. " update-ref -d " .. ref)
end

print(hash)
