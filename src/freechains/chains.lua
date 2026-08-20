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
        cmd = "cp " .. HERE .. "/hooks/pre-receive " .. dir .. "/.git/hooks/pre-receive"
    }
    exec {
        cmd = "chmod +x " .. dir .. "/.git/hooks/pre-receive"
    }
end

-- chain starts with max split among pioneers
local function pioneers (dir)
    -- the genesis may come from a REMOTE peer (clone), so it is
    -- loaded as DATA: "t" text only, {} no globals (T6c)
    local src
    do
        local f = io.open(dir .. "genesis.lua")
        if not f then
            ERROR("chains add : invalid genesis")
        end
        src = f:read("a")
        f:close()
    end
    local T = load(src, "=genesis", "t", {})
    local ok
    if T then
        ok, T = pcall(T)
    end
    if not (ok and type(T) == 'table') then
        ERROR("chains add : invalid genesis")
    end
    local A = {}
    if T.pioneers and #T.pioneers>0 then
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

-- genesis snapshot: stored as a git blob pinned by refs/states/<gen>
-- (same store as STATE.write; inlined, no chain context here).
-- `now` = 0: dates are neutral, so creator and cloner agree byte
-- for byte
local function genesis (dir, gen)
    local G = {
        authors = pioneers(dir),
        actions = {},
        order   = {},
        now     = 0,
    }
    local tmp = dir .. ".git/state-tmp"
    local f = io.open(tmp, "w")
    f:write(serial(G))
    f:close()
    local blob = exec {
        cmd = "git -C " .. dir .. " hash-object -w " .. tmp,
    }
    exec {
        cmd = "git -C " .. dir .. " update-ref refs/states/" .. gen .. " " .. blob,
    }
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
        local rand = math.random(0, 9999999999)

        -- each --pioneer is a key string ("ssh-...") or a key file
        local keys = {}
        for _, v in ipairs(ARGS.pioneer or {}) do
            local key
            if v:match("^ssh%-") then
                key = v
            else
                local f = io.open(v)
                local ln = f and f:read("l")
                if f then
                    f:close()
                end
                if ln and ln:match("^ssh%-") then
                    key = ln          -- public key file
                else
                    key = exec {      -- private key file
                        cmd = "ssh-keygen -y -f " .. v,
                        err = "chains add : invalid pioneer",
                    }
                end
            end
            key = key:match("^(%S+ %S+)")
            if not key then
                ERROR("chains add : invalid pioneer : " .. v)
            end
            keys[key] = true
        end

        local pios = {}
        for key in pairs(keys) do
            pios[#pios+1] = key
        end
        local GEN = {
            version  = VERSION,
            pioneers = pios,
        }

        local tmp = DIR .. "/tmp-" .. rand .. "/"

        exec {
            cmd = "git init -b main " .. tmp,
            err = "chains add : git init failed",
        }
        git_init(tmp)
        do
            local f = io.open(tmp .. "/random", "w")
            f:write(tostring(rand) .. "\n")
            f:close()
        end
        do
            local f = io.open(tmp .. "/genesis.lua", "w")
            f:write(serial(GEN))
            f:close()
        end
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

        local id = "#" .. gen
        local final = DIR .. "/" .. id
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
            cmd = "ln -s '" .. id .. "/' " .. DIR .. "/" .. ARGS.alias,
        }
        print(id)

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
            err = "chains add : clone failed",
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
        local id = "#" .. gen
        local dir = DIR .. "/" .. id .. "/"
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
            cmd = "ln -s '" .. id .. "' " .. DIR .. "/" .. ARGS.alias,
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

        print(id)
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
