math.randomseed()

local SKEL = debug.getinfo(1, "S").source:match("@(.*/)")  .. "skel/"

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
        exec (true,
            "cp -r " .. SKEL .. ". " .. tmp .. "/"
        )
        do
            local f = io.open(tmp .. "/.freechains/random", "w")
            f:write(tostring(rand) .. "\n")
            f:close()
        end
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
