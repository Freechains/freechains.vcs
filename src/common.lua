function ERROR (msg)
    io.stderr:write("ERROR : " .. msg .. "\n")
    os.exit(1)
end

function exec (a, b, c)
    local stderr, cmd, err
    if a == 'stderr' then
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
        ERROR(err==true and "bug found" or err)
    else
        return false, code
    end
end

function git_config (dir)
    exec("git -C " .. dir .. " config user.name  '-'")
    exec("git -C " .. dir .. " config user.email '-'")
    exec("git -C " .. dir .. " config pull.rebase false")
end
