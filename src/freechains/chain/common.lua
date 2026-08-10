C      = require "freechains.constants"
ACTION = require "freechains.chain.action"
REPO   = ARGS.root .. "/chains/" .. ARGS.alias .. "/"

-- the git parents of `hash`: one step back in the DAG, no time
-- involved. Returns an array (empty for a root).
function parents (hash)
    local out = exec {
        cmd = "git -C " .. REPO .. " rev-list --parents -1 " .. hash,
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

-- local state snapshots, one per state commit:
--  - `.git/states/<hash>.lua`
--  - is_ref = true  : rev is a ref (HEAD)
--  - is_ref = false : rev is a hash
STATE = {
    -- G saved with every new state commit
    write = function (G, is_ref, rev)
        local hash = rev
        if is_ref then
            hash = exec {
                cmd = "git -C " .. REPO .. " rev-parse " .. rev,
            }
        end
        -- `.git/states/` is created at repo creation (chains.lua)
        local f = io.open(REPO .. ".git/states/" .. hash .. ".lua", "w")
        f:write(serial(G))
        f:close()
    end,

    -- the state RECORDED at `rev`
    read = function (is_ref, rev)
        local hash = rev
        if is_ref then
            hash = exec {
                cmd = "git -C " .. REPO .. " rev-parse " .. rev,
            }
        end
        local f = assert(
            loadfile(REPO .. ".git/states/" .. hash .. ".lua"),
            "bug found : no snapshot : " .. hash
        )
        return f()
    end,
}

-- REVOKED when either the author's or the community's net revoke sum is negative.
function is_revoked (p)
    local r = p.revoke or {}
    return ((r.author or 0) < 0) or ((r.others or 0) < 0)
end

-- posts hashes in a stable order: (time, hash); consolidated posts
-- (time == nil) sort last, then lexicographically by hash. Makes the
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
local function TIME (hash)
    return assert(tonumber((exec {
        cmd = "git -C " .. REPO .. " log -1 --format=%at " .. hash,
    })))
end

-- the peak RECORDED at `rev` (`now`): the newest time among all of
-- its ancestors. Derived, never trusted: `commit` in consensus.lua
-- checks every stored value against its parents' before using it.
-- Accepts refs (HEAD): the snapshot read resolves them.
function PEAK (rev)
    return STATE.read(true, rev).now
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

-- no author holds more than `max`
-- applied ONCE at the end of a step
function cap (G)
    for _, v in pairs(G.authors) do
        if v.reps > C.reps.max then
            v.reps = C.reps.max
        end
    end
end

-- TIME: the scans that run before anything else
-- discount refunds, consolidation grants, then `now` advances
-- in a `reps` query nothing happened but time passing (no `sign`, no action)
function advance (G, env)
    local sign = env.sign

    -- discount scan (maybe signed at same G.now)
    if env.time>G.now or sign then
        for _, hash in ipairs(ordered(G.posts)) do
            local entry = G.posts[hash]
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

                if env.time >= entry.time + discount then
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
    if env.time > G.now then
        for _, hash in ipairs(ordered(G.posts)) do
            local entry = G.posts[hash]
            if entry.maturity == "12-24" then
                if env.time >= entry.time+C.time.full then
                    if entry.author then
                        local last = G.authors[entry.author].time
                        if env.time-last >= C.time.full then
                            G.authors[entry.author].reps = G.authors[entry.author].reps + C.reps.earn
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

    if env.time > G.now then
        G.now = env.time
    end
end

-- an action is applied from two sides:
--  - `act`: what its author CLAIMS (n, post, author)
--  - `env`: what the chain VERIFIED: (time, aid, sign, parents, beg)
function apply (G, kind, act, env)
    -- a commit may sit at most `time.diff` below everything that precedes it
    -- read from the DAG, so it does not depend on the order a replay applies
    -- commits in (consensus order is not chronological order)
    do
        local up = PEAKS(env.parents)
        if env.time < up-C.time.diff then
            return false, "too old"
        end
    end

    advance(G, env)

    do
        if kind == 'post' then
            -- validation
            assert(env.sign or env.beg)
            if env.sign then
                if env.beg then
                    local reps = G.authors[env.sign] and G.authors[env.sign].reps or 0
                    if reps >= C.reps.cost then
                        return false, "--beg error : author has sufficient reputation"
                    end
                else
                    local reps = G.authors[env.sign] and G.authors[env.sign].reps or 0
                    if reps < C.reps.cost then
                        return false, "insufficient reputation"
                    end
                end
            end

            -- mutation
            G.posts[env.aid] = {
                author   = env.sign,
                time     = env.time,
                maturity = (env.beg and 'beg') or (env.sign and '00-12') or 'beg',
                reps     = 0,
                revoke   = { author=0, others=0 },
            }
            if env.sign then
                G.authors[env.sign] = G.authors[env.sign] or { reps=0 }
                if not env.beg then
                    G.authors[env.sign].reps = G.authors[env.sign].reps - C.reps.cost
                    G.authors[env.sign].time = G.authors[env.sign].time or env.time
                        -- do not set for beg, bc not available to others
                end
            end

        elseif kind=='like' or kind=='revoke' then
            -- validation
            assert(env.sign, "bug found")
            if math.type(act.n)~='integer' or act.n==0 then
                return false, "invalid number : expects non-zero integer"
            end
            if (act.post and act.author) or (not act.post and not act.author) then
                return false, "invalid target : expects 'post' or 'author'"
            end
            -- revoke/unrevoke are post-only
            if kind=='revoke' and (not act.post) then
                return false, "invalid target : expects 'post'"
            end
            if act.post and (not G.posts[act.post]) then
                return false, "invalid target : post not found"
            end

            -- author self-revoke (right to be forgotten) is free and ungated
            local self_revoke = (
                kind=='revoke' and act.n<0 and G.posts[act.post].author==env.sign
            )

            -- must afford the full vote magnitude (no debt); self-revoke is free
            local reps = (G.authors[env.sign] and G.authors[env.sign].reps) or 0
            if (not self_revoke) and reps<math.abs(act.n) then
                return false, "insufficient reputation"
            end

            -- admission mints future income (a refund at 12h, then
            -- `earn` a day): its price must not be dust
            if env.beg and act.n<C.reps.cost then
                return false, "invalid beg like : insufficient reputation"
            end

            -- mutation
            if not self_revoke then
                G.authors[env.sign].reps = reps - math.abs(act.n)
            end
            local n = act.n * (100 - C.like.tax) // 100
            if act.post then
                local a = G.posts[act.post].author
                if not (self_revoke or (kind=='revoke' and act.n>0)) then
                    if a then
                        G.authors[a] = G.authors[a] or { reps=0 }
                        G.authors[a].reps = G.authors[a].reps + n//C.like.split
                    else
                        assert(env.beg)
                    end
                    G.posts[act.post].reps = G.posts[act.post].reps + n//C.like.split
                end

                -- revoke axis: sum the signed magnitude act.n (revoke n<0,
                -- unrevoke n>0). A positive `like` also counts as an
                -- `unrevoke` (the converse is false: a `dislike` never
                -- revokes). Author self-revoke feeds the absolute
                -- `author` channel; everyone else the `others` channel.
                if kind=='revoke' or act.n>0 then
                    local author = G.posts[act.post].author
                    local r = G.posts[act.post].revoke or { author=0, others=0 }
                    G.posts[act.post].revoke = r
                    if kind=='revoke' and author and env.sign==author then
                        r.author = r.author + act.n
                    else
                        r.others = r.others + act.n
                    end
                end

                if env.beg then
                    G.posts[act.post].maturity = "00-12"
                    G.posts[act.post].time = env.time
                    if a then
                        G.authors[a].time = G.authors[a].time or env.time
                    end
                end
            else
                G.authors[act.author] = G.authors[act.author] or { reps=0 }
                G.authors[act.author].reps = G.authors[act.author].reps + n
            end
        end
    end

    cap(G)

    return true
end
