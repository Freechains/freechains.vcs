--[[
-- `chains add|rem|dir`
-- Create, remove, or list root chains.
-- One bare repo per chain, alias symlinks.
-- Inputs:
--  - ARGS.add [boolean]: with ARGS.init (+ ARGS.pioneer list)
--    or ARGS.clone (+ ARGS.url)
--  - ARGS.rem [boolean]: delete repo + alias
--  - ARGS.dir [boolean]: list aliases
--  - ARGS.alias [string]: "#..." chain alias
--  - ARGS.root  [string]: freechains root dir
-- Outputs:
--  - stdout: the chain cid ("#<genesis>"), or the alias listing
--  - fs: repo dir under chains/ + alias symlink (add/rem)
-- Errors:
--  - "chains add : invalid alias : expected '#'"
--  - "chains add : alias already exists"
--  - "chains add : invalid pioneer : <v>"
--  - "chains add : git init failed" | "init failed"
--    | "clone failed" | "invalid genesis" | "too many pioneers"
--  - "chains rem : invalid chain"
-- Callers:
--  - dispatch (freechains.lua): ARGS.chains
--]]

local C    = require "freechains.constants"
local ssh  = require "freechains.chain.ssh"
local HERE = debug.getinfo(1, "S").source:match("@(.*/)")

--[[
-- Configure a fresh bare repo: identity, signing off, merge and
-- pack knobs, the pre-receive hook.
-- Inputs:
--  - dir [string]: the bare repo dir (IS the git dir)
-- Outputs:
--  - none
-- Errors:
--  - via exec: "bug found" if git config/cp fail
-- Callers:
--  - chains add init  (chains.lua): after git init
--  - chains add clone (chains.lua): after git init
--]]
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
    -- wider delta search for the near-identical state blobs: 24 vs
    -- 46 MiB at 6.5k actions; gc is manual (sweep) and rare, so the
    -- extra CPU is fine. Depth 50 (default) measured right; bitmaps
    -- (bare default) measured irrelevant (~0.7 MiB sidecar): left alone
    exec {
        cmd = "git -C " .. dir .. " config pack.window 50"
    }

    -- bare repo: the repo dir IS the git dir
    exec {
        cmd = "cp " .. HERE .. "/hooks/pre-receive " .. dir .. "/hooks/pre-receive"
    }
    exec {
        cmd = "chmod +x " .. dir .. "/hooks/pre-receive"
    }
end

--[[
-- The pioneers' initial reps.
-- C.reps.max split evenly, parsed from the genesis commit MESSAGE.
-- May come from a REMOTE peer on clone, so parsed by match, never load.
-- Inputs:
--  - dir [string]: the bare repo dir
--  - gen [string]: the genesis cid
-- Outputs:
--  - [table]: authors (pubkey -> { reps = n })
-- Errors:
--  - ERROR "chains add : invalid genesis" : message no-parse
--  - ERROR "chains add : too many pioneers" : split under cost
-- Callers:
--  - genesis (chains.lua): the genesis snapshot's authors
--]]
local function pioneers (dir, gen)
    -- the genesis table IS the genesis commit MESSAGE (body after
    -- the header block). It may come from a REMOTE peer (clone), so
    -- it is loaded as DATA: "t" text only, {} no globals (T6c)
    local src = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. dir .. " cat-file commit " .. gen,
    }
    src = src and src:match("\n\n(.*)$")
    if not src then
        ERROR("chains add : invalid genesis")
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

--[[
-- The genesis snapshot: a blob pinned by refs/states/<gen>.
-- Same store as STATE.write; inlined, no chain context here.
-- Inputs:
--  - dir [string]: the bare repo dir
--  - gen [string]: the genesis cid
-- Outputs:
--  - none
-- Errors:
--  - via exec/pioneers: see above
-- Callers:
--  - chains add init  (chains.lua): after the genesis commit
--  - chains add clone (chains.lua): before the first recv
--]]
-- `now` = 0: dates are neutral, so creator and cloner agree byte
-- for byte
local function genesis (dir, gen)
    local G = {
        authors = pioneers(dir, gen),
        actions = {},
        order   = {},
        now     = 0,
    }
    local tmp = dir .. "state-tmp"
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
            local key = ssh.pub.any(v)
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
            nonce    = rand,
            pioneers = pios,
        }

        local tmp = DIR .. "/tmp-" .. rand .. "/"

        exec {
            cmd = "git init --bare -b main " .. tmp,
            err = "chains add : git init failed",
        }
        git_init(tmp)

        -- genesis commit: EMPTY tree, the genesis table IS the
        -- message. `nonce` salts the hash (dates are neutral, so
        -- equal pioneers would otherwise collide into one chain id)
        local tree = exec {
            cmd = "git -C " .. tmp .. " hash-object -t tree /dev/null",
        }
        do
            local f = io.open(tmp .. "genesis-tmp", "w")
            f:write(serial(GEN))
            f:close()
        end
        local gen = exec {
            cmd = CMD.git .. "git -C " .. tmp .. " commit-tree " .. tree ..
                " < " .. tmp .. "genesis-tmp",
        }
        os.remove(tmp .. "genesis-tmp")
        exec {
            cmd = "git -C " .. tmp .. " update-ref HEAD " .. gen,
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
            cmd = "git init --bare -b main " .. tmp,
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
            cmd = "git -C " .. tmp .. " update-ref HEAD " .. gen,
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
