
-- membership: an action of the CURRENT history <=> its commit is
-- an ancestor of HEAD (aid == cid); `abandon` drops exactly the
-- abandoned suffix. A parked beg is outside HEAD: unknown here
local src
do
    ARGS.aid = ACTION.full(ARGS.aid)
    local ok = ARGS.aid:match("^%x+$")
        and ACTION.aid(ARGS.aid)      -- an action (not merge/genesis)
        and exec { err=false, stderr=false,
            cmd = "git -C " .. REPO .. " merge-base --is-ancestor " ..
                ARGS.aid .. " HEAD",
        }
    if ok then
        local out = exec { trim=false,
            cmd = "git -C " .. REPO .. " cat-file commit " .. ARGS.aid,
        }
        src = out:match("\n\n(.*)$")
    end
    if not src then
        ERROR("chain get : unknown post")
    end
end

if ARGS.payload then
    if G.actions[ARGS.aid] and is_revoked(G.actions[ARGS.aid]) then
        ERROR("chain get : revoked payload")
    end

    local T = assert(load(src, "=action", "t", {}))()

    local pay = ""
    if T.blob then
        -- honest peer musts hold the payload
        pay = exec { trim=false,
            cmd = "git -C " .. REPO .. " cat-file blob " .. T.blob,
        }
    end

    io.write(pay)

elseif ARGS.metadata then
    -- the metadata IS the action message (serialized Lua)
    io.write(src)
end
