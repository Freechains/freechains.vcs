require "freechains.chain.common"

-- membership: an action of the CURRENT history <=> its file is
-- in HEAD's tree (mirrored by the worktree): files only ever
-- accumulate, and `destroy`'s reset drops exactly the destroyed
-- ones. One io.open, no git -- and it doubles as the read
local src
do
    local f = ARGS.aid:match("^%x+$") and
        io.open(REPO .. ACTION.path(ARGS.aid))
    if not f then
        ERROR("chain get : unknown post")
    end
    src = f:read("a")
    f:close()
end

if ARGS.payload then
    local T = assert(load(src))()
    -- a post always has a payload; a vote only with `--why`
    if not T.blob then
        ERROR("chain get : no payload")
    end

    if G.posts[ARGS.aid] and is_revoked(G.posts[ARGS.aid]) then
        ERROR("chain get : revoked post")
    end

    -- the payload is the blob the action file pins: never in a
    -- tree, anchored by refs/payloads/<aid>
    io.write((exec { trim=false,
        cmd = "git -C " .. REPO .. " cat-file blob " .. T.blob,
    }))

elseif ARGS.metadata then
    -- the metadata IS the action file (serialized Lua)
    io.write(src)
end
