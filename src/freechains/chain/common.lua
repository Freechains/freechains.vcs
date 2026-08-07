C    = require "freechains.constants"
REPO = ARGS.root .. "/chains/" .. ARGS.alias .. "/"
FC   = REPO .. ".freechains/"
DB   = require "freechains.chain.db"

-- the git parents of `cid`: one step back in the DAG, no time
-- involved. Returns an array (empty for a root).
function parents (cid)
    local out = exec {
        cmd = "git -C " .. REPO .. " rev-list --parents -1 " .. cid,
        -- $ git rev-list --parents -1 a1b2c3...
        -- a1b2c3... d4e5f6... 7890ab...  # merge: 2 parents
    }
    local ps = {}
    for h in out:gmatch("%x+") do
        ps[#ps+1] = h
    end
    table.remove(ps, 1)
    return ps
end

-- TODO : change : par.7/S8.4 : write-path caller (BACKS) moves
-- to the DB frontier; the recursion itself STAYS as the receive
-- validator (par.6 two-DAG check: recompute true ancestors from
-- git, reject a file whose `backs` lie)
-- action ancestors of `cid`: `parents` recursed through merges,
-- which are plumbing the protocol does not expose. Returns an
-- array of hashes (dedup'd).
function backs (cid)
    local ret = {}
    local see = {}
    local function rec (h)
        for _, p in ipairs(parents(h)) do
            if DB.aid(p) then
                if not see[p] then
                    see[p] = true
                    ret[#ret+1] = p
                end
            elseif #parents(p) ~= 1 then
                rec(p)      -- merge (>=2 parents) or genesis (0: stops)
            else
                error("bug found : action-less 1-parent commit")
            end
        end
    end
    rec(cid)
    return ret
end

-- TODO : remove : S11b : commit<->ID index replaces this lookup
-- TODO : change : par.7 : backs come from the DB, not git walks
-- the action IDs backing a new action built on top of `tips`
-- (resolved to hashes for the index): action ancestors via
-- `backs`, as sorted IDs.
-- A tip that IS an action commit (joined, S9) backs itself.
function BACKS (tips)
    local T = {}
    for _, tip in ipairs(tips) do
        -- TODO : redesign : review
        tip = exec {
            cmd = "git -C " .. REPO .. " rev-parse " .. tip,
        }
        local aid = DB.aid(tip)
        if aid then
            T[#T+1] = aid
        else
            for _, h in ipairs(backs(tip)) do
                T[#T+1] = assert(DB.aid(h))
            end
        end
    end
    table.sort(T)
    return T
end

-- TODO : change : S6a : shard into actions/ab/; S10 : add `blob`
-- (blob DONE early at S8.2b for posts: identity needs content;
--  S10 keeps only the ref-anchoring/eviction part)
-- pre/pos bracket `apply`: `pre` builds the action file in
-- `.git/` scratch and returns its aid (the content's own blob
-- hash; `backs` inside `T` must already hold aids); `pos` runs
-- only after `apply` succeeds, so a failure leaves the repo
-- untouched.
ACTION = {
    -- pre + pos in one step, for callers with no `apply` in between
    all = function (T)
        return ACTION.pos(ACTION.pre(T))
    end,

    pre = function (T)
        local tmp = REPO .. ".git/action.lua"
        local f = io.open(tmp, "w")
        f:write(serial(T))
        f:close()
        return exec {
            cmd = "git -C " .. REPO .. " hash-object " .. tmp,
        }
    end,

    -- move the scratch action file into the tree and stage it;
    -- the filename IS the aid returned by `pre`
    pos = function (aid)
        local file = ".freechains/actions/" .. aid .. ".lua"
        exec {
            cmd = "mkdir -p " .. REPO .. ".freechains/actions/",
        }
        os.rename(REPO .. ".git/action.lua", REPO .. file)
        exec {
            cmd = "git -C " .. REPO .. " add " .. file,
        }
        return aid
    end,
}

-- .freechains/state.lua -- the whole derived state, one table.
-- Always `serial` output (sorted keys), byte-comparable by verifiers:
--
--  return {
--      authors = {                             -- one entry per signer
--          ["ssh-ed25519 AAAA..."] = {
--              reps = 13,                      -- current reputation
--              time = 1785000000,              -- last consolidation
--          },
--      },
--      posts = {                               -- one entry per post
--          ["a1b2c3..."] = {                   -- action ID
--              author   = "ssh-ed25519 AAAA...",   -- nil: unsigned beg
--              time     = 1785000000,          -- nil: consolidated
--              maturity = "00-12",             -- beg|00-12|12-24|nil
--              reps     = 0,                   -- received likes
--              revoke   = { author=0, others=0 },  -- net revoke sums
--          },
--      },
--      order = {                               -- consensus order
--          "a1b2c3...",                        -- action ID
--      },
--      now = 1785000000,   -- newest time among ancestors (high-water)
--  }

-- parse a state.lua source: DATA ONLY (empty env, no globals to
-- attacker Lua), and it must yield a table
function READ (src)
    local T = assert(load(src, nil, "t", {}))()
    assert(type(T) == 'table')
    return T
end

function WRITE (G)
    local f = io.open(FC .. "state.lua", "w")
    f:write(serial {
        authors = G.authors,
        posts   = G.posts,
        order   = G.order,
        now     = G.now,
    })
    f:close()
end

-- REVOKED when either the author's or the community's net revoke sum is negative.
function is_revoked (p)
    local r = p.revoke or {}
    return ((r.author or 0) < 0) or ((r.others or 0) < 0)
end

-- posts aids in a stable order: (time, aid); consolidated posts
-- (time == nil) sort last, then lexicographically by aid. Makes the
-- discount/consolidation scans deterministic across OS processes.
local function ordered (posts)
    local hs = {}
    for h in pairs(posts) do
        hs[#hs+1] = h
    end
    table.sort(hs, function (a, b)
        local ta = posts[a].time or math.huge
        local tb = posts[b].time or math.huge
        if ta == tb then
            return a < b
        else
            return ta < tb
        end
    end)
    return hs
end

-- a commit's OWN author date, which says nothing about its ancestors:
-- a post carries the state file of the commit BEFORE it, so its own
-- stamp lives nowhere else.
local function TIME (cid)
    return assert(tonumber((exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%at " .. cid,
    })))
end

-- TODO : remove : par.7 : peak folds over `backs` in the DB
-- the peak RECORDED in a commit's tree (`state.lua` .now): the newest
-- time among all of its ancestors. Derived, never trusted: `commit` in
-- sync.lua checks every stored value against its parents' before using
-- it. Only `state` commits are current -- a post/like may just ADD
-- files, so its tree still holds the previous state commit's value.
function PEAK (cid)
    local src = exec {
        cmd = "git -C " .. REPO .. " show " .. cid .. ":.freechains/state.lua",
    }
    return READ(src).now
end

-- the peak COMPUTED over a set of commits: the peak each one recorded,
-- or its own time if newer (a post's tree still holds the PREVIOUS
-- peak, so its stamp lives nowhere else). The only place the fold
-- happens: `PEAKS(parents(h))` is the newest time causally preceding
-- `h`, the value a state commit must record, so writer and verifier
-- share the formula. Asserts on an empty set: only a root has no
-- parents, and no path takes a root this far.
function PEAKS (hs)
    local mx = nil
    for _, h in ipairs(hs) do
        local t = math.max(TIME(h), PEAK(h))
        mx = math.max(mx or t, t)
    end
    return assert(mx)
end

-- TODO : review : see all callers
-- the `now` an honest commit must record. A joined action commit
-- (S9) writes max(state before, own stamp), where "state before"
-- is its first parent's tree (a merge keeps 'ours'). A merge
-- folds its parents (PEAKS), as before. Writer and verifier
-- share the formula.
function NOW (cid)
    if DB.aid(cid) then
        local ps = parents(cid)
        return math.max(TIME(cid), PEAK(ps[1]))
    end
    return PEAKS(parents(cid))
end

function apply (G, kind, time, T)
    local mutate = (kind ~= 'reps')

    -- TIME: monotonicity, discount, consolidation
    do
        -- causal freshness: a commit may sit at most `time.diff` below
        -- everything that precedes it. Read from the DAG, so it does not
        -- depend on the order a replay applies commits in (consensus order
        -- is not chronological order).
        if mutate then
            -- TODO : change : par.7 : T.backs (action IDs), not commits
            local up = PEAKS(T.parents)
            if time < up-C.time.diff then
                return false, "too old"
            end
        end

        -- discount scan (maybe signed at same G.now)
        local sign = (mutate and T.sign) or nil
        if time>G.now or sign then
            for _, aid in ipairs(ordered(G.posts)) do
                local entry = G.posts[aid]
                if entry.maturity == "00-12" then
                    local subs = {}
                    for h2, other in pairs(G.posts) do
                        if other.author and other.time and other.time>entry.time then
                            subs[other.author] = true
                        end
                    end
                    if sign then
                        subs[sign] = true
                    end

                    local cur = 0
                    for a in pairs(subs) do
                        cur = cur + math.max(0, (G.authors[a] and G.authors[a].reps) or 0)
                    end
                    local tot = 0
                    for _, v in pairs(G.authors) do
                        tot = tot + math.max(0, v.reps)
                    end

                    local ratio = (tot>0 and cur/tot) or 0
                    local discount = C.time.half * math.max(0, 1 - 2*ratio)

                    if time >= entry.time + discount then
                        -- signed beg?
                        if entry.author then
                            G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                        end
                        entry.maturity = "12-24"
                    end
                end
            end
        end

        -- consolidation scan
        if time > G.now then
            for _, aid in ipairs(ordered(G.posts)) do
                local entry = G.posts[aid]
                if entry.maturity == "12-24" then
                    if time >= entry.time+C.time.full then
                        if entry.author then
                            local last = G.authors[entry.author].time
                            if time-last >= C.time.full then
                                G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.cost
                                G.authors[entry.author].time = last + C.time.full
                                entry.maturity = nil
                                entry.time  = nil
                            end
                        else
                            -- authorless (unsigned beg): consolidate, no credit
                            entry.maturity = nil
                            entry.time  = nil
                        end
                    end
                end
            end
        end

        if time > G.now then
            G.now = time
        end
    end

    if mutate then
        if kind == 'post' then
            -- validation
            assert(T.sign or T.beg)
            if T.sign then
                if T.beg then
                    local reps = G.authors[T.sign] and G.authors[T.sign].reps or 0
                    if reps > 0 then
                        return false, "--beg error : author has sufficient reputation"
                    end
                else
                    local reps = G.authors[T.sign] and G.authors[T.sign].reps or 0
                    if reps <= 0 then
                        return false, "insufficient reputation"
                    end
                end
            end

            -- mutation
            G.posts[T.aid] = {
                author   = T.sign,
                time     = time,
                maturity = (T.beg and 'beg') or (T.sign and '00-12') or 'beg',
                reps     = 0,
                revoke   = { author=0, others=0 },
            }
            if T.sign then
                G.authors[T.sign] = G.authors[T.sign] or { reps=0 }
                if not T.beg then
                    G.authors[T.sign].reps = G.authors[T.sign].reps - C.reps.cost
                    G.authors[T.sign].time = G.authors[T.sign].time or time
                        -- do not set for beg, bc not available to others
                end
            end

        elseif kind=='like' or kind=='revoke' then
            -- validation
            assert(T.sign, "bug found")
            if math.type(T.n)~='integer' or T.n==0 then
                return false, "invalid number : expects non-zero integer"
            end
            if (T.post and T.author) or (not T.post and not T.author) then
                return false, "invalid target : expects 'post' or 'author'"
            end
            -- revoke/unrevoke are post-only
            if kind=='revoke' and (not T.post) then
                return false, "invalid target : expects 'post'"
            end
            if T.post and (not G.posts[T.post]) then
                return false, "invalid target : post not found"
            end

            -- author self-revoke (right to be forgotten) is free and ungated
            local self_revoke = (
                kind=='revoke' and T.n<0 and G.posts[T.post].author==T.sign
            )

            -- must afford the full vote magnitude (no debt); self-revoke is free
            local reps = (G.authors[T.sign] and G.authors[T.sign].reps) or 0
            if (not self_revoke) and reps<math.abs(T.n) then
                return false, "insufficient reputation"
            end

            -- mutation
            if not self_revoke then
                G.authors[T.sign].reps = reps - math.abs(T.n)
            end
            local n = T.n * (100 - C.like.tax) // 100
            if T.post then
                local a = G.posts[T.post].author
                if not (self_revoke or (kind=='revoke' and T.n>0)) then
                    if a then
                        G.authors[a] = G.authors[a] or { reps=0 }
                        G.authors[a].reps = G.authors[a].reps + n//C.like.split
                    else
                        assert(T.beg)
                    end
                    G.posts[T.post].reps = G.posts[T.post].reps + n//C.like.split
                end

                -- revoke axis: sum the signed magnitude T.n (revoke n<0,
                -- unrevoke n>0). A positive `like` also counts as an
                -- `unrevoke` (the converse is false: a `dislike` never
                -- revokes). Author self-revoke feeds the absolute
                -- `author` channel; everyone else the `others` channel.
                if kind=='revoke' or T.n>0 then
                    local author = G.posts[T.post].author
                    local r = G.posts[T.post].revoke or { author=0, others=0 }
                    G.posts[T.post].revoke = r
                    if kind=='revoke' and author and T.sign==author then
                        r.author = r.author + T.n
                    else
                        r.others = r.others + T.n
                    end
                end

                if T.beg then
                    G.posts[T.post].maturity = "00-12"
                    G.posts[T.post].time = time
                    if a then
                        G.authors[a].time = G.authors[a].time or time
                    end
                end
            else
                G.authors[T.author] = G.authors[T.author] or { reps=0 }
                G.authors[T.author].reps = G.authors[T.author].reps + n
            end
        end
    end

    -- cap all authors at max
    for k, v in pairs(G.authors) do
        if v.reps > C.reps.max then
            v.reps = C.reps.max
        end
    end

    return true
end
