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

-- SETUP: generate ephemeral GPG key
do
    exec("mkdir -p " .. GPG)
    exec("chmod 700 " .. GPG)

    local batch = GPG .. "/keygen.batch"
    local f = io.open(batch, "w")
    f:write [[
        %no-protection
        Key-Type: eddsa
        Key-Curve: ed25519
        Name-Real: test
        Name-Email: test@freechains
    ]]
    f:close()
    exec (
        "gpg --homedir " .. GPG .. " --batch --gen-key " .. batch
        , true
    )

    local out = exec (
        "gpg --homedir " .. GPG .. " --list-keys --with-colons"
    )
    KEY = out:match("fpr:.-:.-:.-:.-:.-:.-:.-:.-:(%x+):")
    assert(KEY and #KEY > 0, "keygen failed")
end
