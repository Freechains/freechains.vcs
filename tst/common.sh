#!/bin/bash
#
# common.sh — test helper functions
#
# Source this at the top of every test file:
#   source "$(dirname "$0")/common.sh"
#

set -eu

FC_CRYPTO="$(dirname "$0")/fc-crypto.sh"
PASS=0
FAIL=0

assert_eq () {
    local label="${3:-}"
    if [ "$1" = "$2" ]; then
        PASS=$((PASS + 1))
    else
        echo "  FAIL${label:+ ($label)}: expected '$1', got '$2'" >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_neq () {
    local label="${3:-}"
    if [ "$1" != "$2" ]; then
        PASS=$((PASS + 1))
    else
        echo "  FAIL${label:+ ($label)}: expected different, got '$1'" >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_ok () {
    local label="${2:-}"
    if eval "$1" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        echo "  FAIL${label:+ ($label)}: command failed: $1" >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_fail () {
    local label="${2:-}"
    if eval "$1" >/dev/null 2>&1; then
        echo "  FAIL${label:+ ($label)}: expected failure: $1" >&2
        FAIL=$((FAIL + 1))
    else
        PASS=$((PASS + 1))
    fi
}

report () {
    if [ $FAIL -eq 0 ]; then
        echo "  OK: $PASS passed"
    else
        echo "  FAILED: $PASS passed, $FAIL failed" >&2
        exit 1
    fi
}
