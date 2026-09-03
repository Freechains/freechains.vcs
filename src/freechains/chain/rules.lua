-- the reputation rules: what an action does to `G`

local M = {}

--[[
-- Is the entry's payload REVOKED?
-- Inputs:
--  - act [table]: a G.actions entry
-- Outputs:
--  - [boolean]: member OR community net revoke below zero
-- Errors:
--  - none
-- Callers:
--  - apply (rules.lua): self-revoke flood check
--  - like (like.lua): the REMOVAL/LIFT crossing
--  - list (list.lua): ~cid~ wrapping, revokes listing
--  - get (get.lua): refuse a revoked payload
--  - recv (sync.lua): payload anchor reconcile
--]]
function M.is_revoked (act)
    local r = act.revoke or {}
    return ((r.member or 0) < 0) or ((r.others or 0) < 0)
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
local function ordered (G)
    local hs = {}
    for h in pairs(G.actions) do
        hs[#hs+1] = h
    end
    table.sort(hs, function (a, b)
        local ta = G.actions[a].time or math.huge
        local tb = G.actions[b].time or math.huge
        if ta == tb then
            return a < b
        else
            return ta < tb
        end
    end)
    return hs
end

--[[
-- Cap every member at C.reps.max, ONCE at the end of a step.
-- Inputs:
--  - G [table]: chain state; MUTATED (G.members[*].reps)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - apply (rules.lua): after every action
--  - reps (reps.lua): after the query-time advance
--]]
function M.cap (G)
    for _, v in pairs(G.members) do
        if v.reps > C.reps.max then
            v.reps = C.reps.max
        end
    end
end

--[[
-- Positive reps of member `a` (unknown = 0).
-- Inputs:
--  - G [table]: chain state
--      (reads G.members; NOT the global: replay passes its own states)
--  - a [string]: member pubkey
-- Outputs:
--  - [integer]: max(0, reps)
-- Errors:
--  - none
-- Callers:
--  - advance (rules.lua): discount scan sums
--]]
local function reps_of (G, a)
    local T = G.members[a]
    return math.max(0, (T and T.reps) or 0)
end

--[[
-- Advance time: discount refunds (12h), consolidation grants (24h).
-- Then `now` advances.
-- Inputs:
--  - G    [table]: chain state; MUTATED (maturities, reps, G.now)
--  - time [integer]: the time driving the scans (act.time)
--  - sign [string?]: the acting member's pubkey; in a `reps`
--    query nothing happened but time passing (no sign, no action)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - apply (rules.lua): before every action
--  - reps (reps.lua): fold time up to --now at query time
--]]
function M.advance (G, time, sign)
    local ORD

    -- discount scan (maybe signed at same G.now)
    -- entries come in time order, so members acting AFTER entry shrink set
    -- `cur`/`TOT` are kept LIVE: a refund mid-scan is seen by
    -- the entries after it, exactly as the rescan per entry did
    if time>G.now or sign then
        ORD = ordered(G)

        local TOT = 0       -- positive reps of all members
        for _, v in pairs(G.members) do
            TOT = TOT + math.max(0, v.reps)
        end

        local cnt = {}      -- member -> its N actions still ahead
        local cur = 0       -- positive reps of cnt>0 members
        for _, cid in ipairs(ORD) do
            local e = G.actions[cid]
            if e.member and e.time then
                local n = cnt[e.member]
                cnt[e.member] = (n or 0) + 1
                if not n then
                    cur = cur + reps_of(G, e.member)
                end
            end
        end

        local k = 1         -- next action to fall behind
        for _, cid in ipairs(ORD) do
            local entry = G.actions[cid]
            if entry.maturity == "00-12" then
                -- drop the actions at/below this entry's time:
                -- `subs` = the members still counted after that
                while k <= #ORD do
                    local o = G.actions[ORD[k]]
                    if (o.time or math.huge) > entry.time then
                        break
                    end
                    if o.member and o.time then
                        local n = cnt[o.member] - 1
                        cnt[o.member] = n
                        if n == 0 then
                            cur = cur - reps_of(G, o.member)
                        end
                    end
                    k = k + 1
                end

                -- the actor counts as a sub, even with no action
                local c = cur
                if sign and ((cnt[sign] or 0) == 0) then
                    c = c + reps_of(G, sign)
                end

                local ratio = (TOT>0 and c/TOT) or 0
                local discount = C.time.half * math.max(0, 1 - 2*ratio)

                if time >= entry.time + discount then
                    -- signed beg?
                    if entry.member then
                        local A = G.members[entry.member]
                        local old = math.max(0, A.reps)
                        A.reps = A.reps + C.reps.cost
                        local d = math.max(0, A.reps) - old
                        TOT = TOT + d
                        if (cnt[entry.member] or 0) > 0 then
                            cur = cur + d
                        end
                    end
                    entry.maturity = "12-24"
                end
            end
        end
    end

    -- consolidation scan
    if time > G.now then
        for _, cid in ipairs(ORD) do
            local entry = G.actions[cid]
            if entry.maturity == "12-24" then
                if time >= entry.time+C.time.full then
                    if entry.member then
                        local last = G.members[entry.member].time
                        if time-last >= C.time.full then
                            G.members[entry.member].reps = G.members[entry.member].reps + C.reps.earn
                            G.members[entry.member].time = last + C.time.full
                            entry.maturity = nil
                            entry.time  = nil
                        end
                    else
                        -- memberless (unsigned beg): consolidate, no credit
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
function M.now (G, backs)
    local max = 0
    for _, a in ipairs(backs) do
        local now = assert(G.actions[a]).now
        max = math.max(max, now)
    end
    return max
end

--[[
-- Ungated posts and votes
-- Dictators or unrestricted chains (no pioneers, no dictators).
-- Inputs:
--  - G   [table]: chain state (reads G.open and G.members)
--  - key [string?]: the acting member's pubkey
-- Outputs:
--  - [boolean]: true when the gate must be skipped
-- Errors:
--  - none
-- Callers:
--  - apply (rules.lua): the post and the vote gates
--]]
local function ungated (G, key)
    if G.open then
        return true
    end
    local T = key and G.members[key]
    return (T and T.dictator) or false
end

--[[
-- The reputation state transition.
-- One action folded into `G`, from two sides:
--  what its member CLAIMS vs what the chain VERIFIED
-- Inputs:
--  - G   [table]: chain state; MUTATED on acceptance
--  - act [table]: what the commit SAYS: action (the kind), time
--    (its DATE, hash-bound), n, cid?|member? (the target)
--  - env [table]: what the chain DERIVED: cid, sign?, beg?, backs
-- Outputs:
--  - [true]: accepted, or
--  - [false, string]: refused ("too old", "too new",
--    "insufficient reputation", "invalid target : ...", ...)
-- Errors:
--  - assert: post without sign or beg; vote without sign (bugs:
--    the pipeline checks before calling)
-- Callers:
--  - apply (action.lua): the accept pipeline, per action
--]]
function M.apply (G, act, env)
    -- time sits within reasonable interval `time.diff`:
    --  max(backs)-diff <= me <= now+diff
    local up = M.now(G, env.backs)
    do
        if act.time < up-C.time.diff then
            return false, "too old"
        end
        if act.time > ARGS.now+C.time.diff then
            return false, "too new"
        end
    end

    M.advance(G, act.time, env.sign)

    if act.action == 'post' then
        -- validation
        assert(env.sign or env.beg)
        if env.beg and G.open then
            return false, "--beg error : open chain"
        end
        if env.sign then
            if env.beg then
                local reps = G.members[env.sign] and G.members[env.sign].reps or 0
                if reps >= C.reps.cost then
                    return false, "--beg error : member has sufficient reputation"
                end
            else
                local reps = G.members[env.sign] and G.members[env.sign].reps or 0
                if ungated(G,env.sign) or reps>=C.reps.cost then
                    -- OK
                else
                    return false, "insufficient reputation"
                end
            end
        end

        -- mutation
        G.actions[env.cid] = {
            action   = 'post',
            member   = env.sign,
            time     = act.time,
            now      = math.max(act.time, up),
            maturity = (env.beg and 'beg') or (env.sign and '00-12') or 'beg',
            reps     = 0,
            revoke   = { member=0, others=0 },
        }
        if env.sign then
            G.members[env.sign] = G.members[env.sign] or { reps=0 }
            if not env.beg then
                G.members[env.sign].reps = G.members[env.sign].reps - C.reps.cost
                G.members[env.sign].time = G.members[env.sign].time or act.time
                    -- do not set for beg, bc not available to others
            end
        end

    elseif act.action=='like' or act.action=='revoke' then
        -- validation
        assert(env.sign, "bug found")
        if math.type(act.n)~='integer' or act.n==0 then
            return false, "invalid number : expects non-zero integer"
        end
        if (act.cid and act.member) or (not act.cid and not act.member) then
            return false, "invalid target : expects 'action' or 'member'"
        end
        -- revoke/unrevoke never target an member
        if act.action=='revoke' and (not act.cid) then
            return false, "invalid target : expects 'action'"
        end
        -- every chain action costs at least a post
        -- (small votes would flood at 1 rep/commit)
        if act.action=='like' and math.abs(act.n)<C.reps.cost then
            return false, "invalid number : expects at least " .. C.reps.cost
        end
        -- hiding a post must cost at least what a day mints:
        -- one dust unit used to bury a 500-reps post
        if act.action=='revoke' and math.abs(act.n)<C.reps.revoke then
            return false,
                "invalid number : expects at least " .. C.reps.revoke
        end
        if act.cid and (not G.actions[act.cid]) then
            return false, "invalid target : action not found"
        end

        -- member self-revoke (right to be forgotten) is free and ungated
        local self_revoke = (
            act.action=='revoke' and act.n<0 and G.actions[act.cid].member==env.sign
        )

        -- since self-revoke is free, check its not a "flooding attack"
        if self_revoke then
            if G.actions[act.cid].revoke.member<0 then
                return false, "already revoked"
            end
        end

        -- must afford the full vote magnitude (no debt); self-revoke is free
        local reps = (G.members[env.sign] and G.members[env.sign].reps) or 0
        if self_revoke or ungated(G,env.sign) or reps>=math.abs(act.n) then
            -- OK
        else
            return false, "insufficient reputation"
        end


        -- mutation
        if not self_revoke then
            -- ungated may vote, so the entry may not exist yet
            G.members[env.sign] = G.members[env.sign] or { reps=0 }
            G.members[env.sign].reps = reps - math.abs(act.n)
        end
        local n = act.n * (100 - C.vote.tax) // 100
        if act.cid then
            local e = G.actions[act.cid]
            local a = e.member
            if not (self_revoke or (act.action=='revoke' and act.n>0)) then
                if a then
                    G.members[a] = G.members[a] or { reps=0 }
                    G.members[a].reps = G.members[a].reps + n//C.vote.split
                else
                    assert(env.beg)
                end
                e.reps = e.reps + n//C.vote.split
            end

            -- revoke axis: sum the signed magnitude act.n (revoke n<0,
            -- unrevoke n>0). A positive `like` also counts as an
            -- `unrevoke` (the converse is false: a `dislike` never
            -- revokes). Member self-revoke feeds the absolute
            -- `member` channel; everyone else the `others` channel.
            if act.action=='revoke' or act.n>0 then
                local r = e.revoke
                if act.action=='revoke' and a and env.sign==a then
                    r.member = r.member + act.n
                else
                    r.others = r.others + act.n
                end
            end

            if env.beg then
                e.maturity = "00-12"
                e.time = act.time
                if a then
                    G.members[a].time = G.members[a].time or act.time
                end
            end
        else
            G.members[act.member] = G.members[act.member] or { reps=0 }
            G.members[act.member].reps = G.members[act.member].reps + n
        end

        -- the vote enters the registry as a target of its own:
        G.actions[env.cid] = {
            action = act.action,
            member = env.sign,
            now    = math.max(act.time, up),
            reps   = 0,
            revoke = { member=0, others=0 },
        }
    end

    M.cap(G)

    return true
end

return M
