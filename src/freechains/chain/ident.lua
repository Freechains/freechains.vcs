do
    if G.authors[ARGS.sign] then
        ERROR("chain ident : already registered")   -- TODO: untested
    end

    do
        local _,code = exec (true,
            "git -C " .. REPO .. " rev-parse --verify refs/idents/ident-" .. ARGS.sign
        )
        if code == 0 then
            ERROR("chain ident : already registered")
        end
    end
end

-- export pubkey + write .asc
do
    local armor = exec ('stdout',
        "gpg --export --armor " .. ARGS.sign    -- never fails
    )
    if armor == "" then
        ERROR("chain ident : invalid sign key")
    end
    local f = io.open(FC .. "state/keys/" .. ARGS.sign .. ".asc", "w")
    f:write(armor)
    f:close()
end

-- optional bio
if ARGS.bio then
    exec ('stdout',
        "cp " .. ARGS.bio .. " " .. FC .. "idents/" .. ARGS.sign .. ".md"
        , "chain ident : invalid bio : " .. ARGS.bio
    )
end

-- commit ident (signed)
local hash
do
    exec (
        "git -C " .. REPO .. " add .freechains/state/keys/ .freechains/idents/"
    )
    local s1 = " -c user.signingkey=" .. ARGS.sign .. " -c gpg.format=openpgp"
    local msg = ARGS.why or "(empty message)"
    exec ('stdout',
        CMD.git .. "git -C " .. REPO .. s1 .. " commit -S -m '" .. msg ..
            "' --trailer 'Freechains: ident'"
        , "chain ident : invalid sign key"
    )
    hash = exec (
        "git -C " .. REPO .. " rev-parse HEAD"
    )
end

-- apply
do
    local T = {
        sign = ARGS.sign,
    }
    local ok, err = apply(G, 'ident', CMD.now, T)
    if not ok then
        exec("git -C " .. REPO .. " reset --hard HEAD~1")
        ERROR("chain ident : " .. err)
    end
end

-- commit state
do
    write(G)
    exec (
        "git -C " .. REPO .. " add .freechains/state/"
    )
    exec (
        CMD.git .. "git -C " .. REPO .. " commit -m '(empty message)'"
        .. " --trailer 'Freechains: state'"
    )
end

-- create ident ref + reset HEAD
do
    exec (
        "git -C " .. REPO .. " update-ref refs/idents/ident-" .. ARGS.sign .. " HEAD"
    )
    exec (
        "git -C " .. REPO .. " reset --hard HEAD~2"
    )
end

print(hash)
