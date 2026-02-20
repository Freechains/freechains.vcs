#!/usr/bin/env lua
--
-- a3: Asymmetric encryption + Ed25519 signing (Lua version)
--
-- Keypair generation, seal encrypt/decrypt (X25519+AES),
-- Ed25519 sign/verify — all via fc-crypto.sh (openssl).
--

dofile((arg[0]:match("^(.*/)") or "") .. "common.lua")

local DIR = "/tmp/freechains/tests/a3_lua"
os.execute("rm -rf " .. DIR)
os.execute("mkdir -p " .. DIR)

-- --- Setup: generate two keypairs + one ephemeral for encryption ---

os.execute(FC_CRYPTO .. " keygen " .. DIR .. "/key0")
os.execute(FC_CRYPTO .. " keygen " .. DIR .. "/key1")
os.execute(FC_CRYPTO .. " keygen " .. DIR .. "/eph")

local PUB0 = shell(FC_CRYPTO .. " pubkey " .. DIR .. "/key0")
local PUB1 = shell(FC_CRYPTO .. " pubkey " .. DIR .. "/key1")

-- --- Test 1: two keys are different ---

assert_neq(PUB0, PUB1, "two keypairs are different")

-- --- Test 2: asymmetric encrypt/decrypt round-trip ---

local PLAIN = "Alo 1234"
local tmp = tmpwrite(PLAIN)
local ENC = shell("cat " .. tmp .. " | " .. FC_CRYPTO .. " seal-encrypt " .. DIR .. "/key0 " .. DIR .. "/eph")
os.remove(tmp)

local tmp2 = tmpwrite(ENC .. "\n")
local DEC = shell("cat " .. tmp2 .. " | " .. FC_CRYPTO .. " seal-decrypt " .. DIR .. "/key0 " .. DIR .. "/eph")
os.remove(tmp2)
assert_eq(PLAIN, DEC, "seal encrypt/decrypt")

-- --- Test 3: wrong key fails to decrypt correctly ---

local tmp3 = tmpwrite(ENC .. "\n")
local DEC_WRONG = shell("cat " .. tmp3 .. " | " .. FC_CRYPTO .. " seal-decrypt " .. DIR .. "/key1 " .. DIR .. "/eph 2>/dev/null || echo __ERROR__")
os.remove(tmp3)
assert_neq(PLAIN, DEC_WRONG, "wrong key produces wrong output")

-- --- Test 4: sign and verify ---

writefile(DIR .. "/msg.txt", "hello world")
os.execute(FC_CRYPTO .. " sign " .. DIR .. "/key0 < " .. DIR .. "/msg.txt > " .. DIR .. "/msg.sig")
assert_ok(FC_CRYPTO .. " verify " .. DIR .. "/key0 " .. DIR .. "/msg.sig < " .. DIR .. "/msg.txt",
          "sign/verify with correct key")

-- --- Test 5: wrong key fails to verify ---

assert_fail(FC_CRYPTO .. " verify " .. DIR .. "/key1 " .. DIR .. "/msg.sig < " .. DIR .. "/msg.txt",
            "verify fails with wrong key")

-- --- Test 6: tampered message fails to verify ---

writefile(DIR .. "/msg_bad.txt", "tampered")
assert_fail(FC_CRYPTO .. " verify " .. DIR .. "/key0 " .. DIR .. "/msg.sig < " .. DIR .. "/msg_bad.txt",
            "verify fails with tampered message")

-- --- Test 7: encrypt longer payload ---

local LONG = "mensagem secreta com mais texto para testar"
local tmp4 = tmpwrite(LONG)
local ENC_LONG = shell("cat " .. tmp4 .. " | " .. FC_CRYPTO .. " seal-encrypt " .. DIR .. "/key0 " .. DIR .. "/eph")
os.remove(tmp4)

local tmp5 = tmpwrite(ENC_LONG .. "\n")
local DEC_LONG = shell("cat " .. tmp5 .. " | " .. FC_CRYPTO .. " seal-decrypt " .. DIR .. "/key0 " .. DIR .. "/eph")
os.remove(tmp5)
assert_eq(LONG, DEC_LONG, "longer payload seal encrypt/decrypt")

-- --- Test 8: public key extraction is stable ---

local PUB0_AGAIN = shell(FC_CRYPTO .. " pubkey " .. DIR .. "/key0")
assert_eq(PUB0, PUB0_AGAIN, "pubkey extraction is deterministic")

report()
