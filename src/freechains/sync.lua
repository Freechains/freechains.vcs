local REPO = ARGS.root .. "/chains/" .. ARGS.alias .. "/"

if ARGS.recv then
    exec (
        "git -C " .. REPO .. " fetch " .. ARGS.remote .. " main"
        , "chain sync : fetch failed"
    )

    local head = exec("git -C " .. REPO .. " rev-parse HEAD")
    local fetch = exec("git -C " .. REPO .. " rev-parse FETCH_HEAD")

    if head ~= fetch then
        exec (
            "git -C " .. REPO .. " merge --no-edit FETCH_HEAD"
            , "chain sync : merge failed"
        )
    end
elseif ARGS.send then
    exec("git -C " .. REPO .. " add .freechains/authors.lua .freechains/posts.lua")
    local _, code = exec(true, "git -C " .. REPO .. " diff --cached --quiet")
    if code ~= 0 then
        exec(NOW.git .. "git -C " .. REPO .. " commit --allow-empty-message --trailer 'freechains: state' -m ''")
    end
    exec (
        "git -C " .. REPO .. " push " .. ARGS.remote .. " main"
        , "chain sync : push failed"
    )
end
