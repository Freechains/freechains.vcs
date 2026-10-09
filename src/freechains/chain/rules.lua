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
--  - close (rules.lua): a revoked post pays 0 at the full tick
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
--  - advance/close/apply/cap (rules.lua): every reps change
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
--  - ratio (rules.lua): the tick activity
--]]
local function reps_of (G, a)
    local T = G.members[a]
    return math.max(0, (T and T.reps) or 0)
end

--[[
-- What `advance(G, time, sign)` will load: the actor, the members
-- acting in the current tick (its ratio), and the posts a close
-- refunds and rewards, with their members.
-- Inputs:
--  - G    [table]: chain state (reads G.tick)
--  - time [integer]: the time driving the clock (unused: the tick's
--    working set is the same whenever it closes)
--  - sign [string?]: the acting member's pubkey
-- Outputs:
--  - [table]: array of cids (the tick's charged posts)
--  - [table]: array of pubkeys, no repeats
-- Errors:
--  - none
-- Callers:
--  - apply (action.lua): folded into the action's batch
--]]
function M.needs (G, time, sign)
    local T = G.tick
    local cids = table.move(T.posts, 1, #T.posts, 1, {})
    local pubs, seen = {}, {}
    local function pub (k)
        if k and (not seen[k]) then
            seen[k] = true
            pubs[#pubs+1] = k
        end
    end
    pub(sign)
    for k in pairs(T.acting) do
        pub(k)
    end
    for k, cid in pairs(T.posted) do
        pub(k)
        cids[#cids+1] = cid
    end
    return cids, pubs
end

--[[
-- The activity ratio of the current tick.
-- Inputs:
--  - G [table]: chain state (reads G.members, G.tot, G.tick.acting)
-- Outputs:
--  - [number]: positive reps of the members acting since the tick
--    started / positive reps of all members (`G.tot`), 0 if none
-- Errors:
--  - none
-- Callers:
--  - advance (rules.lua): the length of the current tick
--]]
local function ratio (G)
    if G.tot <= 0 then
        return 0
    end
    local keys = {}
    for key in pairs(G.tick.acting) do
        keys[#keys+1] = key
    end
    STATE.members(G, keys)
    local cur = 0
    for _, key in ipairs(keys) do
        cur = cur + reps_of(G, key)
    end
    return cur / G.tot
end

--[[
-- How long the current tick lasts given its activity:
-- `half * max(0, 1 - 2*ratio)`, 12h with no activity, 0 once
-- half of the reps have acted.
-- Inputs:
--  - G [table]: chain state
-- Outputs:
--  - [integer]: seconds from the tick start to its close
-- Errors:
--  - none
-- Callers:
--  - advance (rules.lua)
--]]
local function wait (G)
    return math.floor(C.time.half * math.max(0, 1 - 2*ratio(G)))
end

--[[
-- Close the current half tick at chain time `stop`.
-- Refunds the posts charged since the previous half tick (rule 2).
-- Every second close is a full tick: each member is rewarded once
-- for its first post since the previous full tick (rule 1.b); a
-- revoked post pays 0 but keeps the credit, so a later crossing
-- moves it (see apply).
-- Inputs:
--  - G    [table]: chain state; MUTATED (reps, tick, entry.credit)
--  - stop [integer]: chain time of the close (next tick start)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - advance (rules.lua): time-based and actor-based closes
--]]
local function close (G, stop)
    local T = G.tick
    T.n = T.n + 1
    STATE.fetch(G, T.posts)
    for _, cid in ipairs(T.posts) do
        M.bump(G, G.actions[cid].member, C.reps.cost)
    end
    T.posts = {}
    if T.n % 2 == 0 then
        local cids = {}
        for _, cid in pairs(T.posted) do
            cids[#cids+1] = cid
        end
        STATE.fetch(G, cids)
        for key, cid in pairs(T.posted) do
            local entry = G.actions[cid]
            entry.credit = true
            G.dirty.actions[cid] = true
            if not M.is_revoked(entry) then
                M.bump(G, key, C.reps.earn)
            end
        end
        T.posted = {}
    end
    T.start  = stop
    T.acting = {}
end

--[[
-- Advance chain time: close the ticks that ended since the
-- previous action, then let the actor close the current one.
-- The actor counts for the tick it closes; its action lands in
-- the next one.
-- Inputs:
--  - G    [table]: chain state; MUTATED (reps, tick, G.now)
--  - time [integer]: the time driving the clock (act.time)
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
    local T = G.tick
    local now = math.max(G.now, time)

    -- ticks that ended between the previous action and now:
    -- first with the acting set as it was, then empty ones
    while true do
        local w = wait(G)
        if now < T.start + w then
            break
        end
        if next(T.acting)==nil and #T.posts==0 and next(T.posted)==nil then
            -- nothing to refund or reward: jump the empty ticks and
            -- restart the clock now (no grid: idle time is not phase);
            -- the next close is a half tick (refund before reward)
            T.n = T.n + (now - T.start) // C.time.half
            T.n = T.n - T.n % 2
            T.start = now
            break
        end
        close(G, T.start + w)
    end

    -- the actor: may close the tick now
    if sign then
        T.acting[sign] = true
        if now >= T.start + wait(G) then
            close(G, now)
        end
    end

    if now > G.now then
        G.now = now
    end
end

--[[
-- Register a charged post in the current tick.
-- Inputs:
--  - G   [table]: chain state; MUTATED (tick.posts, tick.posted)
--  - cid [string]: the post, signed and charged (not a beg)
-- Outputs:
--  - none
-- Errors:
--  - none
-- Callers:
--  - apply (rules.lua): a signed post, an admitted beg
--]]
function M.tick_post (G, cid)
    local T = G.tick
    local member = G.actions[cid].member
    T.posts[#T.posts+1] = cid
    T.posted[member] = T.posted[member] or cid
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
-- Every entry records two times:
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

    -- any signed action is activity for the clock (a beg is not
    -- available to others until admitted)
    M.advance(G, act.time, (not env.beg) and env.sign or nil)

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
            action = 'post',
            member = env.sign,
            time   = { backs=math.max(act.time,up), apply=G.now },
            beg    = env.beg or nil,
            reps   = 0,
            revoke = { member=0, others=0 },
        }
        G.dirty.actions[env.cid] = true
        if env.sign then
            if env.beg then
                M.bump(G, env.sign, 0)   -- the member exists from here
            else
                -- rule 2: pays now, refunded at the next half tick;
                -- rule 1.b: first post of the full tick is the credit
                -- (a beg is not available to others: nothing yet)
                M.bump(G, env.sign, -C.reps.cost)
                M.tick_post(G, env.cid)
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
            if a and e.action=='post' and e.credit and was~=M.is_revoked(e) then
                M.bump(G, a, was and C.reps.earn or -C.reps.earn)
            end
            -- the revoked set (listings read it, not every entry)
            if G.revoked and (was ~= M.is_revoked(e)) then
                G.revoked[act.cid] = M.is_revoked(e) or nil
                G.dirty.revoked = true
            end

            if env.beg then
                e.beg = nil
                if a then
                    -- rule 2: the admitted beg pays the post cost now,
                    -- refunded at the next half tick (may go negative)
                    M.bump(G, a, -C.reps.cost)
                    M.tick_post(G, act.cid)
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
