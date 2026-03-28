function ERROR (msg, out)
    io.stderr:write("ERROR : " .. msg .. "\n")
    if out then
        io.stderr:write(">>>\n" .. out .. "<<<\n")
    end
    os.exit(1)
end

function exec (a, b, c)
    local stdout, cmd, err
    if a == true then
        err = true
        if b == 'stdout' then
            stdout = true
            cmd = c
        else
            cmd = b
        end
    elseif a == 'stdout' then
        stdout = true
        cmd, err = b, c
    else
        cmd, err = a, b
    end

    local redir = stdout and "/dev/null" or "&1"
    local h = io.popen(cmd .. " 2>" .. redir)
    local raw = h:read("a")
    local out = raw:match("^([^\n]*)\n$") or raw
    local ok, _, code = h:close()

    if code == 0 then
        return out, code
    elseif err then
        if err == true then
            return false, code, out
        else
            ERROR(err, out)
        end
    else
        error("bug found : [" .. code .. "] : " .. cmd .. " : " .. out)
    end
end

function serial (t)
    local function val (v)
        if type(v) == 'boolean' then
            return tostring(v)
        elseif type(v) == 'number' then
            return tonumber(v)
        elseif type(v) == 'string' then
            assert(not string.find(v,'"'))
            return '"' .. v .. '"'
        elseif type(v) ~= 'table' then
            error("TODO : unsupported type")
        else
            local keys = {}
            for k in pairs(v) do keys[#keys+1] = k end
            table.sort(keys)
            local parts = {}
            for _, k in ipairs(keys) do
                local pfx
                if type(k) == 'number' then
                    pfx = "[" .. k .. "] = "
                else
                    pfx = '["' .. k .. '"] = '
                end
                parts[#parts+1] = pfx .. val(v[k])
            end
            local out = "{\n"
            for _,v in ipairs(parts) do
                out = out .. "    " .. v .. ",\n"
            end
            out = out .. "}"
            return out
        end
    end
    return "return " .. val(t) .. "\n"
end

