#!/bin/bash
#
# b1: Host Init
#
# Kotlin original (b1_host):
#   Host_load(dir) succeeds for a valid directory,
#   throws Permission denied for "/".
#
# New test:
#   A "host" is a base directory containing chains/ and keys/.
#   Initializing a host means creating this directory structure.
#   Each chain is a bare git repo inside chains/.
#
#   We test:
#     1. Host init creates the expected directory layout
#     2. A chain can be created (git init --bare) inside the host
#     3. Chain naming conventions (#topic, @pubkey, $private) work as symlinks
#     4. Invalid base path (/) is rejected
#     5. Listing chains returns correct results
#     6. Leaving (removing) a chain cleans up both repo and symlink
#

source "$(dirname "$0")/common.sh"

DIR=/tmp/freechains/tests/b1
rm -rf "$DIR"

# --- Helper: host_init <dir> ---
# Creates the base directory layout for a Freechains host.
# Returns 0 on success, 1 on failure.
host_init () {
    local base="$1"
    mkdir -p "$base/chains" "$base/keys" 2>/dev/null || return 1
}

# --- Helper: chain_join <host_dir> <chain_name> ---
# Creates a new chain as a bare git repo.
# Chain name can be #topic, @pubkey, $name, or a raw hash.
# Returns 0 on success, 1 on failure.
chain_join () {
    local base="$1"
    local name="$2"
    local hash
    hash=$(echo -n "$name" | openssl dgst -sha256 -hex 2>/dev/null | sed 's/.*= //')
    local repo="$base/chains/$hash"

    if [ -d "$repo" ]; then
        echo "chain already exists" >&2
        return 1
    fi

    git init --bare "$repo" -q || return 1

    # Create a symlink with the human-readable name
    ln -sf "$hash" "$base/chains/$name"

    echo "$hash"
}

# --- Helper: chain_leave <host_dir> <chain_name> ---
# Removes a chain (bare repo + symlink).
chain_leave () {
    local base="$1"
    local name="$2"

    # Resolve symlink to find the hash directory
    local link="$base/chains/$name"
    if [ ! -L "$link" ]; then
        echo "chain not found: $name" >&2
        return 1
    fi

    local hash
    hash=$(readlink "$link")
    rm -f "$link"
    rm -rf "$base/chains/$hash"
}

# --- Helper: chains_list <host_dir> ---
# Lists chain names (symlinks only, not hash dirs).
chains_list () {
    local base="$1"
    local result=""
    for f in "$base/chains"/*; do
        [ -L "$f" ] && result="$result $(basename "$f")"
    done
    echo "$result" | sed 's/^ //'
}

# --- Test 1: host_init creates directory layout ---

host_init "$DIR/host0"
assert_ok "test -d '$DIR/host0/chains'" "chains/ exists"
assert_ok "test -d '$DIR/host0/keys'"   "keys/ exists"

# --- Test 2: host_init on invalid path fails ---
#    /proc is a virtual filesystem — mkdir always fails there.

assert_fail "host_init '/proc/freechains'" "init on /proc fails"

# --- Test 3: create a topic chain (#chat) ---

HASH_CHAT=$(chain_join "$DIR/host0" '#chat')
assert_ok "test -d '$DIR/host0/chains/$HASH_CHAT'"    "#chat bare repo exists"
assert_ok "test -L '$DIR/host0/chains/#chat'"          "#chat symlink exists"
assert_ok "test -f '$DIR/host0/chains/$HASH_CHAT/HEAD'" "#chat is a git repo"

# Verify it's a bare repo
IS_BARE=$(GIT_DIR="$DIR/host0/chains/$HASH_CHAT" git config --get core.bare)
assert_eq "true" "$IS_BARE" "#chat is bare"

# --- Test 4: create an identity chain (@pubkey) ---

HASH_ID=$(chain_join "$DIR/host0" '@AB01FF')
assert_ok "test -d '$DIR/host0/chains/$HASH_ID'"     "@AB01FF bare repo exists"
assert_ok "test -L '$DIR/host0/chains/@AB01FF'"       "@AB01FF symlink exists"

# --- Test 5: create a private chain ($friends) ---

HASH_PVT=$(chain_join "$DIR/host0" '$friends')
assert_ok "test -d '$DIR/host0/chains/$HASH_PVT'"    "\$friends bare repo exists"
assert_ok "test -L '$DIR/host0/chains/\$friends'"     "\$friends symlink exists"

# --- Test 6: different chain names produce different hashes ---

assert_neq "$HASH_CHAT" "$HASH_ID"  "#chat vs @AB01FF"
assert_neq "$HASH_CHAT" "$HASH_PVT" "#chat vs \$friends"
assert_neq "$HASH_ID"   "$HASH_PVT" "@AB01FF vs \$friends"

# --- Test 7: joining the same chain twice fails ---

DUP_RET=0
chain_join "$DIR/host0" '#chat' >/dev/null 2>&1 || DUP_RET=$?
assert_eq "1" "$DUP_RET" "duplicate join fails"

# --- Test 8: chains_list returns all joined chains ---

LIST=$(chains_list "$DIR/host0")
assert_ok "echo '$LIST' | grep -q '#chat'"     "list contains #chat"
assert_ok "echo '$LIST' | grep -q '@AB01FF'"   "list contains @AB01FF"
assert_ok "echo '$LIST' | grep -qF '\$friends'" "list contains \$friends"

# --- Test 9: chain_leave removes repo and symlink ---

chain_leave "$DIR/host0" '#chat'
assert_fail "test -L '$DIR/host0/chains/#chat'"         "#chat symlink removed"
assert_fail "test -d '$DIR/host0/chains/$HASH_CHAT'"    "#chat repo removed"

# --- Test 10: leaving a non-existent chain fails ---

assert_fail "chain_leave '$DIR/host0' '#nonexistent' 2>/dev/null" "leave unknown chain fails"

# --- Test 11: after leave, list no longer contains the chain ---

LIST2=$(chains_list "$DIR/host0")
assert_fail "echo '$LIST2' | grep -q '#chat'" "list no longer contains #chat"

# --- Test 12: symlink resolves to the correct repo ---

RESOLVED=$(readlink "$DIR/host0/chains/@AB01FF")
assert_eq "$HASH_ID" "$RESOLVED" "symlink resolves to hash"

report
