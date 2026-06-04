local C    = require "freechains.constants"
local HERE = debug.getinfo(1, "S").source:match("@(.*/)")

local function git_config (dir)
    exec {
        cmd = "git -C " .. dir .. " config user.name  '-'",
    }
    exec {
        cmd = "git -C " .. dir .. " config user.email '-'",
    }
    exec {
        cmd = "git -C " .. dir .. " config commit.gpgsign false",
    }
    exec {
        cmd = "git -C " .. dir .. " config pull.rebase false",
    }
    exec {
        cmd = "git -C " .. dir .. " config merge.ours.driver true",
    }
    exec {
        cmd = "git -C " .. dir .. " config receive.advertisePushOptions true",
    }
end

local function pioneers (dir)
    local T = dofile(dir .. ".freechains/genesis.lua")
    if T.pioneers then
        local n = C.reps.max // #T.pioneers
        local A = {}
        for _, key in ipairs(T.pioneers) do
            A[key] = { reps = n }
        end
        local f = assert(io.open(
            dir .. ".freechains/state/authors.lua", "w"
        ), "bug found : chain add : init failed")
        f:write(serial(A))
        f:close()
    else
        local f = assert(io.open(
            dir .. ".freechains/state/authors.lua", "w"
        ), "bug found : chain add : init failed")
        f:write("return {\n}\n")
        f:close()
    end
end

local DIR = ARGS.root .. "/chains/"

if ARGS.add then
    if ARGS.alias:sub(1,1) ~= "#" then
        ERROR("chains add : invalid alias : expected '#'")
    end
    if io.open(DIR .. "/" .. ARGS.alias) then
        ERROR("chains add : alias already exists")
    end

    if ARGS.init then
        assert(ARGS.file or ARGS.inline, "bug found")

        local rand = math.random(0, 9999999999)

        if ARGS.file then
            -- existing path-based init below
        elseif ARGS.inline then
            local pub = exec { stderr=false,
                cmd = "ssh-keygen -y -f " .. ARGS.sign,
                err = "chains add : invalid sign key",
            }
            pub = assert(pub:match("^(%S+ %S+)"), "bug found")
            local T = {
                version  = VERSION,
                type     = "#",
                name     = ARGS.alias,
                pioneers = { pub },
            }
            local tmp = "/tmp/fc-inline-" .. rand .. ".lua"
            local f = io.open(tmp, "w")
            f:write(serial(T))
            f:close()
            ARGS.path = tmp
        end

        do
            local err = true
            local f = loadfile(ARGS.path)
            if f then
                local ok, ret = pcall(f)
                if ok and (type(ret) == 'table') then
                    if ret.version and ret.type and ret.name then
                        err = false
                    end
                end
            end
            if err then
                ERROR("chains add : invalid genesis")
            end
        end

        local tmp = DIR .. "/tmp-" .. rand .. "/"

        exec { stderr=false,
            cmd = "git init -b main " .. tmp,
            err = "chains add : init failed",
        }
        git_config(tmp)
        exec {
            cmd = "cp " .. HERE .. "/hooks/pre-receive " .. tmp .. "/.git/hooks/pre-receive && chmod +x " .. tmp .. "/.git/hooks/pre-receive",
        }
        exec {
            cmd = "cp -r " .. HERE .. "/skel/. " .. tmp .. "/",
        }
        do
            local f = io.open(tmp .. "/.freechains/random", "w")
            f:write(tostring(rand) .. "\n")
            f:close()
        end
        exec {
            cmd = "cp " .. ARGS.path .. " " .. tmp .. "/.freechains/genesis.lua",
        }
        pioneers(tmp .. "/")
        exec {
            cmd = "git -C " .. tmp .. " add .freechains/ .gitattributes .gitignore",
        }
        exec {
            cmd = CMD.git .. "git -C " .. tmp .. " commit -m '(empty message)'"
            .. " --trailer 'Freechains: state'",
        }

        local hash = "#" .. exec {
            cmd = "git -C " .. tmp .. " rev-parse HEAD",
        }
        local final = DIR .. "/" .. hash
        if not os.rename(tmp, final) then
            exec {
                cmd = "rm -rf " .. tmp,
            }
            ERROR("chains add : init failed")
        end
        exec {
            cmd = "git -C '" .. final .. "' config freechains.url '" .. final .. "'",
        }
        exec {
            cmd = "ln -s '" .. hash .. "/' " .. DIR .. "/" .. ARGS.alias,
        }
        print(hash)

    elseif ARGS.clone then
        exec {
            cmd = "mkdir -p " .. DIR,
            err = "chains add : clone failed",
        }
        local tmp = DIR .. "/_tmp-" .. math.random(0, 9999999999) .. "/"
        exec { stderr=false,
            cmd = "git clone " .. URL(ARGS.url, ARGS.alias) .. " " .. tmp,
            err = "chains add : clone failed",
        }
        git_config(tmp)
        exec {
            cmd = "cp " .. HERE .. "/hooks/pre-receive " .. tmp .. "/.git/hooks/pre-receive && chmod +x " .. tmp .. "/.git/hooks/pre-receive",
        }
        local hash = "#" .. exec {
            cmd = "git -C " .. tmp .. " rev-list --max-parents=0 HEAD",
        }
        local dir = DIR .. "/" .. hash .. "/"
        if not os.rename(tmp, dir) then
            exec {
                cmd = "rm -rf " .. tmp,
            }
            ERROR("chains add : clone failed")
        end
        exec {
            cmd = "git -C '" .. dir .. "' config freechains.url '" .. dir .. "'",
        }
        exec {
            cmd = "ln -s '" .. hash .. "' " .. DIR .. "/" .. ARGS.alias,
        }
        print(hash)
    end
elseif ARGS.rem then
    local alias = DIR .. "/" .. ARGS.alias
    local lnk = exec {
        cmd = "readlink " .. alias,
        err = "chains rem : invalid chain",
    }
    exec {
        cmd = "rm -rf '" .. DIR .. lnk .. "'",
    }
    os.remove(alias)
elseif ARGS.dir then
    local out = exec {
        cmd = "find " .. DIR .. " -maxdepth 1 -type l -printf '%f\\n'" .. " | sort",
    }
    io.write(out)
end
