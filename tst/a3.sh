#!/bin/bash
#
# a3: Asymmetric encryption + Ed25519 signing
#
# Kotlin original (a3_pubpvt):
#   Encrypt "Alo 1234" with a public key, decrypt with private key.
#
# New test:
#   - Ed25519 keypair generation via ssh-keygen
#   - Asymmetric encryption via age (encrypt to SSH pubkey, decrypt with SSH privkey)
#   - Ed25519 signing and verification via ssh-keygen -Y
#

source "$(dirname "$0")/common.sh"

DIR=/tmp/freechains/tests/a3
rm -rf "$DIR"
mkdir -p "$DIR"

# --- Setup: generate two keypairs ---

"$FC_CRYPTO" keygen "$DIR/key0"
"$FC_CRYPTO" keygen "$DIR/key1"

PUB0=$("$FC_CRYPTO" pubkey "$DIR/key0")
PUB1=$("$FC_CRYPTO" pubkey "$DIR/key1")

# --- Test 1: two keys are different ---

assert_neq "$PUB0" "$PUB1" "two keypairs are different"

# --- Test 2: asymmetric encrypt/decrypt round-trip (SealedBox equivalent) ---

PLAIN="Alo 1234"
ENC=$(echo -n "$PLAIN" | "$FC_CRYPTO" seal-encrypt "$DIR/key0/id_ed25519.pub")
DEC=$(echo "$ENC" | "$FC_CRYPTO" seal-decrypt "$DIR/key0/id_ed25519")
assert_eq "$PLAIN" "$DEC" "seal encrypt/decrypt"

# --- Test 3: wrong key fails to decrypt ---

DEC_WRONG=$(echo "$ENC" | "$FC_CRYPTO" seal-decrypt "$DIR/key1/id_ed25519" 2>/dev/null || echo "__ERROR__")
assert_neq "$PLAIN" "$DEC_WRONG" "wrong key fails to decrypt"

# --- Test 4: sign and verify ---

echo -n "hello world" > "$DIR/msg.txt"
"$FC_CRYPTO" sign "$DIR/key0" < "$DIR/msg.txt" > "$DIR/msg.sig"
assert_ok "'$FC_CRYPTO' verify '$DIR/key0' '$DIR/msg.sig' < '$DIR/msg.txt'" "sign/verify with correct key"

# --- Test 5: wrong key fails to verify ---

assert_fail "'$FC_CRYPTO' verify '$DIR/key1' '$DIR/msg.sig' < '$DIR/msg.txt'" "verify fails with wrong key"

# --- Test 6: tampered message fails to verify ---

echo -n "tampered" > "$DIR/msg_bad.txt"
assert_fail "'$FC_CRYPTO' verify '$DIR/key0' '$DIR/msg.sig' < '$DIR/msg_bad.txt'" "verify fails with tampered message"

# --- Test 7: encrypt longer payload ---

LONG="mensagem secreta com mais texto para testar"
ENC_LONG=$(echo -n "$LONG" | "$FC_CRYPTO" seal-encrypt "$DIR/key0/id_ed25519.pub")
DEC_LONG=$(echo "$ENC_LONG" | "$FC_CRYPTO" seal-decrypt "$DIR/key0/id_ed25519")
assert_eq "$LONG" "$DEC_LONG" "longer payload seal encrypt/decrypt"

# --- Test 8: public key extraction is stable ---

PUB0_AGAIN=$("$FC_CRYPTO" pubkey "$DIR/key0")
assert_eq "$PUB0" "$PUB0_AGAIN" "pubkey extraction is deterministic"

report
