require "freechains.chain.common"

-- membership: an action of the CURRENT history <=> its file is
-- in HEAD's tree (mirrored by the worktree): files only ever
-- accumulate, and `abandon`'s reset drops exactly the abandoned
-- ones. One io.open, no git -- and it doubles as the read
local src
do
    ARGS.aid = ACTION.full(ARGS.aid)
    local f = ARGS.aid:match("^%x+$") and
        io.open(REPO .. ACTION.path(ARGS.aid))
    if not f then
        ERROR("chain get : unknown post")
    end
    src = f:read("a")
    f:close()
end

if ARGS.payload then
    if G.actions[ARGS.aid] and is_revoked(G.actions[ARGS.aid]) then
        ERROR("chain get : revoked payload")
    end

    local T = assert(load(src))()

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
