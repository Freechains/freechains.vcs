--[[
-- `chain <alias> reps <target> [key]`
-- Print reputation queries.
-- Fold time up to --now (discounts/consolidation)
-- Inputs:
--  - ARGS.target [string]: action|actions|revoke|revokes|member|members
--  - ARGS.key [string?]: action cid or member key (single forms)
--  - ARGS.now [integer]: query time (drives `advance`)
--  - G [table]: state at HEAD; mutated in memory only
-- Outputs:
--  - stdout: reps value(s), or revoke channel sums
-- Errors:
--  - "chain reps : action requires id" (also revoke/member)
--  - "chain reps : invalid target : <target>"
-- Callers:
--  - dispatch (chain/init.lua): ARGS.reps
--]]

if ARGS.key then
    ARGS.key = ARGS.key:match("^%s*(.-)%s*$")
    -- member key: string or key file (cli.md "Keys:")
    if ARGS.target == "member" then
        ARGS.key = SSH.pub(ARGS.key) or ARGS.key
    elseif (ARGS.target == "action") or (ARGS.target == "revoke") then
        ARGS.key = ACTION.full(ARGS.key) or ARGS.key
    end
end

RULES.advance(G, ARGS.now)
RULES.cap(G)

if ARGS.target == "action" then
    if not ARGS.key then
        ERROR("chain reps : action requires id")
    end
    local e = G.actions[ARGS.key]
    local v = (e and e.reps) or 0
    print(v)
elseif ARGS.target == "actions" then
    local T = {}
    for k, v in pairs(G.actions) do
        T[#T+1] = { k=k, v=v.reps }
    end
    table.sort(T, function (a, b) return a.v > b.v end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. e.v)
    end

elseif ARGS.target == "revoke" then
    -- the axis is per ACTION (post or vote), so no target argument
    if not ARGS.key then
        ERROR("chain reps : revoke requires id")
    end
    local e = G.actions[ARGS.key]
    local r = (e and e.revoke) or { member=0, others=0 }
    print(r.member .. " " .. r.others)
elseif ARGS.target == "revokes" then
    -- both revoke channels of every action, most revoked first
    local T = {}
    for k, v in pairs(G.actions) do
        local r = v.revoke or { member=0, others=0 }
        T[#T+1] = { k=k, a=r.member, o=r.others }
    end
    table.sort(T, function (x, y)
        if x.o ~= y.o then
            return x.o < y.o
        else
            return x.a < y.a
        end
    end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. e.a .. " " .. e.o)
    end

elseif ARGS.target == "member" then
    if not ARGS.key then
        ERROR("chain reps : member requires a pubkey")
    end
    local e = G.members[ARGS.key]
    local v = (e and e.reps) or 0
    print(v)
elseif ARGS.target == "members" then
    local T = {}
    for k, v in pairs(G.members) do
        T[#T+1] = { k=k, v=v.reps }
    end
    table.sort(T, function (a, b) return a.v > b.v end)
    for _, e in ipairs(T) do
        print(e.k .. " " .. e.v)
    end

else
    ERROR("chain reps : invalid target : " .. ARGS.target)
end
