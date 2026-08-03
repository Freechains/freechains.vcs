local ssh = require "freechains.chain.ssh"

-- revoke/unrevoke are content-removal votes: post target only,
-- so they carry no `target` argument (default it here)
if ARGS.revoke or ARGS.unrevoke then
    ARGS.target = "post"
end

ARGS.id = ARGS.id:match("^%s*(.-)%s*$")

-- num: dislike and revoke remove reps; like and unrevoke add reps
local num = ARGS.number * C.reps.unit
if ARGS.dislike or ARGS.revoke then
    num = -num
end

if ARGS.target == "author" then
    if #ARGS.id~=80 or (not ARGS.id:match("^ssh%-ed25519 %S+$")) then
        ERROR("chain like : invalid author key")
    end
end

-- detect if a positive `like` targets a beg on refs/begs/
-- (only `like` accepts begs; dislike/revoke/unrevoke do not)
local to_beg = (
    ARGS.like and (ARGS.target == "post") and
        exec { err=false,
            cmd = "git -C " .. REPO .. " rev-parse --verify refs/begs/beg-" .. ARGS.id,
        } and true
)

-- beg: validate parent, merge into main, load beg entry
local ref = "refs/begs/beg-" .. ARGS.id
if to_beg then
    local up = exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%P " .. ARGS.id,
    }
    local _,ok = exec { err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. up .. " HEAD",
    }
    if ok ~= 0 then
        error("TODO : bug found : branch should not exist in the first place")
        --exec("git -C " .. REPO .. " update-ref -d " .. ref)
        --ERROR("chain like : invalid target : beg post does not exist")
    end
    exec {
        cmd = "git -C " .. REPO .. " merge -X ours --no-ff --no-commit --no-edit " .. ref,
    }
    G.order[#G.order+1] = exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. ref .. "~1",   -- beg post
    }
    local src = exec {
        cmd = "git -C " .. REPO .. " show " .. ref .. ":.freechains/state/posts.lua",
    }
    G.posts[ARGS.id] = load(src)()[ARGS.id]
end

-- commit the vote (content only, no state). The trailer + dir
-- distinguish a revoke-axis vote from a like/dislike:
--   like/dislike -> .freechains/likes/   , 'Freechains: like'
--   revoke/unrev -> .freechains/revokes/ , 'Freechains: revoke'
local kind = (ARGS.revoke or ARGS.unrevoke) and "revoke" or "like"

local pub = ssh.pub.key(ARGS.sign)
if not pub then
    ERROR("chain " .. kind .. " : invalid sign key")
end

local hash
do
    local payload = [[
        return {
            ]] .. ARGS.target .. [[ = "]] .. ARGS.id .. [[",
            n      = ]] .. num .. [[,
        }
    ]]
    local rand = math.random(0, 9999999999)
    local file = ".freechains/" .. kind .. "s/" .. kind .. "-" .. CMD.now .. "-" .. rand .. ".lua"
    local f = io.open(REPO .. file, "w")
    f:write(payload)
    f:close()
    exec {
        cmd = "git -C " .. REPO .. " add " .. file,
    }
    local s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=ssh"
    local msg = ARGS.why or "(empty message)"
    exec { stderr=false,
        cmd = CMD.git .. "git -C " .. REPO .. s1 .. " commit -S -m '" .. msg ..
                  "' --trailer 'Freechains: " .. kind .. "'",
        err = "chain " .. kind .. " : invalid sign key",
    }
    hash = exec {
        cmd = "git -C " .. REPO .. " rev-parse HEAD",
    }
end

-- apply
do
    local T = {
        [ARGS.target] = ARGS.id,
        hash    = hash,
        parents = parents(hash),
        sign    = pub,
        n       = num,
        beg     = to_beg,
    }
    local ok, err = apply(G, kind, CMD.now, T)
    if not ok then
        exec {
            cmd = "git -C " .. REPO .. " reset --hard HEAD~1",
        }
        ERROR("chain " .. kind .. " : " .. err)
    end
    G.order[#G.order+1] = hash
end

-- commit state
do
    write(G)
    exec {
        cmd = "git -C " .. REPO .. " add .freechains/state/",
    }
    exec {
        cmd = CMD.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
        .. " --trailer 'Freechains: state'",
    }
end

if to_beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
    }
end

print(hash)
