#!/bin/bash
#
# a4: Sorted set difference
#
# Kotlin original (a4_minus):
#   sortedMinus(s1, s2) returns elements in s1 not in s2, maintaining sort order.
#   Tested with two pairs of sorted integer sets.
#
# New test:
#   Uses `comm -23` on sorted files — the Unix equivalent of sorted set difference.
#   This is the operation needed during peer sync to find "blocks I have that you don't"
#   (analogous to `git rev-list --left-only` or computing packfile deltas).
#
#   Files must be lexicographically sorted (as `sort` does by default),
#   which matches how git hashes are naturally compared.
#

source "$(dirname "$0")/common.sh"

DIR=/tmp/freechains/tests/a4
rm -rf "$DIR"
mkdir -p "$DIR"

# Helper: sorted set difference using comm
# Inputs must already be sorted lexicographically (one element per line).
set_minus () {
    comm -23 "$1" "$2" | tr '\n' ' ' | sed 's/ $//'
}

# Helper: create a sorted set file from arguments
set_make () {
    local file=$1; shift
    printf '%s\n' "$@" | sort > "$file"
}

# --- Test 1: {1,2,5,10} - {3,5,7,10} = {1,2} ---

set_make "$DIR/s1.txt" 1 2 5 10
set_make "$DIR/s2.txt" 3 5 7 10
RESULT=$(set_minus "$DIR/s1.txt" "$DIR/s2.txt")
assert_eq "1 2" "$RESULT" "s1 - s2"

# --- Test 2: {3,5,7,10} - {1,2,5,10} = {3,7} ---

RESULT2=$(set_minus "$DIR/s2.txt" "$DIR/s1.txt")
assert_eq "3 7" "$RESULT2" "s2 - s1"

# --- Test 3: {4,5,7,8} - {3,5,7,10} = {4,8} ---

set_make "$DIR/s3.txt" 4 5 7 8
set_make "$DIR/s4.txt" 3 5 7 10
RESULT3=$(set_minus "$DIR/s3.txt" "$DIR/s4.txt")
assert_eq "4 8" "$RESULT3" "s3 - s4"

# --- Test 4: {3,5,7,10} - {4,5,7,8} = {10,3} (lexicographic: 10 < 3) ---

RESULT4=$(set_minus "$DIR/s4.txt" "$DIR/s3.txt")
assert_eq "10 3" "$RESULT4" "s4 - s3"

# --- Test 5: set minus itself = empty ---

RESULT5=$(set_minus "$DIR/s1.txt" "$DIR/s1.txt")
assert_eq "" "$RESULT5" "s1 - s1 = empty"

# --- Test 6: set minus empty = itself ---

> "$DIR/empty.txt"
RESULT6=$(set_minus "$DIR/s1.txt" "$DIR/empty.txt")
assert_eq "1 10 2 5" "$RESULT6" "s1 - empty = s1"

# --- Test 7: empty minus set = empty ---

RESULT7=$(set_minus "$DIR/empty.txt" "$DIR/s1.txt")
assert_eq "" "$RESULT7" "empty - s1 = empty"

# --- Test 8: with hash-like strings (simulating block hashes) ---

set_make "$DIR/local.txt"  "1_AAAA" "2_BBBB" "3_CCCC" "4_DDDD"
set_make "$DIR/remote.txt" "1_AAAA" "3_CCCC"
RESULT8=$(set_minus "$DIR/local.txt" "$DIR/remote.txt")
assert_eq "2_BBBB 4_DDDD" "$RESULT8" "hash set difference"

report
