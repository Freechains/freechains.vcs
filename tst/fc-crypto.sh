#!/bin/bash
#
# fc-crypto.sh — Freechains crypto primitives using SSH Ed25519 + openssl + age
#
# Usage:
#   fc-crypto.sh keygen         <dir>                   — generate Ed25519 keypair in <dir>/
#   fc-crypto.sh pubkey         <dir>                   — print raw 32-byte public key as hex
#   fc-crypto.sh sign           <dir>   < message       — sign stdin, write sig to stdout
#   fc-crypto.sh verify         <dir> <sig_file> < msg  — verify sig, exit 0 if valid
#   fc-crypto.sh shared-key     <passphrase>            — derive 256-bit key from passphrase (hex)
#   fc-crypto.sh shared-encrypt <key_hex>  < plain      — symmetric encrypt stdin to stdout (base64)
#   fc-crypto.sh shared-decrypt <key_hex>  < cipher     — symmetric decrypt stdin (base64) to stdout
#   fc-crypto.sh seal-encrypt   <pub_file> < plain      — asymmetric encrypt to SSH pubkey (binary)
#   fc-crypto.sh seal-decrypt   <pvt_file> < cipher     — asymmetric decrypt with SSH privkey (binary)
#
# <dir> contains: id_ed25519 (private) and id_ed25519.pub (public)
#

set -eu

CMD=${1:?usage: fc-crypto.sh <command> [args...]}
shift

IV="00000000000000000000000000000000"  # fixed IV (deterministic for tests)

case "$CMD" in

keygen)
    DIR=${1:?usage: fc-crypto.sh keygen <dir>}
    mkdir -p "$DIR"
    ssh-keygen -t ed25519 -f "$DIR/id_ed25519" -N "" -C "freechains" -q
    ;;

pubkey)
    DIR=${1:?usage: fc-crypto.sh pubkey <dir>}
    # Extract raw 32-byte Ed25519 public key from SSH format
    awk '{print $2}' "$DIR/id_ed25519.pub" | base64 -d | tail -c 32 | od -A n -t x1 | tr -d ' \n'
    echo
    ;;

sign)
    DIR=${1:?usage: fc-crypto.sh sign <dir>}
    TMP=$(mktemp)
    cat > "$TMP"
    ssh-keygen -Y sign -f "$DIR/id_ed25519" -n freechains "$TMP" >/dev/null 2>&1
    cat "$TMP.sig"
    rm -f "$TMP" "$TMP.sig"
    ;;

verify)
    DIR=${1:?usage: fc-crypto.sh verify <dir> <sig_file>}
    SIG=${2:?usage: fc-crypto.sh verify <dir> <sig_file>}
    TMP_SIGNERS=$(mktemp)
    PUB=$(cat "$DIR/id_ed25519.pub")
    echo "freechains $PUB" > "$TMP_SIGNERS"
    ssh-keygen -Y verify -f "$TMP_SIGNERS" -I freechains -n freechains -s "$SIG" 2>/dev/null
    RET=$?
    rm -f "$TMP_SIGNERS"
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
    PUBFILE=${1:?usage: fc-crypto.sh seal-encrypt <pub_file>}
    age -a -R "$PUBFILE"
    ;;

seal-decrypt)
    PVTFILE=${1:?usage: fc-crypto.sh seal-decrypt <pvt_file>}
    age -d -i "$PVTFILE"
    ;;

*)
    echo "unknown command: $CMD" >&2
    exit 1
    ;;
esac
