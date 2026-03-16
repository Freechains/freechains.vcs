math.randomseed()

-- .freechains/
--   random              -- chain identity seed
--   genesis.lua         -- chain type, parameters
--   likes/              -- like/dislike payload files
--   reps/
--     authors.lua       -- pubkey → internal reputation
--     posts.lua         -- commit hash → internal reputation
--   time/
--     authors.lua       -- pubkey → last consolidation timestamp
--     posts.lua         -- entries in 00-12h or 12-24h
--   local/              -- untracked local state
--     now.lua           -- last staged timestamp
local function skel (rand, path)
    local function empty (file)
        local f = io.open(path .. "/.freechains/" .. file, "w")
        f:write("return {}\n")
        f:close()
    end
    exec (true,
        "mkdir -p " .. path .. "/.freechains/likes"
    )
    exec (true,
        "mkdir -p " .. path .. "/.freechains/reps"
    )
    exec (true,
        "mkdir -p " .. path .. "/.freechains/time"
    )
    exec (true,
        "mkdir -p " .. path .. "/.freechains/local"
    )
    do
        local f = io.open(path .. "/.freechains/random", "w")
        f:write(tostring(rand) .. "\n")
        f:close()
    end
    do
        local f = io.open(path .. "/.freechains/likes/.gitkeep", "w")
        f:close()
    end
    empty("reps/authors.lua")
    empty("reps/posts.lua")
    empty("time/authors.lua")
    empty("time/posts.lua")
    do
        local f = io.open(path .. "/.freechains/local/now.lua", "w")
        f:write("return 0\n")
        f:close()
    end
    do
        local f = io.open(path .. "/.git/info/exclude", "a")
        f:write(".freechains/local/\n")
        f:close()
    end
end

local chains = ARGS.root .. "/chains/"
if ARGS.add then
    if ARGS.dir then
        local genesis = dofile(ARGS.path .. "/genesis.lua")
        if type(genesis) ~= "table" then
            ERROR("chains add : file must return a table")
        end

        if io.open(chains.."/"..ARGS.alias) then
            ERROR("chains add : alias already exists: " .. ARGS.alias)
        end

        local rand = math.random(0, math.maxinteger)
        local tmp
        while true do
            tmp = chains .. "/tmp-" .. rand .. "/"
            if not io.open(tmp .. ".") then
                break
            end
            rand = math.random(0, math.maxinteger)
        end

        exec (
            "git init " .. tmp
            , "chains add : git init failed"
        )
        git_config(tmp)
        skel(rand, tmp)
        exec (
            "cp -r " .. ARGS.path .. "/* " .. tmp .. "/.freechains/"
            , "chains add : copy genesis failed"
        )
        exec (true,
            "git -C " .. tmp .. " add .freechains/"
        )

        exec (true,
            NOW.git .. "git -C " .. tmp .. ' commit --allow-empty-message -m ""'
        )

        local hash = exec (true,
            "git -C " .. tmp .. " rev-parse HEAD"
        )

        local final = chains .. "/" .. hash
        if not os.rename(tmp, final) then
            exec(true, "rm -rf " .. tmp)
            ERROR("chains add : chain already exists: " .. hash)
        end
        exec (true,
            "ln -s " .. hash .. "/ " .. chains .. "/" .. ARGS.alias
        )

        print(hash)
    end
elseif ARGS.rem then
    local alias = chains .. "/" .. ARGS.alias
    local lnk = exec (
        "readlink " .. alias
        , "chains rem : not found: " .. ARGS.alias
    )
    exec (true,
        "rm -rf " .. chains .. lnk
    )
    os.remove(alias)
elseif ARGS.dir then
    local out = exec (true,
        "find " .. chains .. " -maxdepth 1 -type l -printf '%f\\n' | sort"
    )
    io.write(out)
end
