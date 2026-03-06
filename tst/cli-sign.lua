#!/usr/bin/env lua5.4
require "common"

local GPG     = TMP .. "/gnupg/"
local ENV     = "GNUPGHOME=" .. GPG
local ENV_EXE = ENV .. " " .. EXE
local REPO    = ROOT .. "/chains/signchain/"
local KEY


-- SETUP: generate ephemeral GPG key
do
    exec("rm -rf " .. GPG)
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
    exec("gpg --homedir " .. GPG .. " --batch --gen-key " .. batch, true)

    local out = exec (
        "gpg --homedir " .. GPG .. " --list-keys --with-colons"
    )
    KEY = out:match("fpr:.-:.-:.-:.-:.-:.-:.-:.-:(%x+):")
    assert(KEY and #KEY > 0, "keygen failed")
end

os.execute("sleep 1")   -- prevents hash collisions
exec(ENV_EXE .. " chains add signchain lua " .. GEN)

-- SIGNED POST
do
    print("==> freechains chain post --sign")

    do
        TEST "signed post succeeds"
        local out, code = exec (
            ENV_EXE .. " chain signchain post file hello.txt --sign " .. KEY
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")
    end

    do
        TEST "git verify-commit passes"
        local _, code = exec (
            ENV .. " git -C " .. REPO .. " verify-commit HEAD"
        )
        assert(code == 0, "verify-commit failed")
    end

    do
        TEST "gpgsig header present"
        local raw = exec (
            "git -C " .. REPO
            .. " cat-file commit HEAD"
        )
        assert(
            raw:match("gpgsig"),
            "gpgsig header missing"
        )
    end
end

-- UNSIGNED POST (regression)
do
    print("==> freechains chain post (unsigned)")

    do
        TEST "unsigned post still works"
        local tmp = TMP .. "/unsigned.txt"
        local f = io.open(tmp, "w")
        f:write("unsigned content\n")
        f:close()
        local out, code = exec (
            ENV_EXE .. " chain signchain post file " .. tmp
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
    end

    do
        TEST "unsigned commit has no gpgsig"
        local raw = exec (
            "git -C " .. REPO
            .. " cat-file commit HEAD"
        )
        assert(
            not raw:match("gpgsig"),
            "gpgsig should be absent"
        )
    end
end

-- TEARDOWN
exec("rm -rf " .. GPG)

print("<== ALL PASSED")
