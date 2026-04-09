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

-- detect if like targets an ident on refs/idents/
local to_ident = (
    (ARGS.target == "author") and
        exec (true,
            "git -C " .. REPO .. " rev-parse --verify refs/idents/ident-" .. ARGS.id
        ) and true
)

-- ident: merge ident branch into main
local ref_ident = "refs/idents/ident-" .. ARGS.id
if to_ident then
    exec("git -C " .. REPO .. " merge -X ours --no-commit --no-edit " .. ref_ident)
end

-- beg: validate parent, merge into main, load beg entry
local ref_beg = "refs/begs/beg-" .. ARGS.id
if to_beg then
    local up = exec (
        "git -C " .. REPO .. " log -1 --format=%P " .. ARGS.id
    )
    local _,ok = exec (true,
        "git -C " .. REPO .. " merge-base --is-ancestor " .. up .. " HEAD"
    )
    assert(ok==0, "bug found : branch should not exist in the first place")
    exec("git -C " .. REPO .. " merge -X ours --no-commit --no-edit " .. ref_beg)
    local src = exec (
        "git -C " .. REPO .. " show " .. ref_beg .. ":.freechains/state/posts.lua"
    )
    G.posts[ARGS.id] = load(src)()[ARGS.id]
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
    local ok, err = apply(G, 'like', CMD.now, T)
    if not ok then
        ERROR("chain like : " .. err)
    end
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
    local s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=openpgp"
    local msg = ARGS.why or "(empty message)"
    exec (
        CMD.git .. "git -C " .. REPO .. s1 .. " commit -S -m '" .. msg
        .. "' --trailer 'Freechains: like'"
    )
    hash = exec (
        "git -C " .. REPO .. " rev-parse HEAD"
    )
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
    exec("git -C " .. REPO .. " update-ref -d " .. ref_beg)
end

if to_ident then
    exec("git -C " .. REPO .. " update-ref -d " .. ref_ident)
end

print(hash)
