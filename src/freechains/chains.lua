local C    = require "freechains.constants"
local SKEL = debug.getinfo(1, "S").source:match("@(.*/)")  .. "skel/"

local function git_config (dir)
    exec("git -C " .. dir .. " config user.name  '-'")
    exec("git -C " .. dir .. " config user.email '-'")
    exec("git -C " .. dir .. " config commit.gpgsign false")
    exec("git -C " .. dir .. " config pull.rebase false")
    exec("git -C " .. dir .. " config merge.ours.driver true")
end

local function pioneers (dir)
    local T = dofile(dir .. ".freechains/genesis.lua")
    if T.pioneers then
        local n = C.reps.max // #T.pioneers
        local A = {}
        for _, p in ipairs(T.pioneers) do
            A[p.key] = { reps = n }
            if p.type == "gpg" then
                local f = io.open(dir .. ".freechains/keys/" .. p.key .. ".asc", "w")
                f:write("-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n")
                f:write(p.base64 .. "\n")
                f:write("-----END PGP PUBLIC KEY BLOCK-----\n")
                f:close()
            elseif p.type == "ssh" then
                local f = io.open(dir .. ".freechains/keys/allowed_signers", "a")
                f:write(p.name .. " " .. p.key .. "\n")
                f:close()
            else
                ERROR("chains add : unknown key type: " .. tostring(p.type))
            end
        end
        local f = io.open(
            dir .. ".freechains/state/authors.lua", "w"
        )
        f:write(serial(A))
        f:close()
    else
        local f = io.open(
            dir .. ".freechains/state/authors.lua", "w"
        )
        f:write("return {\n}\n")
        f:close()
    end
end

local DIR = ARGS.root .. "/chains/"

if ARGS.add then
    if io.open(DIR .. "/" .. ARGS.alias) then
        ERROR("chains add : alias already exists: " .. ARGS.alias)
    end

    if ARGS.init then
        local genesis = dofile(ARGS.path)
        if type(genesis) ~= "table" then
            -- TODO: check format
            ERROR("chains add : file must return a table")
        end

        local rand = math.random(0, 9999999999)
        local tmp
        while true do
            tmp = DIR .. "/tmp-" .. rand .. "/"
            if not io.open(tmp .. ".") then
                break
            end
            rand = math.random(0, 9999999999)
        end

        exec (
            "git init -b main " .. tmp
            , "chains add : git init failed"
        )
        git_config(tmp)
        exec ("cp -r " .. SKEL .. ". " .. tmp .. "/")
        do
            local f = io.open(tmp .. "/.freechains/random", "w")
            f:write(tostring(rand) .. "\n")
            f:close()
        end
        exec (
            "cp " .. ARGS.path .. " " .. tmp .. "/.freechains/genesis.lua"
            , "chains add : copy genesis failed"
        )
        pioneers(tmp .. "/")
        exec (
            "git -C " .. tmp .. " add .freechains/ .gitattributes"
        )
        exec (
            CMD.git .. "git -C " .. tmp .. " commit -m '(empty message)'"
            .. " --trailer 'Freechains: state'"
        )

        local hash = exec (
            "git -C " .. tmp .. " rev-parse HEAD"
        )
        local final = DIR .. "/" .. hash
        if not os.rename(tmp, final) then
            exec("rm -rf " .. tmp)
            ERROR("chains add : chain already exists: " .. hash)
        end
        exec (
            "ln -s " .. hash .. "/ " .. DIR .. "/" .. ARGS.alias
        )
        print(hash)

    elseif ARGS.clone then
        exec("mkdir -p " .. DIR)
        local tmp = DIR .. "/" .. "_tmp" .. "/"
        exec (
            "git clone " .. ARGS.url .. " " .. tmp
            , "chains add : git clone failed"
        )
        git_config(tmp)
        local hash = exec (
            "git -C " .. tmp .. " rev-list --max-parents=0 HEAD"
        )
        local dir = DIR .. "/" .. hash .. "/"
        exec("mv " .. tmp .. " " .. dir)
        exec("ln -s " .. hash .. " " .. DIR .. "/" .. ARGS.alias)
        print(hash)
    end
elseif ARGS.rem then
    local alias = DIR .. "/" .. ARGS.alias
    local lnk = exec (
        "readlink " .. alias
        , "chains rem : not found: " .. ARGS.alias
    )
    exec ("rm -rf " .. DIR .. lnk)
    os.remove(alias)
elseif ARGS.dir then
    local out = exec (
        "find " .. DIR .. " -maxdepth 1 -type l -printf '%f\\n'" .. " | sort"
    )
    io.write(out)
end
