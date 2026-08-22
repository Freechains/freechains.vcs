local M = {}

-- Pubkey by source: `key` from a key file, `commit` from a signature.
M.pub = {}

--[[
-- The pubkey of a private key file, from its `.pub` sibling.
-- Inputs:
--  - path [string]: private key path (reads path .. ".pub")
-- Outputs:
--  - [string?]: "ssh-ed25519 <base64>", nil if unreadable
-- Errors:
--  - none
-- Callers:
--  - post/like: early clean check of --sign before minting
--]]
function M.pub.key (path)
    local f = io.open(path .. ".pub")
    if not f then
        return nil
    end
    local s = f:read("l") or ""
    f:close()
    return s:match("^(%S+ %S+)")
end

--[[
-- Resolve a pubkey from
--  - a key STRING ("ssh-...")
--  - a pub key FILE
--  - a pvt key FILE
-- Inputs:
--  - v [string]: key string or key file path
-- Outputs:
--  - [string?]: "ssh-ed25519 <base64>", nil if none resolves
-- Errors:
--  - none
-- Callers:
--  - chains add init (chains.lua): each --pioneer
--  - like (like.lua): author target normalization
--  - reps (reps.lua): author key argument
--]]
function M.pub.any (v)
    if v:match("^ssh%-") then
        return v:match("^(%S+ %S+)")
    end
    local f = io.open(v)
    local ln = f and f:read("l")
    if f then
        f:close()
    end
    if ln and ln:match("^ssh%-") then
        return ln:match("^(%S+ %S+)")   -- public key file
    end
    local out = exec { err=false, stderr=false,
        cmd = "ssh-keygen -y -f " .. v, -- private key file
    }
    if out then
        return out:match("^(%S+ %S+)")
    end
    return nil
end

--[[
-- Extract CLAIMED pubkey from a commit gpgsig header
-- (parses the SSHSIG armored blob; does NOT verify it).
-- Inputs:
--  - repo [string]: git dir path
--  - cid  [string]: 40-hex commit hash
-- Outputs:
--  - [string?]: "ssh-ed25519 <base64>", nil if unsigned
-- Errors:
--  - via exec: "bug found" if cat-file/base64/xxd fail
-- Callers:
--  - read (action.lua): opt-in `t.sign` (display only)
--  - collect_keys (consensus.lua): reps summing per side
--  - verify (ssh.lua): the key the signature is checked against
--]]
function M.pub.commit (repo, cid)
    local commit = exec {
        cmd = "git -C " .. repo .. " cat-file commit " .. cid,
    }
    if not commit:match("\ngpgsig ") then
        return nil
    end

    -- collect gpgsig line + following continuation lines (start with space)
    local body = ""
    local in_sig = false
    for line in (commit .. "\n"):gmatch("([^\n]*)\n") do
        if in_sig then
            if line:sub(1,1) == " " then
                local s = line:sub(2)
                if not s:match("^%-%-%-") then
                    body = body .. s
                else
                    -- skip BEGIN/END armor
                end
            else
                in_sig = false
            end
        else
            if line:match("^gpgsig ") then
                in_sig = true
                -- first line is "-----BEGIN SSH SIGNATURE-----", skip
            else
                -- not the gpgsig header
            end
        end
    end
    local hex = exec {
        cmd = "printf '%s' '" .. body .. "' | base64 -d | xxd -p | tr -d '\n'",
    }
    --[[
    -- Big-endian u32 at 1-based offset `off` of the hex dump.
    -- Inputs:
    --  - off [integer]: hex-char offset (8 chars read)
    -- Outputs:
    --  - [integer]: the 32-bit value
    -- Errors:
    --  - none
    -- Callers:
    --  - pub.commit (ssh.lua): SSHSIG wire-format lengths
    --]]
    local function u32 (off)
        local a = tonumber(hex:sub(off,    off+1), 16)
        local b = tonumber(hex:sub(off+2,  off+3), 16)
        local c = tonumber(hex:sub(off+4,  off+5), 16)
        local d = tonumber(hex:sub(off+6,  off+7), 16)
        return ((a*256 + b)*256 + c)*256 + d
    end

    -- skip "SSHSIG"(6B=12hex) + version(4B=8hex) = 20 hex chars
    -- pubkey wire-format string starts at hex offset 21 (1-based)
    local len = u32(21)
    local hex = hex:sub(29, 28 + len*2)
    local key = exec {
        cmd = "printf '%s' '" .. hex .. "' | xxd -r -p | base64 -w0",
    }
    return "ssh-ed25519 " .. key
end

--[[
-- Verify a commit's SSH signature against its embedded pubkey.
-- Inputs:
--  - repo [string]: git dir path
--  - cid  [string]: 40-hex commit hash
-- Outputs:
--  - [string]: the verified pubkey, or
--  - [nil, string]: 'unsigned' (no gpgsig) | 'forged' (bad sig)
-- Errors:
--  - none
-- Callers:
--  - apply (action.lua): authenticates every action
--]]
function M.verify (repo, cid)
    local key = M.pub.commit(repo, cid)
    if key == nil then
        return nil, 'unsigned'
    end

    -- per-repo scratch: the bare repo dir IS the git dir
    local f = io.open(repo .. "/allowed_signers", "w")
    f:write("git " .. key .. "\n")
    f:close()
    local out, code = exec { err=false,
        cmd = "git -C " .. repo
        .. " -c gpg.ssh.allowedSignersFile=allowed_signers"
        .. " verify-commit " .. cid,
    }
    os.remove(repo .. "/allowed_signers")
    if code == 0 then
        return key
    else
        return nil, 'forged'
    end
end

return M
