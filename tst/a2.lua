#!/usr/bin/env lua
--
-- a2: Symmetric encryption (Lua version)
--
-- Key derived from passphrase via SHA-256.
-- AES-256-CBC encryption via fc-crypto.sh (openssl).
--

dofile((arg[0]:match("^(.*/)") or "") .. "common.lua")

-- --- Test 1: basic encrypt/decrypt round-trip ---

local KEY = shell(FC_CRYPTO .. " shared-key 'senha secreta'")
local PLAIN = "Alo 1234"

local tmp = tmpwrite(PLAIN)
local ENC = shell("cat " .. tmp .. " | " .. FC_CRYPTO .. " shared-encrypt " .. KEY)
os.remove(tmp)

local tmp2 = tmpwrite(ENC .. "\n")
local DEC = shell("cat " .. tmp2 .. " | " .. FC_CRYPTO .. " shared-decrypt " .. KEY)
os.remove(tmp2)

assert_eq(PLAIN, DEC, "shared encrypt/decrypt")

-- --- Test 2: same passphrase produces same key ---

local KEY2 = shell(FC_CRYPTO .. " shared-key 'senha secreta'")
assert_eq(KEY, KEY2, "deterministic key derivation")

-- --- Test 3: different passphrases produce different keys ---

local K0 = shell(FC_CRYPTO .. " shared-key 'senha'")
local K1 = shell(FC_CRYPTO .. " shared-key 'senha secreta'")
local K2 = shell(FC_CRYPTO .. " shared-key 'senha super secreta'")
assert_neq(K0, K1, "different passphrase 0 vs 1")
assert_neq(K1, K2, "different passphrase 1 vs 2")
assert_neq(K0, K2, "different passphrase 0 vs 2")

-- --- Test 4: wrong key fails to decrypt correctly ---

local KEY_WRONG = shell(FC_CRYPTO .. " shared-key 'wrong password'")
local tmp3 = tmpwrite(ENC .. "\n")
local DEC_WRONG = shell("cat " .. tmp3 .. " | " .. FC_CRYPTO .. " shared-decrypt " .. KEY_WRONG .. " 2>/dev/null || echo __ERROR__")
os.remove(tmp3)
assert_neq(PLAIN, DEC_WRONG, "wrong key produces wrong output")

-- --- Test 5: ciphertext differs from plaintext ---

assert_neq(PLAIN, ENC, "ciphertext != plaintext")

-- --- Test 6: encrypt larger text ---

local BIG = string.rep("x", 10000)
local tmp4 = tmpwrite(BIG)
local ENC_BIG = shell("cat " .. tmp4 .. " | " .. FC_CRYPTO .. " shared-encrypt " .. KEY)
os.remove(tmp4)

local tmp5 = tmpwrite(ENC_BIG .. "\n")
local DEC_BIG = shell("cat " .. tmp5 .. " | " .. FC_CRYPTO .. " shared-decrypt " .. KEY)
os.remove(tmp5)
assert_eq(BIG, DEC_BIG, "large payload encrypt/decrypt")

report()
