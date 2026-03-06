#!/usr/bin/env lua5.4
require "common"

local GPGHOME = TMP .. "/gnupg/"
local KEY_ID

-- SETUP: generate ephemeral GPG key
do
    exec("rm -rf " .. GPGHOME)
    exec("mkdir -p " .. GPGHOME)
    exec("chmod 700 " .. GPGHOME)

    local batch = GPGHOME .. "/keygen.batch"
    local f = io.open(batch, "w")
    f:write(
        "%no-protection\n"
        .. "Key-Type: eddsa\n"
        .. "Key-Curve: ed25519\n"
        .. "Name-Real: test\n"
        .. "Name-Email: test@freechains\n"
    )
    f:close()

    exec (
        "gpg --homedir " .. GPGHOME
        .. " --batch --gen-key " .. batch,
        true
    )

    KEY_ID = exec (
        "gpg --homedir " .. GPGHOME
        .. " --list-keys --with-colons"
        .. " | grep '^fpr:' | head -1"
        .. " | cut -d: -f10"
    )
    assert(#KEY_ID > 0, "keygen failed")
end

local GPG_ENV = "GNUPGHOME=" .. GPGHOME .. " "
local REPO = ROOT .. "/chains/signchain/"

exec(GPG_ENV .. EXE .. " chains add signchain lua " .. GEN)

-- SIGNED POST
do
    print("==> freechains chain post --sign")

    do
        TEST "signed post succeeds"
        local out, code = exec (
            GPG_ENV .. EXE
            .. " chain signchain post file hello.txt"
            .. " --sign " .. KEY_ID
        )
        assert(code == 0, "exit code: " .. tostring(code))
        assert(#out == 40, "hash length: " .. #out)
        assert(out:match("^%x+$"), "hash is hex")
    end

    do
        TEST "git verify-commit passes"
        local _, code = exec (
            GPG_ENV
            .. "git -C " .. REPO
            .. " verify-commit HEAD"
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
            GPG_ENV .. EXE
            .. " chain signchain post file " .. tmp
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
exec("rm -rf " .. GPGHOME)

print("<== ALL PASSED")
