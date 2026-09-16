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
--  - apply (rules.lua): self-revoke flood check, rule 1.b flip
--  - advance (rules.lua): consolidation of a revoked post
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
-- Insert a pending record, keeping (time, cid) order.
-- `G.pending` mirrors the maturing entries (time.member ~= nil):
-- { cid, member?, time, maturity }, so the scans never touch the
-- consolidated majority of `G.actions`. `maturity` is kept in sync
-- with the entry by the scans below.
-- Inputs:
--  - G [table]: chain state; MUTATED (G.pending)
--  - r [table]: the record
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - apply (rules.lua): a new post, a promoted beg
--]]
local function pend (G, r)
    STATE.day(G, r.time)    -- its bucket must be whole before rewriting
    if r.maturity ~= "12-24" then
        G.min0012 = math.min(G.min0012 or r.time, r.time)
    end
    local P = G.pending
    local lo, hi = 1, #P+1
    while lo < hi do
        local mid = (lo+hi) // 2
        local m = P[mid]
        if (m.time < r.time) or (m.time == r.time and m.cid < r.cid) then
            lo = mid + 1
        else
            hi = mid
        end
    end
    table.insert(P, lo, r)
    G.dirty.pending[r.time] = true
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
    -- only a member touched this step can have crossed the cap
    for k in pairs(G.dirty.members) do
        local v = G.members[k]
        if v.reps > C.reps.max then
            M.bump(G, k, C.reps.max - v.reps)
        end
    end
end

--[[
-- Move member reps by `d`, keeping `G.tot` (the positive total the
-- discount rule divides by) and the dirty set; creates the member.
-- Inputs:
--  - G   [table]: chain state; MUTATED (members, tot, dirty)
--  - pub [string]: member pubkey
--  - d   [integer]: the delta (negative: cost, drain, clawback)
-- Outputs:
--  - [integer]: the change of the member's POSITIVE reps
-- Errors:
--  - none
-- Callers:
--  - advance/apply/cap (rules.lua): every reps change
--]]
function M.bump (G, pub, d)
    local A = G.members[pub]
    if not A then
        A = { reps=0 }
        G.members[pub] = A
    end
    local old = math.max(0, A.reps)
    A.reps = A.reps + d
    local pos = math.max(0, A.reps) - old
    G.tot = G.tot + pos
    G.dirty.members[pub] = true
    return pos
end

