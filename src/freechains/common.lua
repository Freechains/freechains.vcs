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
    elseif t.err == false then
        if out == "" then
            out = nil
        end
        return false, code, out
    elseif t.err then
        if out == "" then
            out = nil
        end
        ERROR(t.err, out)
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
            local out = {"{\n"}
            for _, k in ipairs(keys) do
                local pfx
                if type(k) == 'number' then
                    pfx = "[" .. k .. "] = "
                else
                    pfx = '["' .. k .. '"] = '
                end
                out[#out+1] = "    " .. pfx .. val(v[k]) .. ",\n"
            end
            out[#out+1] = "}"
            return table.concat(out)
        end
    end
    return "return " .. val(t) .. "\n"
end

-- Objects reachable from `tips` that this repo does not have.
-- `rev-list --missing=print` prefixes those with '?'.
function missing_objects (dir, tips)
    local out = exec { err=false,
        cmd = "git -C " .. dir .. " rev-list --objects --missing=print " .. tips,
    }
    local T = {}
    if out then
        for h in out:gmatch("%?(%x+)") do
            T[#T+1] = h
        end
    end
    return T
end

-- Fetch `want` (an array of object hashes) from `url` BY HASH.
--
-- A fetch REQUEST is all-or-nothing: one absent hash sinks the whole
-- batch and its available siblings are NOT delivered. So try one
-- optimistic batch -- a single round trip whenever everything asked
-- for is there -- and only on failure retry per object, where the
-- available ones land and the absent ones fail individually.
--
-- --no-write-fetch-head: a by-hash fetch would otherwise point
-- FETCH_HEAD at the object, clobbering the tip a caller may still
-- need.
function fetch_objects (dir, url, want)
    if #want == 0 then
        return
    end
    table.sort(want)    -- deterministic request order
    local F = "git -C " .. dir .. " fetch --no-write-fetch-head " .. url .. " "
    local ok = exec { stderr=false, err=false,
        cmd = F .. table.concat(want, " "),
    }
    if not ok then
        for _, h in ipairs(want) do
            exec { stderr=false, err=false, cmd = F .. h }
        end
    end
end

-- git refuses to register a promisor remote whose name begins with
-- '/', and --filter cannot run without one, so a bare absolute path
-- fails outright with "did not send all necessary objects". file:// is
-- the same transport under a name git will accept.
function FILTERABLE (url)
    if url:sub(1,1) == "/" then
        return "file://" .. url
    end
    return url
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

