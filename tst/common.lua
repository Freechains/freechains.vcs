TMP  = "/tmp/freechains/"
GEN    = "genesis/"
GEN_1P = "genesis-1p/"
GEN_2P = "genesis-2p/"
ROOT = TMP .. "/root/"
EXE  = "../src/freechains --root " .. ROOT

function exec (cmd, stderr)
    local redir = stderr and "&1" or "/dev/null"
    local h = io.popen(cmd .. " 2>" .. redir)
    local raw = h:read("a")
    local out = raw:match("^([^\n]*)\n$") or raw
    local ok, _, code = h:close()
    return out, (ok and 0 or code)
end

GPG     = exec("realpath gnupg/") .. "/"
KEY     = "CA6391CEA51882DF980E0F0C6774E21538E4078B"
KEY2    = "783975D11C5437506E4EF015CC72520488613667"
ENV     = "GNUPGHOME=" .. GPG
ENV_EXE = ENV .. " " .. EXE

function git_config (dir)
    exec("git -C " .. dir .. " config user.name  '-'")
    exec("git -C " .. dir .. " config user.email '-'")

end

function TEST (name)
    print("  - " .. name .. "... ")
end
