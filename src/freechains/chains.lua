local C    = require "freechains.constants"
local HERE = debug.getinfo(1, "S").source:match("@(.*/)")

local function git_init (dir)
    exec {
        cmd = "git -C " .. dir .. " config user.name  '-'"
    }
    exec {
        cmd = "git -C " .. dir .. " config user.email '-'"
    }
    exec {
        cmd = "git -C " .. dir .. " config commit.gpgsign false"
    }
    exec {
        cmd = "git -C " .. dir .. " config pull.rebase false"
    }
    exec {
        cmd = "git -C " .. dir .. " config merge.ours.driver true"
    }
    exec {
        cmd = "git -C " .. dir .. " config receive.advertisePushOptions true"
    }

    exec {
        cmd = "mkdir -p " .. dir .. "/.git/states/"
    }
    exec {
        cmd = "cp " .. HERE .. "/hooks/pre-receive " .. dir .. "/.git/hooks/pre-receive"
    }
    exec {
        cmd = "chmod +x " .. dir .. "/.git/hooks/pre-receive"
    }
end

-- chain starts with max split among pioneers
local function pioneers (dir)
    local T = dofile(dir .. "genesis.lua")
    local A = {}
    if T.pioneers then
        local n = C.reps.max // #T.pioneers
        if n < C.reps.cost then
            ERROR("chains add : too many pioneers")
        end
        for _, key in ipairs(T.pioneers) do
            A[key] = { reps = n }
        end
    end
    return A
end

-- genesis snapshot: direct write (no chain context here); `now` =
-- 0: dates are neutral, so creator and cloner agree byte for byte
local function genesis (dir, gen)
    local G = {
        authors = pioneers(dir),
        actions = {},
        order   = {},
        now     = 0,
    }
    local f = io.open(dir .. ".git/states/" .. gen .. ".lua", "w")
    f:write(serial(G))
    f:close()
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
            local pub = exec {
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

        exec {
            cmd = "git init -b main " .. tmp,
        }
        git_init(tmp)
        do
            local f = io.open(tmp .. "/random", "w")
            f:write(tostring(rand) .. "\n")
            f:close()
        end
        exec {
            cmd = "cp " .. ARGS.path .. " " .. tmp .. "/genesis.lua",
        }
        exec {
            cmd = "git -C " .. tmp .. " add .",
        }
        exec {
            cmd = CMD.git .. "git -C " .. tmp .. " commit --allow-empty-message -m ''",
        }

        local gen = exec {
            cmd = "git -C " .. tmp .. " rev-parse HEAD",
        }

        -- genesis ref: remote clone without whole history
        exec {
            cmd = "git -C " .. tmp .. " update-ref refs/genesis " .. gen,
        }

        genesis(tmp, gen)

        local hash = "#" .. gen
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
        -- clone genesis alone: everything else comes later through `recv`
        -- clone = base case of recv: keep the genesis commit only,
        -- snapshot it, then let `sync recv` validate the rest.
        -- On failure the clone is deleted whole
        exec {
            cmd = "mkdir -p " .. DIR,
        }
        local tmp = DIR .. "/_tmp-" .. math.random(0, 9999999999) .. "/"
        exec {
            cmd = "git init -b main " .. tmp,
        }
        git_init(tmp)
        exec {
            cmd = "git -C " .. tmp .. " fetch " .. URL(ARGS.url, ARGS.alias) ..
                " refs/genesis:refs/genesis",
            err = "chains add : clone failed",
        }
        local gen = exec {
            cmd = "git -C " .. tmp .. " rev-parse refs/genesis",
        }
        exec {
            cmd = "git -C " .. tmp .. " reset --hard " .. gen,
        }
        local hash = "#" .. gen
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

        genesis(dir, gen)

        -- re-exec myself: `recv` binds REPO from its own ARGS
        local ok, _, out = exec { err=false,
            cmd = arg[0] .. " --root='" .. ARGS.root .. "'"
                .. " chain '" .. ARGS.alias .. "'"
                .. " sync recv '" .. ARGS.url .. "'",
        }
        if not ok then
            os.remove(DIR .. "/" .. ARGS.alias)
            exec {
                cmd = "rm -rf '" .. dir .. "'",
            }
            ERROR("chains add : clone failed", out)
        end

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
