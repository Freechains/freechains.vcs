-- the reputation rules: what an action does to `G`

--[[
-- Is the entry's payload REVOKED?
-- Inputs:
--  - act [table]: a G.actions entry
-- Outputs:
--  - [boolean]: author OR community net revoke below zero
-- Errors:
--  - none
-- Callers:
--  - apply (rules.lua): self-revoke flood check
--  - like (like.lua): the REMOVAL/LIFT crossing
--  - list (list.lua): ~cid~ wrapping, revokes listing
--  - get (get.lua): refuse a revoked payload
--  - recv (sync.lua): payload anchor reconcile
--]]
    return ((r.author or 0) < 0) or ((r.others or 0) < 0)
end

--[[
-- Action cids in a stable order.
-- (time, cid); consolidated actions (time == nil) sort last.
-- Makes the scans deterministic across OS processes.
-- Inputs:
--  - G [table]: chain state (reads G.actions; NOT the global:
--    replay passes its own states)
-- Outputs:
--  - [table]: array of cids, sorted
-- Errors:
--  - none
-- Callers:
--  - advance (rules.lua): discount and consolidation scans
--]]
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

--[[
-- Cap every author at C.reps.max, ONCE at the end of a step.
-- Inputs:
--  - G [table]: chain state; MUTATED (G.authors[*].reps)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - apply (rules.lua): after every action
--  - reps (reps.lua): after the query-time advance
--]]
function cap (G)
    for _, v in pairs(G.authors) do
        if v.reps > C.reps.max then
            v.reps = C.reps.max
        end
    end
end

--[[
-- Advance time: discount refunds (12h), consolidation grants (24h).
-- Then `now` advances.
-- Inputs:
--  - G   [table]: chain state; MUTATED (maturities, reps, G.now)
--  - env.time [integer]: the verified time driving the scans
--  - env.sign [string?]: the acting author's pubkey; in a `reps`
--    query nothing happened but time passing (no sign, no action)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - apply (rules.lua): before every action
--  - reps (reps.lua): fold time up to --now at query time
--]]
function advance (G, env)
    local sign = env.sign

    -- discount scan (maybe signed at same G.now)
    if env.time>G.now or sign then
        for _, cid in ipairs(ordered(G.actions)) do
            local entry = G.actions[cid]
            if entry.maturity == "00-12" then
                local subs = {}
                for h2, other in pairs(G.actions) do
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
        for _, cid in ipairs(ordered(G.actions)) do
            local entry = G.actions[cid]
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

--[[
-- The newest time causally preceding a set of actions: each
-- entry records its own `now` at apply, so the fold is one walk.
-- Inputs:
--  - G     [table]: chain state (reads G.actions[*].now)
--  - backs [table]: action cids, STRUCTURAL (from the parents)
-- Outputs:
--  - [integer]: max of the backs' recorded `now`, 0 if none
-- Errors:
--  - assert: a back without a G entry (bug: backs precede)
-- Callers:
--  - apply (rules.lua): the "too old" lower bound
--  - apply (action.lua): merge-snapshot `now` fold
--  - recv (sync.lua): loser sync-merge snapshot fold
--]]
function NOW (G, backs)
    local max = 0
    for _, a in ipairs(backs) do
        local now = assert(G.actions[a]).now
        max = math.max(max, now)
    end
    return max
end

-- an action is applied from two sides:
--  - `act`: what its author CLAIMS (n, target=cid/author)
--  - `env`: what the chain VERIFIED: (time, cid, sign, beg, backs)
function apply (G, kind, act, env)
    -- time sits within reasonable interval `time.diff`:
    --  max(backs)-diff <= me <= now+diff
    local up = NOW(G, env.backs)
    do
        if env.time < up-C.time.diff then
            return false, "too old"
        end
        if env.time > ARGS.now+C.time.diff then
            return false, "too new"
        end
    end

    advance(G, env)

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
        G.actions[env.cid] = {
            action   = 'post',
            author   = env.sign,
            time     = env.time,
            now      = math.max(env.time, up),
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
        if (act.cid and act.author) or (not act.cid and not act.author) then
            return false, "invalid target : expects 'action' or 'author'"
        end
        -- revoke/unrevoke never target an author
        if kind=='revoke' and (not act.cid) then
            return false, "invalid target : expects 'action'"
        end
        -- hiding a post must cost at least what a day mints:
        -- one dust unit used to bury a 500-reps post
        if kind=='revoke' and math.abs(act.n)<C.reps.revoke then
            return false,
                "invalid number : expects at least " .. C.reps.revoke
        end
        if act.cid and (not G.actions[act.cid]) then
            return false, "invalid target : action not found"
        end

        -- author self-revoke (right to be forgotten) is free and ungated
        local self_revoke = (
            kind=='revoke' and act.n<0 and G.actions[act.cid].author==env.sign
        )

        -- since self-revoke is free, check its not a "flooding attack"
        if self_revoke then
            if G.actions[act.cid].revoke.author<0 then
                return false, "already revoked"
            end
        end

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
        local n = act.n * (100 - C.vote.tax) // 100
        if act.cid then
            local e = G.actions[act.cid]
            local a = e.author
            if not (self_revoke or (kind=='revoke' and act.n>0)) then
                if a then
                    G.authors[a] = G.authors[a] or { reps=0 }
                    G.authors[a].reps = G.authors[a].reps + n//C.vote.split
                else
                    assert(env.beg)
                end
                e.reps = e.reps + n//C.vote.split
            end

            -- revoke axis: sum the signed magnitude act.n (revoke n<0,
            -- unrevoke n>0). A positive `like` also counts as an
            -- `unrevoke` (the converse is false: a `dislike` never
            -- revokes). Author self-revoke feeds the absolute
            -- `author` channel; everyone else the `others` channel.
            if kind=='revoke' or act.n>0 then
                local r = e.revoke
                if kind=='revoke' and a and env.sign==a then
                    r.author = r.author + act.n
                else
                    r.others = r.others + act.n
                end
            end

            if env.beg then
                e.maturity = "00-12"
                e.time = env.time
                if a then
                    G.authors[a].time = G.authors[a].time or env.time
                end
            end
        else
            G.authors[act.author] = G.authors[act.author] or { reps=0 }
            G.authors[act.author].reps = G.authors[act.author].reps + n
        end

        -- the vote enters the registry as a target of its own:
        G.actions[env.cid] = {
            action = kind,
            author = env.sign,
            now    = math.max(env.time, up),
            reps   = 0,
            revoke = { author=0, others=0 },
        }
    end

    cap(G)

    return true
end
