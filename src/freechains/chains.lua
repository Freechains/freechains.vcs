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
-- The genesis snapshot: a blob pinned by refs/states/<gen>.
-- Parses the pioneers from the genesis commit MESSAGE and splits
-- C.reps.max evenly among them.
-- Same store as STATE.write; inlined, no chain context here.
-- Inputs:
--  - dir [string]: the bare repo dir
--  - gen [string]: the genesis cid
-- Outputs:
--  - none
-- Errors:
--  - "chains add : invalid genesis : expected commit"
--  - "chains add : invalid genesis : expected version"
--  - "chains add : invalid genesis : expected nonce"
--  - "chains add : invalid genesis : invalid pioneer"
--  - "chains add : invalid genesis : too many pioneers"
--  - via exec: "bug found" on hash-object/update-ref
-- Callers:
--  - chains add init  (chains.lua): after the genesis commit
--  - chains add clone (chains.lua): before the first recv
--]]
-- `now` = 0: dates are neutral, so creator and cloner agree byte
-- for byte
local function genesis (dir, gen)
    -- the genesis commit MESSAGE, POSITIONAL (may come from a
    -- REMOTE peer on clone, so parsed by match, never load):
    --   <version>\n<nonce>\n<pioneer pubkey>...
    -- `src` is false when refs/genesis is not a commit (clone);
    -- for a commit, the "\n\n" separator is ALWAYS present
    local src = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. dir .. " cat-file commit " .. gen,
    }
    if not src then
        ERROR("chains add : invalid genesis : expected commit")
    end

    src = src:match("\n\n(.*)$")

    local ls = {}
    for l in src:gmatch("[^\n]+") do
        ls[#ls+1] = l
    end

    if not (ls[1] and ls[1]:match("^%d+%.%d+%.%d+$")) then
        ERROR("chains add : invalid genesis : expected version")
    end
    if not (ls[2] and ls[2]:match("^%d+$")) then
        ERROR("chains add : invalid genesis : expected nonce")
    end

    local pios = {}
    for i=3, #ls do
        local key = ls[i]:match("^(ssh%-%S+ %S+)$")
        if not key then
            ERROR("chains add : invalid genesis : invalid pioneer")
        end
        pios[#pios+1] = key
    end

    -- chain starts with max split among pioneers
    local A = {}
    if #pios > 0 then
        local n = C.reps.max // #pios
        if n < C.reps.cost then
            ERROR("chains add : invalid genesis : too many pioneers")
        end
        for _, key in ipairs(pios) do
            A[key] = { reps = n }
        end
    end

    local G = {
        authors = A,
        actions = {},
        order   = {},
        now     = 0,
    }
    local tmp = dir .. "state-tmp"
    table_to_file(G, tmp)
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
        table.sort(pios)

        -- genesis message, POSITIONAL (see `genesis` above)
        local GEN = table.concat(VERSION, ".") .. "\n" ..
            rand .. "\n"
        for _, key in ipairs(pios) do
            GEN = GEN .. key .. "\n"
        end

        local tmp = DIR .. "/tmp-" .. rand .. "/"

        exec {
            cmd = "git init --bare -b main " .. tmp,
            err = "chains add : git init failed",
        }
        git_init(tmp)

        -- genesis commit: EMPTY tree, the genesis IS the message.
        -- `nonce` salts the hash (dates are neutral, so equal
        -- pioneers would otherwise collide into one chain cid).
        local tree = exec {
            cmd = "git -C " .. tmp .. " hash-object -t tree /dev/null",
        }
        -- the message is piped VERBATIM (printf, as GIT.commit);
        -- single quotes are safe: version, nonce and base64 keys
        local gen = exec {
            -- @0: creator and cloner agree byte for byte
            cmd = "printf '%s' '" .. GEN .. "' | " ..
                "GIT_AUTHOR_DATE='@0 +0000' GIT_COMMITTER_DATE='@0 +0000' " ..
                "git -C " .. tmp .. " commit-tree " .. tree,
        }
        exec {
            cmd = "git -C " .. tmp .. " update-ref HEAD " .. gen,
        }

        -- genesis ref: remote clone without whole history
        exec {
            cmd = "git -C " .. tmp .. " update-ref refs/genesis " .. gen,
        }

        genesis(tmp, gen)

        local cid = "#" .. gen
        local final = DIR .. "/" .. cid
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
            cmd = "ln -s '" .. cid .. "/' " .. DIR .. "/" .. ARGS.alias,
        }
        print(cid)

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
        local cid = "#" .. gen
        local dir = DIR .. "/" .. cid .. "/"
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
            cmd = "ln -s '" .. cid .. "' " .. DIR .. "/" .. ARGS.alias,
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

        print(cid)
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
