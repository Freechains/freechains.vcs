TMP  = "/tmp/freechains/"
GEN  = "genesis.lua"
ROOT = TMP .. "/root/"
EXE  = "../src/freechains --root " .. ROOT

function exec (cmd)
    local h = io.popen(cmd .. " 2>&1")
    local out = h:read("a"):match("^%s*(.-)%s*$")
    local ok, _, code = h:close()
    return out, (ok and 0 or code)
end

function TEST (name)
    print("  - " .. name .. "... ")
end
