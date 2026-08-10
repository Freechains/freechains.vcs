local ssh = require "freechains.chain.ssh"

-- revoke/unrevoke are content-removal votes: post target only,
-- so they carry no `target` argument (default it here)
if ARGS.revoke or ARGS.unrevoke then
    ARGS.target = "post"
end

ARGS.id = ARGS.id:match("^%s*(.-)%s*$")

-- a post target may be abbreviated (`list dag` prints it so); an
-- author target is a pubkey and passes through untouched
if ARGS.target == "post" then
    ARGS.id = ACTION.full(ARGS.id)
end

-- num: dislike and revoke remove reps; like and unrevoke add reps
local num = ARGS.number
if ARGS.dislike or ARGS.revoke then
    num = -num
end

-- the action file + vote dir distinguish a revoke-axis vote
-- from a like/dislike (see the commit block below)
local kind = (ARGS.revoke or ARGS.unrevoke) and "revoke" or "like"

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
-- (the ref is named by the beg's aid)
local ref = "refs/begs/beg-" .. ARGS.id
if to_beg then
    local up = exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%P " .. ref,
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
        cmd = "git -C " .. REPO .. " merge --no-ff --no-commit --no-edit " .. ref,
    }
    G.order[#G.order+1] = ARGS.id   -- beg post
    G.posts[ARGS.id] = STATE.read(true, ref).posts[ARGS.id]
end

-- the writer's own pubkey, read from the `.pub` file BEFORE the
-- commit: a bad key fails early, nothing enters the tree
local pub = ssh.pub.key(ARGS.sign)
if not pub then
    ERROR("chain " .. kind .. " : invalid sign key")
end

-- the vote IS its action file: nothing else enters the commit.
-- `--why` is its OPTIONAL payload: a loose blob outside the
-- tree, deletable like any payload
local path = REPO .. ".git/payload-tmp"   -- why staging file

local blob
if ARGS.why then
    local f = io.open(path, "w")
    f:write(ARGS.why)
    f:close()
    -- DRY hash: nothing enters the object db before `apply`
    blob = exec {
        cmd = "git -C " .. REPO .. " hash-object " .. path,
    }
end

-- the parents of the commit about to be created: `backs` walks
-- them and `apply` folds its time peak over them
local ps = to_beg and { "HEAD", ref } or { "HEAD" }

-- action file: self-description; minted BEFORE the commit;
-- a beg like backs both sides of its merge.
-- ARGS.id is already the aid (or a pubkey): stored as is
local act = {
    action = kind,
    backs  = ACTION.backs(ps),
    sign   = pub,
    time   = tonumber(CMD.now),
    blob   = blob,
    [ARGS.target] = ARGS.id,
    n      = num,
}
local aid = ACTION.pre(act)

-- apply BEFORE the commit: a rejected vote leaves nothing;
-- an in-progress beg merge is aborted
do
    local ok, err = apply(G, kind, CMD.now, act, {
        aid     = aid,
        sign    = pub,
        parents = ps,
        beg     = to_beg,
    })
    if not ok then
        if to_beg then
            exec {
                cmd = "git -C " .. REPO .. " merge --abort",
            }
        end
        ERROR("chain " .. kind .. " : " .. err)
    end
    G.order[#G.order+1] = aid
end

ACTION.pos(aid)

-- the why enters the object db anchored at its final name
if blob then
    exec {
        cmd = "git -C " .. REPO .. " hash-object -w " .. path,
    }
    exec {
        cmd = "git -C " .. REPO .. " update-ref refs/payloads/" .. aid .. " " .. blob,
    }
    os.remove(path)
end

do
    local s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=ssh"
    exec { stderr=false,
        cmd = CMD.git .. "git -C " .. REPO .. s1 .. " commit -S --allow-empty-message -m ''",
        err = "chain " .. kind .. " : invalid sign key",
    }
end

-- snapshot state at the new tip (the action commit itself)
STATE.write(G, true, "HEAD")

if to_beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
    }
end

print(aid)
