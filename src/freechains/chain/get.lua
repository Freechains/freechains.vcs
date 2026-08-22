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
--  - "chain get : unknown post" : not in HEAD's history
--  - "chain get : revoked payload"
-- Callers:
--  - dispatch (chain/init.lua): ARGS.get
--]]

-- membership: an action of the CURRENT history <=> its commit is
-- an ancestor of HEAD (the cid IS the commit); `abandon` drops exactly the
-- abandoned suffix. A parked beg is outside HEAD: unknown here
local T
do
    ARGS.cid = ACTION.full(ARGS.cid) or ERROR("chain get : unknown post")
    local ok = exec { err=false, stderr=false,
        cmd = "git -C " .. REPO .. " merge-base --is-ancestor " ..
            ARGS.cid .. " HEAD",
    }
    if ok then
        local opt = ARGS.metadata and { sign=true, backs=true }
        T = ACTION.read(false, ARGS.cid, opt)
    end
    if not T then
        ERROR("chain get : unknown post")
    end
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
