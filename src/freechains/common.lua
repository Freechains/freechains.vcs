VERSION = {0, 20, 0}
PORT    = 8330

--[[
-- The version string ("vX.Y.Z") from the VERSION table.
-- Inputs:
--  - none
-- Outputs:
--  - [string]: "v" .. major.minor.patch
-- Errors:
--  - none
-- Callers:
--  - --version action (freechains.lua): prints and exits
--]]
function version ()
    return "v" .. VERSION[1] .. "." .. VERSION[2] .. "." .. VERSION[3]
end

--[[
-- Print "ERROR : <msg>" to stderr and exit(1).
-- Inputs:
--  - msg [string]: "<command> : <detail>" (see CLAUDE.md format)
--  - out [string?]: raw tool output, quoted between >>> <<<
-- Outputs:
--  - none: never returns (os.exit)
-- Errors:
--  - none
-- Callers:
--  - everywhere: every command's user-facing failure path
--]]
function ERROR (msg, out)
    io.stderr:write("ERROR : " .. msg .. "\n")
    if out then
        io.stderr:write(">>>\n" .. out .. "<<<\n")
    end
    os.exit(1)
end

--[[
-- Run a shell command, capture stdout, dispatch on exit code.
-- Inputs:
--  - t.cmd    [string]: the command line
--  - t.trim   [boolean?]: false keeps the trailing newline
--  - t.stderr [boolean?]: false silences stderr (2>/dev/null)
--  - t.err    [string|boolean?]: on failure -- string: ERROR(err);
--    false: return; nil: raise "bug found" (failure is a bug)
-- Outputs:
--  - [string, integer]: stdout and code 0 on success
--  - [false, integer, string?]: code and stderr/stdout (err=false)
-- Errors:
--  - "bug found : [code] : cmd : out" : failure with t.err = nil
-- Callers:
--  - everywhere: the single door to git and the shell
--]]
function exec (t)
    -- t.stderr == false: silences stderr ("2>/dev/null")
    local redir = (t.stderr == false) and "/dev/null" or "&1"
    local h = io.popen(t.cmd .. " 2>" .. redir)
    local out = h:read("a")
    local _, _, code = h:close()
    if code == 0 then
        if t.trim ~= false then
            out = out:match("^([^\n]*)\n$") or out
        end
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

--[[
-- Convert table to string with keys sorted.
-- Inputs:
--  - v   [table]: nested booleans/numbers/strings/tables only
--  - spc [string?]: indentation accumulator (recursion only)
-- Outputs:
--  - [string]: '{...}', the table's Lua source
-- Errors:
--  - assert: a string value containing '"'
--  - "TODO : unsupported type" : function/userdata/etc
-- Callers:
--  - table_to_file (common.lua): the only consumer
--]]
local function table_to_string (v, spc)
    spc = spc or ""
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
        local sub = spc .. "    "
        for _, k in ipairs(keys) do
            local pfx
            if type(k) == 'number' then
                pfx = "[" .. k .. "] = "
            else
                pfx = '["' .. k .. '"] = '
            end
            out[#out+1] = sub .. pfx .. table_to_string(v[k], sub) .. ",\n"
        end
        out[#out+1] = spc .. "}"
        return table.concat(out)
    end
end

--[[
-- Writes table to given path as a loadable "return {...}" chunk.
-- Inputs:
--  - t    [table]: nested booleans/numbers/strings/tables only
--  - path [string]: destination file (overwritten)
-- Outputs:
--  - none
-- Errors:
--  - see table_to_string above
-- Callers:
--  - STATE.write (state.lua): snapshot staging file
--  - genesis (chains.lua): genesis snapshot staging file
--]]
function table_to_file (t, path)
    local f = io.open(path, "w")
    f:write("return " .. table_to_string(t) .. "\n")
    f:close()
end

--[[
-- Expand a user remote into a git URL: append the chain alias
-- to a bare host, default to git:// host with the freechains PORT.
-- Inputs:
--  - raw   [string]: path, host[:port][/path], or full URL
--  - alias [string]: chain "/alias" or bare "<cid>", appended to
--    bare hosts; any path or URL is explicit
-- Outputs:
--  - [string]: local path or "git://host:port/path"
-- Errors:
--  - none
-- Callers:
--  - chains add clone (chains.lua): fetch genesis + first recv
--  - sync send/recv (sync.lua): push/fetch remotes
--]]
function URL (raw, alias)
    -- bare host[:port]: append alias; any path/URL is explicit
    if not raw:find("/") then
        if alias:sub(1,1) ~= "/" then
            alias = "/" .. alias
        end
        raw = raw .. alias
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

