--[[
-- `chain <alias> get payload|metadata`
-- Print one action payload bytes or metadata.
-- Inputs:
--  - ARGS.payload|ARGS.metadata [boolean]: what to print
--  - ARGS.cid [string]: the actions cid (may be short)
--  - G    [table]: state at HEAD (revocation check)
--  - REPO [string]: the chain's bare repo dir
-- Outputs:
--  - stdout: raw payload bytes, or metadata dump
-- Errors:
--  - "chain get : unknown post" : does not resolve to an action
--  - "chain get : revoked payload"
-- Callers:
--  - dispatch (chain/init.lua): ARGS.get
--]]

-- `get` is a DISK query: anything git resolves to an action is
-- readable -- parked begs, abandoned suffixes, refused syncs --
-- until `sweep` reclaims the unreferenced ones.
-- The one deny is a REVOKED payload, gated by the chain state

ARGS.cid = ACTION.full(ARGS.cid) or ERROR("chain get : unknown post")

local opt = ARGS.metadata and { sign=true, backs=true }
local T = ACTION.read(false, ARGS.cid, opt)
if not T then
    ERROR("chain get : unknown post")
end

if ARGS.payload then
    if G.actions[ARGS.cid] and RULES.is_revoked(G.actions[ARGS.cid]) then
        ERROR("chain get : revoked payload")
    end

    local pay = ""
    if T.blob then
        -- honest peer musts hold the payload
        pay = exec { trim=false,
            cmd = "git -C " .. REPO .. " cat-file blob " .. T.blob,
        }
    end

    io.write(pay)

elseif ARGS.metadata then
    local out = ARGS.cid .. "\n" ..
        "action " .. T.action .. "\n" ..
        "time " .. T.time .. "\n"
    if T.n then
        out = out .. "n " .. T.n .. "\n"
    end
    if T.cid then
        out = out .. "cid " .. T.cid .. "\n"
    elseif T.author then
        out = out .. "author " .. T.author .. "\n"
    end
    if T.blob then
        out = out .. "blob " .. T.blob .. "\n"
    end
    if T.sign then
        out = out .. "sign " .. T.sign .. "\n"
    end
    out = out .. "backs"
    for _, b in ipairs(T.backs) do
        out = out .. " " .. b
    end
    io.write(out .. "\n")
end
