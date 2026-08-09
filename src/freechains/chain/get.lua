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
    if G.posts[ARGS.aid] and is_revoked(G.posts[ARGS.aid]) then
        ERROR("chain get : revoked post")
    end

    local T = assert(load(src))()

    local pay = ""
    if T.blob then
        pay = exec { trim=false,
            cmd = "git -C " .. REPO .. " cat-file blob " .. T.blob,
        }
    end

    io.write(pay)

elseif ARGS.metadata then
    -- the metadata IS the action file (serialized Lua)
    io.write(src)
end
