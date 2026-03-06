TMP     = "/tmp/freechains/"
GPG     = TMP .. "/gnupg/"
GEN     = "genesis.lua"
ROOT    = TMP .. "/root/"
EXE     = "../src/freechains --root " .. ROOT
ENV     = "GNUPGHOME=" .. GPG
ENV_EXE = ENV .. " " .. EXE

function exec (cmd, stderr)
    local redir = stderr and "&1" or "/dev/null"
    local h = io.popen(cmd .. " 2>" .. redir)
    local raw = h:read("a")
    local out = raw:match("^([^\n]*)\n$") or raw
    local ok, _, code = h:close()
    return out, (ok and 0 or code)
end

function TEST (name)
    print("  - " .. name .. "... ")
end
