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
    exec (
        "git -C " .. REPO .. " push " .. ARGS.remote .. " main"
        , "chain sync : push failed"
    )
end
