function ERROR (msg, out)
    io.stderr:write("ERROR : " .. msg .. "\n")
    if out then
        io.stderr:write(">>>\n" .. out .. "<<<\n")
    end
    os.exit(1)
end

function exec (a, b, c)
    local stderr, cmd, err
    if a == true then
        err = true
        if b == 'stderr' then
            stderr = true
            cmd = c
        else
            cmd = b
        end
    elseif a == 'stderr' then
        stderr = true
        cmd, err = b, c
    else
        cmd, err = a, b
    end

    local redir = stderr and "&1" or "/dev/null"
    local h = io.popen(cmd .. " 2>" .. redir)
    local raw = h:read("a")
    local out = raw:match("^([^\n]*)\n$") or raw
    local ok, _, code = h:close()

    if code == 0 then
        return out, code
    elseif err then
        if err == true then
            error("bug found : [" .. code .. "] : " .. cmd .. " : " .. out)
        else
            ERROR(err, out)
        end
    else
        return false, code, out
    end
end

function serial (t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys+1] = k
    end
    table.sort(keys)
    local lines = {}
    for _, k in ipairs(keys) do
        lines[#lines+1] = '    ["' .. k .. '"] = ' .. t[k] .. ","
    end
    return "return {\n" .. table.concat(lines, "\n") .. "\n}\n"
end

function git_config (dir)
    exec("git -C " .. dir .. " config user.name  '-'")
    exec("git -C " .. dir .. " config user.email '-'")
    exec("git -C " .. dir .. " config pull.rebase false")
end
