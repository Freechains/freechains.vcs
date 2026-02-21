--
-- common.lua — test helper functions for Lua tests
--
-- Usage at the top of every Lua test file:
--   dofile(arg[0]:match("^(.*/)") .. "common.lua")
--

local PASS = 0
local FAIL = 0

function assert_eq (expected, actual, label)
    label = label or ""
    if expected == actual then
        PASS = PASS + 1
    else
        io.stderr:write(string.format("  FAIL (%s): expected '%s', got '%s'\n",
                        label, tostring(expected), tostring(actual)))
        FAIL = FAIL + 1
    end
end

function assert_neq (a, b, label)
    label = label or ""
    if a ~= b then
        PASS = PASS + 1
    else
        io.stderr:write(string.format("  FAIL (%s): expected different, got '%s'\n",
                        label, tostring(a)))
        FAIL = FAIL + 1
    end
end

function assert_ok (cmd, label)
    label = label or ""
    local ok = os.execute(cmd .. " >/dev/null 2>&1")
    if ok then
        PASS = PASS + 1
    else
        io.stderr:write(string.format("  FAIL (%s): command failed: %s\n", label, cmd))
        FAIL = FAIL + 1
    end
end

function assert_fail (cmd, label)
    label = label or ""
    local ok = os.execute(cmd .. " >/dev/null 2>&1")
    if not ok then
        PASS = PASS + 1
    else
        io.stderr:write(string.format("  FAIL (%s): expected failure: %s\n", label, cmd))
        FAIL = FAIL + 1
    end
end

function report ()
    if FAIL == 0 then
        print(string.format("  OK: %d passed", PASS))
    else
        io.stderr:write(string.format("  FAILED: %d passed, %d failed\n", PASS, FAIL))
        os.exit(1)
    end
end

--- Run a command, return stdout as a string (trimmed of trailing newline)
function shell (cmd)
    local h = io.popen(cmd)
    local out = h:read("*a")
    h:close()
    return out:gsub("\n$", "")
end

--- Write string to a temporary file, return the path
function tmpwrite (s)
    local path = os.tmpname()
    local f = io.open(path, "wb")
    f:write(s)
    f:close()
    return path
end

--- Read entire file contents
function readfile (path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

--- Write data to a file
function writefile (path, data)
    local f = io.open(path, "wb")
    f:write(data)
    f:close()
end
