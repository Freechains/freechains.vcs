#!/bin/bash
#
# a1: Data round-trip
#
# Kotlin original (a1_json):
#   All 256 byte values survive JSON serialize/deserialize.
#
# New test:
#   Lua literal data survives a round-trip through a git blob.
#   A Lua table is serialized as a string, stored as a git blob
#   with `git hash-object -w`, read back with `git cat-file blob`,
#   and compared to the original.
#
#   We also test that raw binary (all 256 byte values) survives
#   the git blob round-trip, since git blobs are binary-safe.
#

source "$(dirname "$0")/common.sh"

DIR=/tmp/freechains/tests/a1
rm -rf "$DIR"
mkdir -p "$DIR"
git init --bare "$DIR/repo.git" -q

# --- Test 1: Lua literal table round-trip through git blob ---

LUA_DATA='return {
    name  = "test",
    value = 42,
    tags  = {"alpha", "beta", "gamma"},
    nested = {
        x = 1.5,
        y = true,
        z = "hello world",
    },
}'

HASH=$(echo -n "$LUA_DATA" | GIT_DIR="$DIR/repo.git" git hash-object -w --stdin)
READBACK=$(GIT_DIR="$DIR/repo.git" git cat-file blob "$HASH")

assert_eq "$LUA_DATA" "$READBACK" "lua literal round-trip"

# --- Test 2: Same content produces same hash (content-addressing) ---

HASH2=$(echo -n "$LUA_DATA" | GIT_DIR="$DIR/repo.git" git hash-object -w --stdin)
assert_eq "$HASH" "$HASH2" "same content = same hash"

# --- Test 3: Different content produces different hash ---

HASH3=$(echo -n "different data" | GIT_DIR="$DIR/repo.git" git hash-object -w --stdin)
assert_neq "$HASH" "$HASH3" "different content = different hash"

# --- Test 4: All 256 byte values survive git blob round-trip ---
#
# Equivalent to Kotlin's a1_json: create a byte array with values 0..255,
# store it in a git blob, read it back, compare byte-for-byte.

for i in $(seq 0 255); do printf "\\x$(printf '%02x' "$i")"; done > "$DIR/all_bytes.bin"
HASH4=$(GIT_DIR="$DIR/repo.git" git hash-object -w -- "$DIR/all_bytes.bin")
GIT_DIR="$DIR/repo.git" git cat-file blob "$HASH4" > "$DIR/all_bytes_out.bin"
assert_ok "cmp -s '$DIR/all_bytes.bin' '$DIR/all_bytes_out.bin'" "256 byte values round-trip"

# --- Test 5: Empty payload ---

HASH5=$(echo -n "" | GIT_DIR="$DIR/repo.git" git hash-object -w --stdin)
READBACK5=$(GIT_DIR="$DIR/repo.git" git cat-file blob "$HASH5")
assert_eq "" "$READBACK5" "empty payload round-trip"

# --- Test 6: Large payload (200KB, matching Kotlin's big payload test) ---

head -c 200000 /dev/zero | tr '\0' '.' > "$DIR/big.bin"
HASH6=$(GIT_DIR="$DIR/repo.git" git hash-object -w -- "$DIR/big.bin")
GIT_DIR="$DIR/repo.git" git cat-file blob "$HASH6" > "$DIR/big_out.bin"
assert_ok "cmp -s '$DIR/big.bin' '$DIR/big_out.bin'" "200KB payload round-trip"

report
