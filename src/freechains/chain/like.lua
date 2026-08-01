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

-- the trailer + dir distinguish a revoke-axis vote from a like/dislike:
--   like/dislike -> .freechains/likes/   , 'Freechains: like'
--   revoke/unrev -> .freechains/revokes/ , 'Freechains: revoke'
local kind = (ARGS.revoke or ARGS.unrevoke) and "revoke" or "like"

-- gated unrevoke: a vote that would flip a currently-REVOKED post
-- back to ACCEPTED must not succeed unless the payload is still
-- available -- otherwise it promises visibility nobody can deliver
-- (260721-remove-blob.md, "Gated unrevoke"). Mirrors apply()'s own
-- author-vs-others channel pick (common.lua) to predict the outcome
-- without mutating G; a vote that doesn't actually restore (e.g. a
-- self-like while the author channel alone still forces REVOKED) is
-- never gated. A post hidden only via the community channel never
-- had its blob touched, so this only bites once `gc_revoked` has
-- actually removed it.
if ARGS.target == "post" and num>0 and G.posts[ARGS.id] and is_revoked(G.posts[ARGS.id]) then
    local post = G.posts[ARGS.id]
    local r = post.revoke or {}
    local a, o = r.author or 0, r.others or 0
    -- ARGS.sign is a private-key file PATH; post.author is a
    -- "ssh-ed25519 <pubkey>" STRING (see ssh.pubkey) -- derive the
    -- caster's own pubkey the same way chains.lua does before
    -- comparing, same shape as apply()'s check.
    local caster = ARGS.sign and ("ssh-ed25519 " .. (exec {
        cmd = "ssh-keygen -y -f " .. ARGS.sign,
    }):match("ssh%-ed25519 (%S+)"))
    if kind=='revoke' and post.author and caster==post.author then
        a = a + num
    else
        o = o + num
    end
    if not ((a<0) or (o<0)) then
        local file = exec {
            cmd = "git -C " .. REPO .. " diff-tree --no-commit-id -r --name-only " .. ARGS.id,
        } :match("(%S+)")
        local avail = file and exec { err=false,
            cmd = "git -C " .. REPO .. " cat-file -e " .. ARGS.id .. ":" .. file,
        }
        if not avail then
            ERROR("chain " .. (ARGS.unrevoke and "unrevoke" or "like") .. " : blob unavailable")
        end
    end
end

-- commit the vote (content only, no state)
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
    local msg = ARGS.why or "(empty message)"
    hash = commit_tree(msg, kind, ARGS.sign, "chain " .. kind .. " : invalid sign key")
end

-- apply
do
    local T = {
        [ARGS.target] = ARGS.id,
        hash = hash,
        sign = ssh.pubkey(REPO, hash),
        n    = num,
        beg  = to_beg,
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

if ARGS.target == "post" then
    gc_revoked(G, ARGS.id)
end

-- commit state
do
    write(G)
    exec {
        cmd = "git -C " .. REPO .. " add .freechains/state/",
    }
    commit_tree("(empty message)", "state", nil, nil)
end

if to_beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
    }
end

print(hash)
