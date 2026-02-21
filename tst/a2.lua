#!/usr/bin/env lua
--
-- a2: Symmetric encryption (Lua version)
--
-- Key derived from passphrase via BLAKE2b.
-- SecretBox (XSalsa20-Poly1305) encryption via luasodium.
--

local dir = (arg[0]:match("^(.*/)") or "./")
dofile(dir .. "common.lua")
package.path = dir .. "?.lua;" .. package.path
local crypto = require("fc-crypto")

-- --- Test 1: basic encrypt/decrypt round-trip ---

local KEY = crypto.shared_key("senha secreta")
local PLAIN = "Alo 1234"

local ENC = crypto.shared_encrypt(PLAIN, KEY)
local DEC = crypto.shared_decrypt(ENC, KEY)

assert_eq(PLAIN, DEC, "shared encrypt/decrypt")

-- --- Test 2: same passphrase produces same key ---

local KEY2 = crypto.shared_key("senha secreta")
assert_eq(KEY, KEY2, "deterministic key derivation")

-- --- Test 3: different passphrases produce different keys ---

local K0 = crypto.shared_key("senha")
local K1 = crypto.shared_key("senha secreta")
local K2 = crypto.shared_key("senha super secreta")
assert_neq(K0, K1, "different passphrase 0 vs 1")
assert_neq(K1, K2, "different passphrase 1 vs 2")
assert_neq(K0, K2, "different passphrase 0 vs 2")

-- --- Test 4: wrong key fails to decrypt correctly ---

local KEY_WRONG = crypto.shared_key("wrong password")
local DEC_WRONG = crypto.shared_decrypt(ENC, KEY_WRONG)
assert_eq(nil, DEC_WRONG, "wrong key fails to decrypt")

-- --- Test 5: ciphertext differs from plaintext ---

assert_neq(PLAIN, ENC, "ciphertext != plaintext")

-- --- Test 6: encrypt larger text ---

local BIG = string.rep("x", 10000)
local ENC_BIG = crypto.shared_encrypt(BIG, KEY)
local DEC_BIG = crypto.shared_decrypt(ENC_BIG, KEY)
assert_eq(BIG, DEC_BIG, "large payload encrypt/decrypt")

report()
