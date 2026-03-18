math.randomseed()

local C    = require "freechains.constants"

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
        git_init(tmp, rand, ARGS.path)
        exec (
            "git -C " .. tmp .. " add .freechains/"
        )

        exec (
            NOW.git .. "git -C " .. tmp .. ' commit --allow-empty-message -m ""'
        )

        local hash = exec (
            "git -C " .. tmp .. " rev-parse HEAD"
        )

        local final = chains .. "/" .. hash
        if not os.rename(tmp, final) then
            exec("rm -rf " .. tmp)
            ERROR("chains add : chain already exists: " .. hash)
        end
        exec (
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
    exec (
        "rm -rf " .. chains .. lnk
    )
    os.remove(alias)
elseif ARGS.dir then
    local out = exec (
        "find " .. chains .. " -maxdepth 1 -type l -printf '%f\\n' | sort"
    )
    io.write(out)
end
