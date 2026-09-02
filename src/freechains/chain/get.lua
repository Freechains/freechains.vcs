--[[
-- `chain <alias> get payload|metadata`
-- Print one action payload bytes or metadata.
-- Inputs:
--  - ARGS.payload|ARGS.metadata [boolean]: what to print
--  - ARGS.cid [string]: the actions cid (may be short)
--  - G    [table]: state at HEAD (revocation check)
--  - REPO [string]: the chain's bare repo dir
-- Outputs:
--  - stdout: raw payload bytes, or a `return {...}` table
--    (metadata; the id `genesis` yields the genesis table)
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

if ARGS.metadata and ARGS.cid==GIT.deref("refs/genesis") then
    local src = exec { trim=false,
        cmd = "git -C " .. REPO .. " cat-file commit " .. ARGS.cid,
    }
    local ls = {}
    for l in src:match("\n\n(.*)$"):gmatch("[^\n]+") do
        ls[#ls+1] = l
    end
    local T = {
        version   = ls[1],
        nonce     = tonumber(ls[2]),
        dictators = {},
        pioneers  = {},
    }
    local cur = T.dictators
    for i=4, #ls do
        if ls[i] == "pioneers:" then
            cur = T.pioneers
        else
            cur[#cur+1] = ls[i]
        end
    end
    T.open = (#T.dictators==0 and #T.pioneers==0)
    print("return " .. table_to_string(T))

else
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
        print("return " .. table_to_string(T))
    end
end
