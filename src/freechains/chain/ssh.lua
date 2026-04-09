-- Extract the SSH pubkey from a signed commit, or nil if unsigned.
-- Parses the SSHSIG armored blob in the gpgsig header.
function pubkey (repo, hash)
    local commit = exec("git -C " .. repo .. " cat-file commit " .. hash)
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
    local hex = exec(
        "printf '%s' '" .. body .. "' | base64 -d | xxd -p | tr -d '\n'"
    )
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
    local key = exec(
        "printf '%s' '" .. hex .. "' | xxd -r -p | base64 -w0"
    )
    return "ssh-ed25519 " .. key
end

-- Verify a commit's SSH signature against its embedded pubkey.
-- Returns pubkey on success, nil on failure.
function verify (repo, hash)
    local key = pubkey(repo, hash)
    if key == nil then
        return nil
    end

    local f = io.open(repo .. "/.freechains/tmp/allowed_signers", "w")
    f:write("git " .. key .. "\n")
    f:close()
    local out, code = exec(true,
        "git -C " .. repo
        .. " -c gpg.ssh.allowedSignersFile=.freechains/tmp/allowed_signers"
        .. " verify-commit " .. hash
    )
    if code == 0 then
        return key
    else
        return nil
    end
end
