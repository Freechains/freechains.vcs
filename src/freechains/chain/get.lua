require "freechains.chain.common"

do
    local _, code = exec(true, 'stdout',
        "git -C " .. REPO .. " merge-base --is-ancestor " .. ARGS.hash .. " HEAD"
    )
    if code ~= 0 then
        ERROR("chain get : unknown post")
    end
end

local kind = trailer(ARGS.hash)

if ARGS.payload then
    if kind ~= "post" then
        ERROR("chain get : unknown post")
    end

    local files = exec (
        "git -C " .. REPO ..
        " diff-tree --no-commit-id -r --name-only " .. ARGS.hash
    )
    local file = files:match("^(%S+)")
    local out = exec (
        "git -C " .. REPO .. " show " .. ARGS.hash .. ":" .. file
    )
    io.write(out)

elseif ARGS.block then
    if kind~="post" and kind~="like" then
        ERROR("chain get : unknown post")
    end
    ERROR("chain get : TODO block")
end