--[[
-- Set member `m`'s head (its oldest waiting 12-24 record time) and
-- keep the due-heads index `G.heads` (sorted by time) in step.
-- Inputs:
--  - G [table]: chain state; MUTATED (members, heads, dirty)
--  - m [string]: member pubkey
--  - t [integer?]: the head time; nil removes it
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - advance (rules.lua): maturation and settling
--]]
local function sethead (G, m, t)
    local A = G.members[m]
    A.head = t
    G.dirty.members[m] = true
    local H = G.heads
    for i = #H, 1, -1 do
        if H[i].member == m then
            table.remove(H, i)
        end
    end
    if t then
        local lo, hi = 1, #H+1
        while lo < hi do
            local mid = (lo+hi) // 2
            if H[mid].time < t or (H[mid].time == t and H[mid].member < m) then
                lo = mid + 1
            else
                hi = mid
            end
        end
        table.insert(H, lo, { time=t, member=m })
    end
    G.dirty.heads = true
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
-- A revoked post consolidates without credit (rule 1.b).
-- Then `now` advances.
-- Inputs:
--  - G    [table]: chain state; MUTATED (maturities, reps, G.now,
--    G.pending)
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
    -- `G.pending` holds the loaded WINDOW: every maturing record
    -- (00-12/beg) and everything after the oldest of them, so the
    -- discount scan below is exact; older days hold settled-in-
    -- waiting (12-24) records and load on demand, driven by each
    -- member's `head` (its oldest 12-24 record time)
    local P = G.pending

    -- discount scan (maybe signed at same G.now)
    -- records come in time order, so members acting AFTER a record
    -- shrink set; `cur`/`TOT` are kept LIVE: a refund mid-scan is
    -- seen by the records after it
    if time>G.now or sign then
        -- the members of the window, in one batch
        do
            local pubs, seen = { sign }, {}
            for _, r in ipairs(P) do
                if r.member and (not seen[r.member]) then
                    seen[r.member] = true
                    pubs[#pubs+1] = r.member
                end
            end
            STATE.members(G, pubs)
        end

        local cnt = {}      -- member -> its N actions still ahead
        local cur = 0       -- positive reps of cnt>0 members
        for _, r in ipairs(P) do
            if r.member then
                local n = cnt[r.member]
                cnt[r.member] = (n or 0) + 1
                if not n then
                    cur = cur + reps_of(G, r.member)
                end
            end
        end

        -- the entries that may mature now, in one batch
        do
            local cids = {}
            for _, r in ipairs(P) do
                if r.maturity == "00-12" and r.time <= time then
                    cids[#cids+1] = r.cid
                end
            end
            STATE.fetch(G, cids)
        end

        local k = 1         -- next record to fall behind
        for _, r in ipairs(P) do
            if r.maturity == "00-12" then
                -- drop the records at/below this one's time:
                -- `subs` = the members still counted after that
                while k <= #P do
                    local o = P[k]
                    if o.time > r.time then
                        break
                    end
                    if o.member then
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

                local ratio = (G.tot>0 and c/G.tot) or 0
                local discount = C.time.half * math.max(0, 1 - 2*ratio)

                if time >= r.time + discount then
                    -- signed beg?
                    if r.member then
                        local d = M.bump(G, r.member, C.reps.cost)
                        if (cnt[r.member] or 0) > 0 then
                            cur = cur + d
                        end
                        -- now waiting for its slot: the member's head
                        local A = G.members[r.member]
                        if (not A.head) or (r.time < A.head) then
                            sethead(G, r.member, r.time)
                        end
                    elseif (not G.headless) or (r.time < G.headless) then
                        G.headless = r.time
                    end
                    r.maturity = "12-24"
                    G.dirty.pending[r.time] = true
                    G.actions[r.cid].maturity = "12-24"
                    G.dirty.actions[r.cid] = true
                end
            end
        end

        -- the window floor: oldest record still maturing
        G.min0012 = nil
        for _, r in ipairs(P) do
            if r.maturity ~= "12-24" then
                G.min0012 = math.min(G.min0012 or r.time, r.time)
            end
        end
    end

    -- consolidation scan, by heads: a member settles its oldest
    -- 12-24 record while it is due and a daily slot is free
    if time > G.now then
        local gone = {}     -- cid -> settled now

        --[[
        -- The 12-24 record of `m` at time `t` (its bucket loaded).
        -- Inputs:
        --  - m [string?]: member (nil: unsigned)
        --  - t [integer]: the head time
        -- Outputs:
        --  - [table?]: a record not yet settled, or nil
        --]]
        local function find (m, t)
            STATE.day(G, t)
            for _, r in ipairs(G.pending) do
                if r.member == m and r.time == t and r.maturity == "12-24" and (not gone[r.cid]) then
                    return r
                end
            end
            return nil
        end

        --[[
        -- The next head of `m` after time `t`: the oldest 12-24
        -- record later than `t`, walking the bucket days forward.
        -- Inputs:
        --  - m [string?]: member (nil: unsigned)
        --  - t [integer]: the previous head time
        -- Outputs:
        --  - [integer?]: the time, or nil (no more)
        --]]
        local function nexthead (m, t)
            local day = STATE.day(G, t)
            while day do
                local lo, hi = day*C.time.full, (day+1)*C.time.full
                local best
                for _, r in ipairs(G.pending) do
                    if r.member == m and r.maturity == "12-24" and r.time > t
                    and r.time >= lo and r.time < hi and (not gone[r.cid])
                    and ((not best) or r.time < best) then
                        best = r.time
                    end
                end
                if best then
                    return best
                end
                day = STATE.next_day(G, day)
                if day then
                    STATE.day(G, day*C.time.full)
                end
            end
            return nil
        end

        --[[
        -- Settle record `r`: rule 1.b credit (unless revoked), the
        -- entry leaves `pending`.
        -- Inputs:
        --  - r [table]: a 12-24 record
        --]]
        local function settle (r)
            local entry = G.actions[r.cid]
            if r.member then
                -- the slot is consumed either way;
                -- a revoked post pays 0 (rule 1.b)
                if not M.is_revoked(entry) then
                    M.bump(G, r.member, C.reps.earn)
                end
                G.members[r.member].time = G.members[r.member].time + C.time.full
                G.dirty.members[r.member] = true
            end
            entry.maturity = nil
            entry.time.member = nil
            G.dirty.actions[r.cid] = true
            G.dirty.pending[r.time] = true
            gone[r.cid] = true
        end

        -- the due heads, oldest first, their members in one batch
        local due = {}
        for _, h in ipairs(G.heads) do
            if time >= h.time+C.time.full then
                due[#due+1] = h.member
            else
                break
            end
        end
        STATE.members(G, due)
        for _, m in ipairs(due) do
            local A = G.members[m]
            while A.head and (time >= A.head+C.time.full) and (time-A.time >= C.time.full) do
                local r = find(m, A.head)
                if r then
                    settle(r)
                else
                    sethead(G, m, nexthead(m, A.head))
                end
            end
        end
        -- memberless (unsigned begs): consolidate, no credit, no slot
        while G.headless and (time >= G.headless+C.time.full) do
            local r = find(nil, G.headless)
            if r then
                settle(r)
            else
                G.headless = nexthead(nil, G.headless)
            end
        end

        if next(gone) then
            local keep = {}
            for _, r in ipairs(G.pending) do
                if not gone[r.cid] then
                    keep[#keep+1] = r
                end
            end
            G.pending = keep
        end
    end

    if time > G.now then
        G.now = time
    end
end

--[[
-- The newest time causally preceding a set of actions: each
-- entry records its own `time.backs` at apply, so the fold is one walk.
-- Inputs:
--  - G     [table]: chain state (reads G.actions[*].time.backs)
--  - backs [table]: action cids, STRUCTURAL (from the parents)
-- Outputs:
--  - [integer]: max of the backs' recorded `time.backs`, 0 if none
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
        local t = assert(G.actions[a]).time.backs
        max = math.max(max, t)
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
-- Every entry records three times:
--  - `time.member`: the date its member claims (nil once consolidated)
--  - `time.backs`: max member time over its ancestry ("too old")
--  - `time.apply`: chain time when applied in the local order
--    (max member time so far), a function of the DAG order
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
            time     = { member=act.time, backs=math.max(act.time,up), apply=G.now },
            maturity = (env.beg and 'beg') or (env.sign and '00-12') or 'beg',
            reps     = 0,
            revoke   = { member=0, others=0 },
        }
        G.dirty.actions[env.cid] = true
        pend(G, {
            cid      = env.cid,
            member   = env.sign,
            time     = act.time,
            maturity = G.actions[env.cid].maturity,
        })
        if env.sign then
            if env.beg then
                M.bump(G, env.sign, 0)   -- the member exists from here
            else
                M.bump(G, env.sign, -C.reps.cost)
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
            M.bump(G, env.sign, -math.abs(act.n))
        end
        local n = act.n * (100 - C.vote.tax) // 100
        if act.cid then
            local e = G.actions[act.cid]
            local a = e.member
            G.dirty.actions[act.cid] = true
            if not (self_revoke or (act.action=='revoke' and act.n>0)) then
                if a then
                    M.bump(G, a, n//C.vote.split)
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
            local was = M.is_revoked(e)
            if act.action=='revoke' or act.n>0 then
                local r = e.revoke
                if act.action=='revoke' and a and env.sign==a then
                    r.member = r.member + act.n
                else
                    r.others = r.others + act.n
                end
            end

            -- rule 1.b: a consolidated post holds its +1K for the
            -- author only while not revoked: the credit follows the
            -- revoke sums, so a crossing moves it back or forth
            if a and e.action=='post' and (not e.maturity) and was~=M.is_revoked(e) then
                M.bump(G, a, was and C.reps.earn or -C.reps.earn)
            end

            if env.beg then
                e.maturity = "00-12"
                e.time.member = act.time
                pend(G, { cid=act.cid, member=a, time=act.time, maturity="00-12" })
                if a then
                    M.bump(G, a, 0)
                    G.members[a].time = G.members[a].time or act.time
                end
            end
        else
            M.bump(G, act.member, n)
        end

        -- the vote enters the registry as a target of its own:
        G.actions[env.cid] = {
            action = act.action,
            member = env.sign,
            time   = { backs=math.max(act.time,up), apply=G.now },
            reps   = 0,
            revoke = { member=0, others=0 },
        }
        G.dirty.actions[env.cid] = true
    end

    M.cap(G)

    return true
end

return M
