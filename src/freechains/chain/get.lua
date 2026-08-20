
-- membership: an action of the CURRENT history <=> its file is
-- in HEAD's tree: files only ever accumulate, and `abandon`'s
-- reset drops exactly the abandoned ones. One cat-file -- and
-- it doubles as the read
local src
do
    ARGS.aid = ACTION.full(ARGS.aid)
    src = ARGS.aid:match("^%x+$") and
        exec { trim=false, err=false, stderr=false,
            cmd = "git -C " .. REPO .. " cat-file blob" ..
                " 'HEAD:" .. ACTION.path(ARGS.aid) .. "'",
        }
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
    -- the metadata IS the action file (serialized Lua)
    io.write(src)
end
