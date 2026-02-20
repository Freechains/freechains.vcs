#!/bin/bash
#
# fc-crypto.sh — Freechains crypto primitives (openssl only)
#
# Usage:
#   fc-crypto.sh keygen         <dir>                   — generate Ed25519 keypair in <dir>/
#   fc-crypto.sh pubkey         <dir>                   — print raw 32-byte public key as hex
#   fc-crypto.sh sign           <dir>   < message       — sign stdin, write signature to stdout
#   fc-crypto.sh verify         <dir> <sig_file> < msg  — verify sig, exit 0 if valid
#   fc-crypto.sh shared-key     <passphrase>            — derive 256-bit key from passphrase (hex)
#   fc-crypto.sh shared-encrypt <key_hex>  < plain      — symmetric encrypt stdin to stdout (base64)
#   fc-crypto.sh shared-decrypt <key_hex>  < cipher     — symmetric decrypt stdin (base64) to stdout
#   fc-crypto.sh seal-encrypt   <dir_pub> <dir_eph>     — asymmetric encrypt stdin to stdout (base64)
#   fc-crypto.sh seal-decrypt   <dir_pvt> <dir_eph_pub> — asymmetric decrypt stdin (base64) to stdout
#
# <dir> contains: pvt.pem (private) and pub.pem (public)
#
# Dependencies: openssl (with Ed25519 + X25519 support, i.e. OpenSSL 3.0+)
#

set -eu

CMD=${1:?usage: fc-crypto.sh <command> [args...]}
shift

IV="00000000000000000000000000000000"

case "$CMD" in

keygen)
    DIR=${1:?usage: fc-crypto.sh keygen <dir>}
    mkdir -p "$DIR"
    openssl genpkey -algorithm ed25519 -out "$DIR/pvt.pem" 2>/dev/null
    openssl pkey -in "$DIR/pvt.pem" -pubout -out "$DIR/pub.pem" 2>/dev/null
    # Also generate X25519 keypair for asymmetric encryption
    openssl genpkey -algorithm X25519 -out "$DIR/x25519_pvt.pem" 2>/dev/null
    openssl pkey -in "$DIR/x25519_pvt.pem" -pubout -out "$DIR/x25519_pub.pem" 2>/dev/null
    ;;

pubkey)
    DIR=${1:?usage: fc-crypto.sh pubkey <dir>}
    # Extract raw 32-byte Ed25519 public key from DER (last 32 bytes of 44-byte DER)
    openssl pkey -in "$DIR/pub.pem" -pubin -outform DER 2>/dev/null | tail -c 32 | od -A n -t x1 | tr -d ' \n'
    echo
    ;;

sign)
    DIR=${1:?usage: fc-crypto.sh sign <dir>}
    TMP=$(mktemp)
    cat > "$TMP"
    openssl pkeyutl -sign -inkey "$DIR/pvt.pem" -rawin -in "$TMP" -out "$TMP.sig" 2>/dev/null
    base64 < "$TMP.sig"
    rm -f "$TMP" "$TMP.sig"
    ;;

verify)
    DIR=${1:?usage: fc-crypto.sh verify <dir> <sig_file>}
    SIG_B64=${2:?usage: fc-crypto.sh verify <dir> <sig_file>}
    TMP=$(mktemp)
    TMP_SIG=$(mktemp)
    cat > "$TMP"
    base64 -d < "$SIG_B64" > "$TMP_SIG"
    openssl pkeyutl -verify -pubin -inkey "$DIR/pub.pem" -rawin -in "$TMP" -sigfile "$TMP_SIG" 2>/dev/null
    RET=$?
    rm -f "$TMP" "$TMP_SIG"
    exit $RET
    ;;

shared-key)
    PASSPHRASE=${1:?usage: fc-crypto.sh shared-key <passphrase>}
    echo -n "$PASSPHRASE" | openssl dgst -sha256 -hex 2>/dev/null | sed 's/.*= //'
    ;;

shared-encrypt)
    KEY=${1:?usage: fc-crypto.sh shared-encrypt <key_hex>}
    openssl enc -aes-256-cbc -K "$KEY" -iv "$IV" -nosalt -base64
    ;;

shared-decrypt)
    KEY=${1:?usage: fc-crypto.sh shared-decrypt <key_hex>}
    openssl enc -d -aes-256-cbc -K "$KEY" -iv "$IV" -nosalt -base64
    ;;

seal-encrypt)
    # Asymmetric encrypt: X25519 key exchange + AES-256-CBC
    # Args: <recipient_dir> <ephemeral_dir>
    # recipient_dir must have x25519_pub.pem
    # ephemeral_dir must have x25519_pvt.pem (caller generates ephemeral keypair)
    RCPT_DIR=${1:?usage: fc-crypto.sh seal-encrypt <recipient_dir> <ephemeral_dir>}
    EPH_DIR=${2:?usage: fc-crypto.sh seal-encrypt <recipient_dir> <ephemeral_dir>}
    SHARED=$(openssl pkeyutl -derive -inkey "$EPH_DIR/x25519_pvt.pem" -peerkey "$RCPT_DIR/x25519_pub.pem" 2>/dev/null | od -A n -t x1 | tr -d ' \n')
    openssl enc -aes-256-cbc -K "$SHARED" -iv "$IV" -nosalt -base64
    ;;

seal-decrypt)
    # Asymmetric decrypt: X25519 key exchange + AES-256-CBC
    # Args: <recipient_dir> <ephemeral_dir>
    # recipient_dir must have x25519_pvt.pem
    # ephemeral_dir must have x25519_pub.pem
    RCPT_DIR=${1:?usage: fc-crypto.sh seal-decrypt <recipient_dir> <ephemeral_dir>}
    EPH_DIR=${2:?usage: fc-crypto.sh seal-decrypt <recipient_dir> <ephemeral_dir>}
    SHARED=$(openssl pkeyutl -derive -inkey "$RCPT_DIR/x25519_pvt.pem" -peerkey "$EPH_DIR/x25519_pub.pem" 2>/dev/null | od -A n -t x1 | tr -d ' \n')
    openssl enc -d -aes-256-cbc -K "$SHARED" -iv "$IV" -nosalt -base64
    ;;

*)
    echo "unknown command: $CMD" >&2
    exit 1
    ;;
esac
