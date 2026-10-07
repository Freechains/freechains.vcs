local M = {}

-- base64 in Lua: the signature and key blobs are small, and a
-- shell pipeline per decode (base64 | xxd | tr) cost 3-4 processes
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64V = {}
for i = 1, 64 do
    B64V[B64:sub(i, i)] = i - 1
end

--[[
-- Decode base64 (standard alphabet, padding optional, whitespace
-- ignored).
-- Inputs:
--  - s [string]: base64 text
-- Outputs:
--  - [string]: the bytes
-- Errors:
--  - none (invalid chars are skipped)
-- Callers:
--  - pub/signer (ssh.lua): key files and SSHSIG blobs
--]]
local function b64dec (s)
    local out = {}
    local acc, bits = 0, 0
    for c in s:gmatch("[A-Za-z0-9+/]") do
        acc = (acc << 6) | B64V[c]
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            out[#out+1] = string.char((acc >> bits) & 0xFF)
            acc = acc & ((1 << bits) - 1)
        end
    end
    return table.concat(out)
end

--[[
-- Encode bytes as base64 (standard alphabet, padded, one line).
-- Inputs:
--  - s [string]: the bytes
-- Outputs:
--  - [string]: base64 text
-- Errors:
--  - none
-- Callers:
--  - pub/signer (ssh.lua): the pubkey blob as git prints it
--]]
local function b64enc (s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i+2)
        local n = (a << 16) | ((b or 0) << 8) | (c or 0)
        out[#out+1] = B64:sub((n >> 18) + 1, (n >> 18) + 1)
            .. B64:sub(((n >> 12) & 63) + 1, ((n >> 12) & 63) + 1)
            .. (b and B64:sub(((n >> 6) & 63) + 1, ((n >> 6) & 63) + 1) or "=")
            .. (c and B64:sub((n & 63) + 1, (n & 63) + 1) or "=")
    end
    return table.concat(out)
end

--[[
-- The pubkey line of an SSH wire-format key blob
-- ("<type> <base64 blob>", as ssh-keygen and git print it).
-- Inputs:
--  - blob [string]: the key blob (starts with the string <type>)
-- Outputs:
--  - [string?]: "<type> <base64>", nil if malformed
-- Errors:
--  - none
-- Callers:
--  - pub/signer (ssh.lua)
--]]
local function keyline (blob)
    if #blob < 4 then
        return nil
    end
    local n = string.unpack(">I4", blob)
    if (n < 1) or (#blob < 4 + n) then
        return nil
    end
    return blob:sub(5, 4 + n) .. " " .. b64enc(blob)
end

--[[
-- Resolve a pubkey from anything (cli.md "Keys:"):
--  - a key STRING ("ssh-...")
--  - a pub key FILE
--  - a pvt key FILE (ssh-keygen -y)
-- Inputs:
--  - v [string]: key string or key file path
-- Outputs:
--  - [string?]: "ssh-ed25519 <base64>", nil if none resolves
-- Errors:
--  - none
-- Callers:
--  - post/like: early clean check of --sign before minting
--  - like (like.lua): member target normalization
--  - reps (reps.lua): member key argument
--  - chains add init (chains.lua): each --pioneer
--]]
function M.pub (v)
    if v:match("^ssh%-") then
        return v:match("^(%S+ %S+)")
    end
    local f = io.open(v)
    local src = f and f:read("a")
    if f then
        f:close()
    end
    if not src then
        return nil
    end
    if src:match("^ssh%-") then
        return src:match("^(%S+ %S+)")   -- public key file
    end
    -- an OpenSSH private key carries its pubkey in clear:
    --   "openssh-key-v1\0" cipher kdf kdfopts nkeys <pubkey blob>
    local body = src:match("^%-%-%-%-%-BEGIN OPENSSH PRIVATE KEY%-%-%-%-%-\n(.-)\n%-%-%-%-%-END")
    if body then
        local raw = b64dec(body)
        if raw:sub(1, 15) == "openssh-key-v1\0" then
            local pos = 16
            for _ = 1, 3 do          -- cipher, kdf, kdfopts
                local n = string.unpack(">I4", raw, pos)
                pos = pos + 4 + n
            end
            pos = pos + 4            -- nkeys
            local n = string.unpack(">I4", raw, pos)
            return keyline(raw:sub(pos + 4, pos + 3 + n))
        end
    end
    local out = exec { err=false, stderr=false,
        cmd = "ssh-keygen -y -f " .. v, -- any other private key format
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
--  - repo [string]: git dir path (REPO uses the chain's commit memo)
--  - cid  [string]: 40-hex commit hash
-- Outputs:
--  - [string?]: "ssh-ed25519 <base64>", nil if unsigned
-- Errors:
--  - "bug found : not a commit" : unknown cid
-- Callers:
--  - read (action.lua): opt-in `t.sign` (display only)
--  - collect_keys (consensus.lua): reps summing per side
--  - verify (ssh.lua): the key the signature is checked against
--]]
function M.signer (repo, cid)
    -- the chain's memo when in chain context (tests call this
    -- module alone, on any repo)
    local commit
    if GIT and (repo == REPO) then
        commit = GIT.cat(cid)
    else
        commit = exec { trim=false,
            cmd = "git -C " .. repo .. " cat-file commit " .. cid,
        }
    end
    assert(commit, "bug found : not a commit : " .. cid)
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
    -- SSHSIG blob: "SSHSIG" (6) + version u32 + string pubkey ...
    local raw = b64dec(body)
    local len = string.unpack(">I4", raw, 11)
    return keyline(raw:sub(15, 14 + len))
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
    local key = M.signer(repo, cid)
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
