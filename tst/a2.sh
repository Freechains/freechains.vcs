#!/bin/bash
#
# a2: Symmetric encryption (shared key)
#
# Kotlin original (a2_shared):
#   Encrypt "Alo 1234" with a shared key derived from a passphrase,
#   decrypt it, verify it matches.
#
# New test:
#   Uses openssl AES-256-CBC for symmetric encryption.
#   Key derived from passphrase via SHA-256.
#

source "$(dirname "$0")/common.sh"

# --- Test 1: basic encrypt/decrypt round-trip ---

KEY=$("$FC_CRYPTO" shared-key "senha secreta")
PLAIN="Alo 1234"
ENC=$(echo -n "$PLAIN" | "$FC_CRYPTO" shared-encrypt "$KEY")
DEC=$(echo "$ENC" | "$FC_CRYPTO" shared-decrypt "$KEY")

assert_eq "$PLAIN" "$DEC" "shared encrypt/decrypt"

# --- Test 2: same passphrase produces same key ---

KEY2=$("$FC_CRYPTO" shared-key "senha secreta")
assert_eq "$KEY" "$KEY2" "deterministic key derivation"

# --- Test 3: different passphrases produce different keys ---
#    (mirrors Kotlin's m02_crypto_passphrase)

K0=$("$FC_CRYPTO" shared-key "senha")
K1=$("$FC_CRYPTO" shared-key "senha secreta")
K2=$("$FC_CRYPTO" shared-key "senha super secreta")
assert_neq "$K0" "$K1" "different passphrase 0 vs 1"
assert_neq "$K1" "$K2" "different passphrase 1 vs 2"
assert_neq "$K0" "$K2" "different passphrase 0 vs 2"

# --- Test 4: wrong key fails to decrypt correctly ---

KEY_WRONG=$("$FC_CRYPTO" shared-key "wrong password")
DEC_WRONG=$(echo "$ENC" | "$FC_CRYPTO" shared-decrypt "$KEY_WRONG" 2>/dev/null || echo "__ERROR__")
assert_neq "$PLAIN" "$DEC_WRONG" "wrong key produces wrong output"

# --- Test 5: ciphertext differs from plaintext ---

assert_neq "$PLAIN" "$ENC" "ciphertext != plaintext"

# --- Test 6: encrypt larger text ---

BIG=$(head -c 10000 /dev/zero | tr '\0' 'x')
ENC_BIG=$(echo -n "$BIG" | "$FC_CRYPTO" shared-encrypt "$KEY")
DEC_BIG=$(echo "$ENC_BIG" | "$FC_CRYPTO" shared-decrypt "$KEY")
assert_eq "$BIG" "$DEC_BIG" "large payload encrypt/decrypt"

report
