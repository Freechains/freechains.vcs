#!/usr/bin/env lua5.4
require "common"

local DIR = ROOT .. "/chains/cli-sign/"
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

os.execute("sleep 1")   -- prevents hash collisions
exec(ENV_EXE .. " chains add cli-sign lua " .. GEN)

-- SIGNED POST
do
    print("==> freechains chain post --sign")

    do
        TEST "signed post succeeds"
        local out, code = exec (
            ENV_EXE .. " chain cli-sign post file hello.txt --sign " .. KEY
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")
    end

    do
        TEST "git verify-commit passes"
        local out, code = exec (
            ENV .. " git -C " .. DIR .. " verify-commit HEAD",
            true
        )
        assert(code == 0, "verify-commit failed")
        assert(out:match('Good signature from "test <test@freechains>"'))
    end

    do
        TEST "gpgsig header present"
        local out = exec (
            "git -C " .. DIR .. " cat-file commit HEAD"
        )
        assert(out:match("gpgsig"), "gpgsig header missing")
    end
end

-- UNSIGNED POST (regression)
do
    print("==> freechains chain post (unsigned)")

    do
        TEST "unsigned post still works"
        local out, code = exec (
            ENV_EXE .. " chain cli-sign post inline unsigned"
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
    end

    do
        TEST "unsigned commit has no gpgsig"
        local raw = exec (
            "git -C " .. DIR .. " cat-file commit HEAD"
        )
        assert(not raw:match("gpgsig"), "gpgsig should be absent")
    end
end

print("<== ALL PASSED")
