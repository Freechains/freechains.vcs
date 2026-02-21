#!/usr/bin/env lua
--
-- a3: Asymmetric encryption + Ed25519 signing (Lua version)
--
-- Keypair generation, sealed box encrypt/decrypt,
-- Ed25519 sign/verify — all via luasodium.
--

local dir = (arg[0]:match("^(.*/)") or "./")
dofile(dir .. "common.lua")
package.path = dir .. "?.lua;" .. package.path
local crypto = require("fc-crypto")

-- --- Setup: generate two keypairs ---

local key0 = crypto.keygen()
local key1 = crypto.keygen()

local PUB0 = crypto.pubkey(key0)
local PUB1 = crypto.pubkey(key1)

-- --- Test 1: two keys are different ---

assert_neq(PUB0, PUB1, "two keypairs are different")

-- --- Test 2: asymmetric encrypt/decrypt round-trip ---

local PLAIN = "Alo 1234"
local ENC = crypto.seal_encrypt(PLAIN, key0.box_pk)
local DEC = crypto.seal_decrypt(ENC, key0)
assert_eq(PLAIN, DEC, "seal encrypt/decrypt")

-- --- Test 3: wrong key fails to decrypt ---

local DEC_WRONG = crypto.seal_decrypt(ENC, key1)
assert_eq(nil, DEC_WRONG, "wrong key fails to decrypt")

-- --- Test 4: sign and verify ---

local MSG = "hello world"
local SIG = crypto.sign(MSG, key0.sign_sk)
assert_eq(true, crypto.verify(MSG, SIG, PUB0),
          "sign/verify with correct key")

-- --- Test 5: wrong key fails to verify ---

assert_eq(false, crypto.verify(MSG, SIG, PUB1),
          "verify fails with wrong key")

-- --- Test 6: tampered message fails to verify ---

assert_eq(false, crypto.verify("tampered", SIG, PUB0),
          "verify fails with tampered message")

-- --- Test 7: encrypt longer payload ---

local LONG = "mensagem secreta com mais texto para testar"
local ENC_LONG = crypto.seal_encrypt(LONG, key0.box_pk)
local DEC_LONG = crypto.seal_decrypt(ENC_LONG, key0)
assert_eq(LONG, DEC_LONG, "longer payload seal encrypt/decrypt")

-- --- Test 8: public key extraction is stable ---

local PUB0_AGAIN = crypto.pubkey(key0)
assert_eq(PUB0, PUB0_AGAIN, "pubkey extraction is deterministic")

report()
