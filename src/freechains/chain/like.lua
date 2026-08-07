-- TODO : review : like flow

local ssh = require "freechains.chain.ssh"

-- revoke/unrevoke are content-removal votes: post target only,
-- so they carry no `target` argument (default it here)
if ARGS.revoke or ARGS.unrevoke then
    ARGS.target = "post"
end

ARGS.aid = ARGS.aid:match("^%s*(.-)%s*$")

-- num: dislike and revoke remove reps; like and unrevoke add reps
local num = ARGS.number * C.reps.unit
if ARGS.dislike or ARGS.revoke then
    num = -num
end

if ARGS.target == "author" then
    if #ARGS.aid~=80 or (not ARGS.aid:match("^ssh%-ed25519 %S+$")) then
        ERROR("chain like : invalid author key")
    end
end

-- the action file's `action` distinguishes a revoke-axis vote
-- from a like/dislike
local kind = (ARGS.revoke or ARGS.unrevoke) and "revoke" or "like"

local pub = ssh.pub.key(ARGS.sign)
if not pub then
    ERROR("chain " .. kind .. " : invalid sign key")
end

-- detect if a positive `like` targets a beg on refs/begs/
-- (only `like` accepts begs; dislike/revoke/unrevoke do not)
local to_beg = (
    ARGS.like and (ARGS.target == "post") and
        exec { err=false,
            cmd = "git -C " .. REPO .. " rev-parse --verify refs/begs/beg-" .. ARGS.aid,
        } and true
)

-- beg: validate parent, load beg entry (the merge waits for `apply`)
local ref = "refs/begs/beg-" .. ARGS.aid
if to_beg then
    -- a fetched beg was never replayed, so the index may not
    -- know it -- but its ref NAMES the aid
    DB.add(ARGS.aid, ref)
    -- the beg branch is one joined commit: ref~1 is its base
    local up = exec {
        cmd = "git -C " .. REPO .. " rev-parse " .. ref .. "~1",
    }
    local _,ok = exec { err=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " .. up .. " HEAD",
    }
    if ok ~= 0 then
        error("TODO : bug found : branch should not exist in the first place")
        --exec("git -C " .. REPO .. " update-ref -d " .. ref)
        --ERROR("chain like : invalid target : beg post does not exist")
    end
    G.order[#G.order+1] = ARGS.aid
    -- TODO : redesign : review
    -- S15.1d: the beg SELF-DESCRIBES; no beg-state read. Entry
    -- shape mirrors apply's beg post; peak = S16 fold over its
    -- backs (all in my history: ref~1 is an ancestor of HEAD)
    local A = READ(exec {
        cmd = "git -C " .. REPO .. " show " .. ref ..
            ":.freechains/actions/" .. ARGS.aid .. ".lua",
    })
    -- S8.4: a fetched beg bypassed the receive gate -- check
    -- its file against its commit before trusting it. (Every
    -- peer re-checks when the merge reaches them; an invalid
    -- beg would only get MY merge rejected.) `backs` is
    -- enforced there too, so it is not re-checked here.
    do
        local bid = exec {
            cmd = "git -C " .. REPO .. " rev-parse " .. ref,
        }
        local sha = (exec {
            cmd = "git -C " .. REPO .. " ls-tree " .. bid ..
                " -- .freechains/actions/" .. ARGS.aid .. ".lua",
        }):match("blob (%x+)")
        local bkey = ssh.verify(REPO, bid)
        local btime = tonumber((exec {
            cmd = "git -C " .. REPO .. " log -1 --format=%at " .. bid,
        }))
        if sha ~= ARGS.aid or A.sign ~= bkey or A.time ~= btime then
            ERROR("chain " .. kind .. " : invalid beg")
        end
    end
    G.posts[ARGS.aid] = {
        author   = A.sign,
        time     = A.time,
        maturity = 'beg',
        reps     = 0,
        revoke   = { author=0, others=0 },
    }
    local up = assert(G.gen, "bug found : no gen")
    for _, b in ipairs(A.backs) do
        local p = assert(G.peaks[b], "bug found : no peak")
        up = math.max(up, p)
    end
    G.peaks[ARGS.aid] = math.max(A.time, up)
end

-- TODO : redesign : review
local bs = to_beg and BACKS { "HEAD", ref } or BACKS { "HEAD" }

local aid = ACTION.pre {
    action = kind,
    backs  = bs,
    sign   = pub,
    time   = CMD.now,
    n      = num,
    -- action ID for posts; pubkey as is for authors
    [ARGS.target] = ARGS.aid,
}

-- apply BEFORE the commit: failure leaves the repo untouched
do
    local T = {
        [ARGS.target] = ARGS.aid,
        aid     = aid,
        -- TODO : DONE : S16 : peak folds over T.backs, no git
        backs   = bs,
        sign    = pub,
        n       = num,
        beg     = to_beg,
    }
    local ok, err = apply(G, kind, CMD.now, T)
    if not ok then
        ERROR("chain " .. kind .. " : " .. err)
    end
    G.order[#G.order+1] = aid
end

-- one commit: (beg merge +) action file + state
do
    if to_beg then
        exec {
            cmd = "git -C " .. REPO .. " merge -X ours --no-ff --no-commit --no-edit " .. ref,
        }
    end
    ACTION.pos(aid)
    -- TODO : DONE : S15.2 : state no longer enters the tree
    local s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=ssh"
    local msg = ARGS.why or "(empty message)"
    exec { stderr=false,
        cmd = CMD.git .. "git -C " .. REPO .. s1 .. " commit -S -m '" .. msg .. "'",
        err = "chain " .. kind .. " : invalid sign key",
    }
    DB.add(aid, "HEAD", true)
    DB.snap("HEAD", G)
end

if to_beg then
    exec {
        cmd = "git -C " .. REPO .. " update-ref -d " .. ref,
    }
end

print(aid)
