function ERROR (msg)
    io.stderr:write("ERROR : " .. msg .. "\n")
    os.exit(1)
end

function exec (a, b, c)
    local stderr, err, cmd
    if c then
        stderr, err, cmd = a, b, c
    elseif b then
        if type(a) == "boolean" then
            stderr, cmd = a, b
        else
            err, cmd = a, b
        end
    else
        cmd = a
    end

    local redir = stderr and "&1" or "/dev/null"
    local h = io.popen(cmd .. " 2>" .. redir)
    local raw = h:read("a")
    local out = raw:match("^([^\n]*)\n$") or raw
    local ok, _, code = h:close()

    if code == 0 then
        return out, code
    elseif err then
        ERROR(err)
    else
        return false, code
    end
end

function git_config (dir)
    exec("git -C " .. dir .. " config user.name  '-'")
    exec("git -C " .. dir .. " config user.email '-'")
    exec("git -C " .. dir .. " config pull.rebase false")
end
