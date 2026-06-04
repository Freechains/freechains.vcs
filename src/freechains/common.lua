VERSION = {0, 20, 0}
PORT    = 8330

function version ()
    return "v" .. VERSION[1] .. "." .. VERSION[2] .. "." .. VERSION[3]
end

function ERROR (msg, out)
    io.stderr:write("ERROR : " .. msg .. "\n")
    if out then
        io.stderr:write(">>>\n" .. out .. "<<<\n")
    end
    os.exit(1)
end

function exec (t)
    -- t.stderr == false: silences stderr ("2>/dev/null")
    local redir = (t.stderr == false) and "/dev/null" or "&1"
    local h = io.popen(t.cmd .. " 2>" .. redir)
    local out = h:read("a")
    if t.trim ~= false then
        out = out:match("^([^\n]*)\n$") or out
    end
    local _, _, code = h:close()
    if code == 0 then
        return out, code
    elseif t.err then
        if out == "" then
            out = nil
        end
        if t.err == true then
            return false, code, out
        else
            ERROR(t.err, out)
        end
    else
        error("bug found : [" .. code .. "] : " .. t.cmd .. " : " .. out)
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

function URL (raw, alias)
    if not raw:find("#") then
        local sep = (raw:sub(-1) == "/") and "" or "/"
        raw = raw .. sep .. alias
    end
    if raw:match("^[/~.]") or raw:find("://") then
        return raw
    end
    local hostport, path = raw:match("^([^/]+)(/?.*)$")
    if not hostport:find(":") then
        hostport = hostport .. ":" .. PORT
    end
    return "git://" .. hostport .. path
end

