--[[
-- `chains add|rem|dir`
-- Create, remove, or list root chains.
-- One bare repo per chain, alias symlinks.
-- Inputs:
--  - ARGS.add [boolean]: with ARGS.init (+ ARGS.pioneer list)
--    or ARGS.clone (+ ARGS.url)
--  - ARGS.rem [boolean]: delete repo + alias
--  - ARGS.dir [boolean]: list aliases
--  - ARGS.alias [string]: "/..." chain alias
--  - ARGS.root  [string]: freechains root dir
-- Outputs:
--  - stdout: the chain cid ("<genesis>"), or the alias listing
--  - fs: repo dir under chains/ + alias symlink (add/rem)
-- Errors:
--  - "chains add : invalid alias : expected '/'"
--  - "chains add : invalid alias : nested alias not supported"
--  - "chains add : alias already exists"
--  - "chains add : invalid pioneer : <v>"
--  - "chains add : git init failed" | "init failed"
--    | "clone failed" | "invalid genesis" | "too many pioneers"
--  - "chains rem : invalid chain"
-- Callers:
--  - dispatch (freechains.lua): ARGS.chains
--]]

local C    = require "freechains.constants"
local SSH  = require "freechains.chain.ssh"
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
-- Parses the two key sections from the genesis commit MESSAGE and splits
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
--  - "chains add : invalid genesis : expected newline"
--  - "chains add : invalid genesis : unexpected empty line"
--  - "chains add : invalid genesis : expected dictators"
--  - "chains add : invalid genesis : expected pioneers"
--  - "chains add : invalid genesis : unexpected pioneers"
--  - "chains add : invalid genesis : invalid key"
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
    --   <version>\n<nonce>\ndictators:\n<key>...\npioneers:\n<key>...
    -- both headers are ALWAYS present: an empty section states
    -- that the role is empty, instead of leaving it to be inferred
    -- `src` is false when refs/genesis is not a commit (clone);
    -- for a commit, the "\n\n" separator is ALWAYS present
    local src = exec { trim=false, err=false, stderr=false,
        cmd = "git -C " .. dir .. " cat-file commit " .. gen,
    }
    if not src then
        ERROR("chains add : invalid genesis : expected commit")
    end

    src = src:match("\n\n(.*)$")

    -- STRICT split: every line ends in "\n", and none is empty.
    if src:sub(-1) ~= "\n" then
        ERROR("chains add : invalid genesis : expected newline")
    end
    local ls = {}
    for l in src:gmatch("([^\n]*)\n") do
        if l == "" then
            ERROR("chains add : invalid genesis : unexpected empty line")
        end
        ls[#ls+1] = l
    end

    if not (ls[1] and ls[1]:match("^%d+%.%d+%.%d+$")) then
        ERROR("chains add : invalid genesis : expected version")
    end
    if not (ls[2] and ls[2]:match("^%d+$")) then
        ERROR("chains add : invalid genesis : expected nonce")
    end

    -- two SECTIONS, in this order, each holding sorted keys
    if ls[3] ~= "dictators:" then
        ERROR("chains add : invalid genesis : expected dictators")
    end

    -- first section: up to the `pioneers:` header, which MUST come
    local gods = {}
    local i = 4
    while ls[i] ~= "pioneers:" do
        if not ls[i] then
            ERROR("chains add : invalid genesis : expected pioneers")
        end
        local key = ls[i]:match("^(ssh%-%S+ %S+)$")
        if not key then
            ERROR("chains add : invalid genesis : invalid dictator : expected key")
        end
        gods[#gods+1] = key
        i = i + 1
    end

    -- second section: everything after that header
    local pios = {}
    for j=i+1, #ls do
        local key = ls[j]:match("^(ssh%-%S+ %S+)$")
        if not key then
            ERROR("chains add : invalid genesis : invalid pioneer : expected key")
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

    -- dictator: never checked, and its side wins a fork
    -- ordinary member otherwise (pays, mints, caps, may owe)
    for _, key in ipairs(gods) do
        A[key] = A[key] or { reps = 0 }
        A[key].dictator = true
    end

    local G = {
        now     = 0,
        open    = (#pios==0 and #gods==0),  -- unrestricted chain: anyone can post,vote
        members = A,
        actions = {},
        order   = {},
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
    if ARGS.alias:sub(1,1) ~= "/" then
        ERROR("chains add : invalid alias : expected '/'")
    end
    -- flat for now: "/a/b" reserved
    if ARGS.alias:find("/", 2, true) then
        ERROR("chains add : invalid alias : unexpected '/'")
    end
    if io.open(DIR .. ARGS.alias) then
        ERROR("chains add : alias already exists")
    end

    if ARGS.init then
        local rand = math.random(0, 9999999999)

        -- each --pioneer is a key string ("ssh-...") or a key file.
        -- hash part dedups a repeated flag
        -- array part holds the order
        local pios = {}
        for _, v in ipairs(ARGS.pioneer or {}) do
            local key = SSH.pub(v)
            if not key then
                ERROR("chains add : invalid pioneer : " .. v)
            end
            if not pios[key] then
                pios[key] = true        -- seen
                pios[#pios+1] = key     -- order
            end
        end

        -- each --dictator is a key string or a key file too
        local gods = {}
        for _, v in ipairs(ARGS.dictator or {}) do
            local key = SSH.pub(v)
            if not key then
                ERROR("chains add : invalid dictator : " .. v)
            end
            if not gods[key] then
                gods[key] = true
                gods[#gods+1] = key
            end
        end

        table.sort(pios)
        table.sort(gods)

        -- genesis message, POSITIONAL (see `genesis` above):
        -- both headers always, each section sorted, so two peers
        -- building the same chain emit the very same bytes
        local GEN = table.concat(VERSION, ".") .. "\n" ..
            rand .. "\n" ..
            "dictators:\n"
        for _, key in ipairs(gods) do
            GEN = GEN .. key .. "\n"
        end
        GEN = GEN .. "pioneers:\n"
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

        local dir = DIR .. "/" .. gen
        if not os.rename(tmp, dir) then
            exec {
                cmd = "rm -rf " .. tmp,
            }
            ERROR("chains add : init failed")
        end
        exec {
            cmd = "git -C '" .. dir .. "' config freechains.url '" .. dir .. "'",
        }
        exec {
            cmd = "ln -s '" .. gen .. "/' " .. DIR .. ARGS.alias,
        }
        print(gen)

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

        local dir = DIR .. "/" .. gen .. "/"
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
            cmd = "ln -s '" .. gen .. "/' " .. DIR .. ARGS.alias,
        }

        genesis(dir, gen)

        -- re-exec myself: `recv` binds REPO from its own ARGS
        local ok, _, out = exec { err=false,
            cmd = arg[0] .. " --root='" .. ARGS.root .. "'"
                .. " chain '" .. ARGS.alias .. "'"
                .. " sync recv '" .. ARGS.url .. "'",
        }
        if not ok then
            os.remove(DIR .. ARGS.alias)
            exec {
                cmd = "rm -rf '" .. dir .. "'",
            }
            ERROR("chains add : clone failed", out)
        end

        print(gen)
    end
elseif ARGS.rem then
    local alias = DIR .. ARGS.alias
    local lnk = exec {
        cmd = "readlink " .. alias,
        err = "chains rem : invalid chain",
    }
    exec {
        cmd = "rm -rf '" .. DIR .. lnk .. "'",
    }
    os.remove(alias)
elseif ARGS.dir then
    local out = exec { trim=false,
        cmd = "find " .. DIR .. " -maxdepth 1 -type l -printf '/%f\\n'" .. " | sort",
    }
    io.write(out)
end
