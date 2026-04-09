#!/usr/bin/env lua5.4

require "tests"
require "freechains.chain.ssh"

local DIR  = TMP .. "/ssh-unit/"
local KEYS = exec("realpath ssh-keys/")
local K1   = KEYS .. "/key1"
local K2   = KEYS .. "/key2"
local PUB1 = exec("awk '{print $1\" \"$2}' " .. K1 .. ".pub")
local PUB2 = exec("awk '{print $1\" \"$2}' " .. K2 .. ".pub")

local function reset_repo ()
    exec("rm -rf " .. DIR)
    exec("mkdir -p " .. DIR)
    exec("git -C " .. DIR .. " init -q")
    exec("git -C " .. DIR .. " config user.email t@t")
    exec("git -C " .. DIR .. " config user.name  t")
end

local function commit_signed (key, msg)
    local cmd = "git -C " .. DIR
        .. " -c gpg.format=ssh"
        .. " -c user.signingkey=" .. key
        .. " commit -S --allow-empty -q -m '" .. msg .. "'"
    exec(cmd)
    return exec("git -C " .. DIR .. " rev-parse HEAD")
end

local function commit_unsigned (msg)
    exec("git -C " .. DIR .. " commit --allow-empty -q -m '" .. msg .. "'")
    return exec("git -C " .. DIR .. " rev-parse HEAD")
end

print("==> signing_ssh helpers")

do
    TEST "extract_pubkey returns key1 pubkey after signing with key1"
    reset_repo()
    local h = commit_signed(K1, "one")
    local pk = extract_pubkey(DIR, h)
    assert(pk == PUB1, "got: " .. tostring(pk) .. " want: " .. PUB1)
end

do
    TEST "verify_commit returns (true, pubkey) on good signature"
    reset_repo()
    local h = commit_signed(K1, "two")
    local ok, pk = verify_commit(DIR, h)
    assert(ok == true, "verify failed")
    assert(pk == PUB1, "wrong pubkey")
end

do
    TEST "extract_pubkey returns nil on unsigned commit"
    reset_repo()
    local h = commit_unsigned("plain")
    local pk = extract_pubkey(DIR, h)
    assert(pk == nil, "expected nil, got: " .. tostring(pk))
end

do
    TEST "verify_commit returns false on unsigned commit"
    reset_repo()
    local h = commit_unsigned("plain")
    local ok = verify_commit(DIR, h)
    assert(ok == false, "expected false")
end

do
    TEST "verify_commit fails on tampered commit"
    reset_repo()
    local h = commit_signed(K1, "orig")
    exec("git -C " .. DIR .. " commit --amend --allow-empty -q -m 'tampered' --no-gpg-sign")
    local h2 = exec("git -C " .. DIR .. " rev-parse HEAD")
    local ok = verify_commit(DIR, h2)
    assert(ok == false, "tampered commit should not verify")
end

do
    TEST "extract_pubkey distinguishes key2 from key1"
    reset_repo()
    local h = commit_signed(K2, "by key2")
    local pk = extract_pubkey(DIR, h)
    assert(pk == PUB2, "got: " .. tostring(pk))
    assert(pk ~= PUB1, "must differ from key1")
end

print("<== ALL PASSED")
