local ssh = require "freechains.chain.ssh"

-- num
local num = ARGS.number * C.reps.unit
if ARGS.dislike then
    num = -num
end

if ARGS.target == "author" then
    if #ARGS.id~=80 or (not ARGS.id:match("^ssh%-ed25519 %S+$")) then
        ERROR("chain like : invalid author key")
    end
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
        "git -C " .. REPO .. " show " .. ref .. ":.freechains/state/posts.lua"
    )
    G.posts[ARGS.id] = load(src)()[ARGS.id]
end

-- commit like (content only, no state)
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
    local file = ".freechains/likes/like-" .. CMD.now .. "-" .. rand .. ".lua"
    local f = io.open(REPO .. file, "w")
    f:write(payload)
    f:close()
    exec (
        "git -C " .. REPO .. " add " .. file
    )
    local s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=ssh"
    local msg = ARGS.why or "(empty message)"
    exec ('stdout',
        CMD.git .. "git -C " .. REPO .. s1 .. " commit -S -m '" .. msg
        .. "' --trailer 'Freechains: like'"
        , "chain like : invalid sign key"
    )
    hash = exec (
        "git -C " .. REPO .. " rev-parse HEAD"
    )
end

-- apply
do
    local T = {
        sign   = ssh.pubkey(REPO, hash),
        num    = num,
        target = ARGS.target,
        id     = ARGS.id,
        beg    = to_beg,
    }
    local ok, err = apply(G, 'like', CMD.now, T)
    if not ok then
        exec("git -C " .. REPO .. " reset --hard HEAD~1")
        ERROR("chain like : " .. err)
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

if to_beg then
    exec("git -C " .. REPO .. " update-ref -d " .. ref)
end

print(hash)
