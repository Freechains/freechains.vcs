#!/bin/bash
#
# b2: Chain Persistence — Block Creation & Read-back
#
# Kotlin original (b2_chain):
#   Join a chain, reload it, create a block, verify block persistence.
#
# New test:
#   A "block" is a git commit inside a chain's bare repo.
#   The payload is a git blob, referenced via a tree object.
#
#   We test:
#     1. Create a block (genesis) with a payload in a bare repo
#     2. Read back the payload via git cat-file
#     3. HEAD points to the new commit
#     4. Create a second block with a parent link
#     5. git log shows both blocks in order
#     6. "Reload" — re-read chain state from disk, verify persistence
#     7. Block with extra headers (freechains-pubkey, freechains-sig)
#     8. Empty-tree commit (like/dislike: no payload)
#

source "$(dirname "$0")/common.sh"

DIR=/tmp/freechains/tests/b2
rm -rf "$DIR"
mkdir -p "$DIR"

# --- Helper: host_init (same as b1) ---
host_init () {
    local base="$1"
    mkdir -p "$base/chains" "$base/keys" 2>/dev/null || return 1
}

# --- Helper: chain_join (same as b1) ---
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
    ln -sf "$hash" "$base/chains/$name"
    echo "$hash"
}

# --- Helper: block_create <repo> <payload> [parent_hash] ---
# Creates a block (commit) in a bare repo.
# Returns the commit hash.
block_create () {
    local repo="$1"
    local payload="$2"
    local parent="${3:-}"

    # 1. Create blob from payload
    local blob_hash
    blob_hash=$(echo -n "$payload" | GIT_DIR="$repo" git hash-object -w --stdin)

    # 2. Create tree pointing to the blob (filename: "payload")
    local tree_hash
    tree_hash=$(echo -e "100644 blob $blob_hash\tpayload" | GIT_DIR="$repo" git mktree)

    # 3. Create commit
    local parent_flag=""
    [ -n "$parent" ] && parent_flag="-p $parent"

    local commit_hash
    commit_hash=$(GIT_AUTHOR_NAME=freechains GIT_AUTHOR_EMAIL=freechains@localhost \
        GIT_COMMITTER_NAME=freechains GIT_COMMITTER_EMAIL=freechains@localhost \
        GIT_AUTHOR_DATE="2025-01-01T00:00:00+0000" GIT_COMMITTER_DATE="2025-01-01T00:00:00+0000" \
        GIT_DIR="$repo" git commit-tree $tree_hash $parent_flag -m "block")

    # 4. Update HEAD
    GIT_DIR="$repo" git update-ref refs/heads/main "$commit_hash"

    echo "$commit_hash"
}

# --- Helper: block_payload <repo> <commit_hash> ---
# Reads the payload blob from a commit.
block_payload () {
    local repo="$1"
    local commit="$2"

    local tree_hash
    tree_hash=$(GIT_DIR="$repo" git cat-file -p "$commit" | sed -n 's/^tree //p')

    local blob_hash
    blob_hash=$(GIT_DIR="$repo" git cat-file -p "$tree_hash" | awk '{print $3}')

    GIT_DIR="$repo" git cat-file blob "$blob_hash"
}

# --- Helper: block_create_raw <repo> <payload> <extra_headers> [parent_hash] ---
# Creates a block with extra headers (raw commit object).
block_create_raw () {
    local repo="$1"
    local payload="$2"
    local extra_headers="$3"
    local parent="${4:-}"

    # 1. Create blob
    local blob_hash
    blob_hash=$(echo -n "$payload" | GIT_DIR="$repo" git hash-object -w --stdin)

    # 2. Create tree
    local tree_hash
    tree_hash=$(echo -e "100644 blob $blob_hash\tpayload" | GIT_DIR="$repo" git mktree)

    # 3. Build raw commit object
    local raw="tree $tree_hash"
    [ -n "$parent" ] && raw="$raw
parent $parent"
    raw="$raw
author freechains <freechains@localhost> 1735689600 +0000
committer freechains <freechains@localhost> 1735689600 +0000
$extra_headers

block"

    # 4. Hash and store
    local commit_hash
    commit_hash=$(echo "$raw" | GIT_DIR="$repo" git hash-object -t commit -w --stdin)

    # 5. Update HEAD
    GIT_DIR="$repo" git update-ref refs/heads/main "$commit_hash"

    echo "$commit_hash"
}

# ======================================================
# Setup: init host, join chain
# ======================================================

host_init "$DIR/host0"
HASH=$(chain_join "$DIR/host0" '#test')
REPO="$DIR/host0/chains/$HASH"

# ======================================================
# Test 1: Genesis block (no parent)
# ======================================================

PAYLOAD1="Hello, Freechains!"
BLOCK1=$(block_create "$REPO" "$PAYLOAD1")

# commit exists
assert_ok "GIT_DIR='$REPO' git cat-file -t '$BLOCK1' | grep -q commit" "genesis is a commit"

# payload round-trip
GOT1=$(block_payload "$REPO" "$BLOCK1")
assert_eq "$PAYLOAD1" "$GOT1" "genesis payload matches"

# HEAD points to genesis
HEAD1=$(GIT_DIR="$REPO" git rev-parse refs/heads/main)
assert_eq "$BLOCK1" "$HEAD1" "HEAD is genesis"

# genesis has no parent
PARENTS1=$(GIT_DIR="$REPO" git cat-file -p "$BLOCK1" | grep -c '^parent ' || true)
assert_eq "0" "$PARENTS1" "genesis has no parent"

# ======================================================
# Test 2: Second block (with parent)
# ======================================================

PAYLOAD2="Second block"
BLOCK2=$(block_create "$REPO" "$PAYLOAD2" "$BLOCK1")

# payload round-trip
GOT2=$(block_payload "$REPO" "$BLOCK2")
assert_eq "$PAYLOAD2" "$GOT2" "second payload matches"

# HEAD advanced
HEAD2=$(GIT_DIR="$REPO" git rev-parse refs/heads/main)
assert_eq "$BLOCK2" "$HEAD2" "HEAD is second block"

# parent link correct
PARENT_OF_2=$(GIT_DIR="$REPO" git cat-file -p "$BLOCK2" | sed -n 's/^parent //p')
assert_eq "$BLOCK1" "$PARENT_OF_2" "second block parent is genesis"

# git log shows both blocks (most recent first)
LOG=$(GIT_DIR="$REPO" git log --format=%H refs/heads/main)
LOG_FIRST=$(echo "$LOG" | head -1)
LOG_SECOND=$(echo "$LOG" | tail -1)
assert_eq "$BLOCK2" "$LOG_FIRST" "log first is second block"
assert_eq "$BLOCK1" "$LOG_SECOND" "log second is genesis"

# ======================================================
# Test 3: Reload — re-read from disk
# ======================================================

# Simulate "reload": forget all shell variables, re-derive from disk
unset BLOCK1 BLOCK2 PAYLOAD1 PAYLOAD2 HEAD1 HEAD2

# Re-read HEAD
RELOAD_HEAD=$(GIT_DIR="$REPO" git rev-parse refs/heads/main)
RELOAD_PAY=$(block_payload "$REPO" "$RELOAD_HEAD")
assert_eq "Second block" "$RELOAD_PAY" "reload: HEAD payload persists"

# Walk back to genesis
RELOAD_PARENT=$(GIT_DIR="$REPO" git cat-file -p "$RELOAD_HEAD" | sed -n 's/^parent //p')
RELOAD_GEN_PAY=$(block_payload "$REPO" "$RELOAD_PARENT")
assert_eq "Hello, Freechains!" "$RELOAD_GEN_PAY" "reload: genesis payload persists"

# Genesis has no parent
RELOAD_GEN_PARENTS=$(GIT_DIR="$REPO" git cat-file -p "$RELOAD_PARENT" | grep -c '^parent ' || true)
assert_eq "0" "$RELOAD_GEN_PARENTS" "reload: genesis has no parent"

# Chain still listed
CHAINS=$(ls -1 "$DIR/host0/chains/" | sort)
assert_ok "echo '$CHAINS' | grep -qF '#test'" "reload: chain still listed"

# ======================================================
# Test 4: Block with extra headers (signing preparation)
# ======================================================

PUBKEY="ABCDEF0123456789"
SIG="deadbeefcafebabe"
HEADERS="freechains-pubkey $PUBKEY
freechains-sig $SIG"

BLOCK3=$(block_create_raw "$REPO" "signed payload" "$HEADERS" "$RELOAD_HEAD")

# extra headers present in commit object
COMMIT_RAW=$(GIT_DIR="$REPO" git cat-file -p "$BLOCK3")
GOT_PUB=$(echo "$COMMIT_RAW" | sed -n 's/^freechains-pubkey //p')
GOT_SIG=$(echo "$COMMIT_RAW" | sed -n 's/^freechains-sig //p')
assert_eq "$PUBKEY" "$GOT_PUB" "extra header: pubkey"
assert_eq "$SIG" "$GOT_SIG" "extra header: sig"

# payload still readable
GOT3=$(block_payload "$REPO" "$BLOCK3")
assert_eq "signed payload" "$GOT3" "signed block payload matches"

# ======================================================
# Test 5: Empty-tree commit (like/dislike: no payload)
# ======================================================

# Create an empty tree (git's well-known empty tree hash)
EMPTY_TREE=$(GIT_DIR="$REPO" git hash-object -t tree /dev/null)

EMPTY_COMMIT=$(GIT_DIR="$REPO" git commit-tree "$EMPTY_TREE" -p "$BLOCK3" -m "like")
GIT_DIR="$REPO" git update-ref refs/heads/main "$EMPTY_COMMIT"

# commit exists
assert_ok "GIT_DIR='$REPO' git cat-file -t '$EMPTY_COMMIT' | grep -q commit" "empty commit exists"

# tree is empty (no entries)
EMPTY_TREE_ENTRIES=$(GIT_DIR="$REPO" git cat-file -p "$EMPTY_TREE" | wc -l)
assert_eq "0" "$EMPTY_TREE_ENTRIES" "empty tree has no entries"

# parent is the signed block
EMPTY_PARENT=$(GIT_DIR="$REPO" git cat-file -p "$EMPTY_COMMIT" | sed -n 's/^parent //p')
assert_eq "$BLOCK3" "$EMPTY_PARENT" "empty commit parent is signed block"

# ======================================================
# Test 6: Binary payload (all 256 byte values)
# ======================================================

BINFILE="$DIR/binary_payload"
python3 -c "import sys; sys.stdout.buffer.write(bytes(range(256)))" > "$BINFILE" 2>/dev/null \
    || perl -e 'print map chr, 0..255' > "$BINFILE" 2>/dev/null \
    || printf '%b' "$(for i in $(seq 0 255); do printf '\\x%02x' "$i"; done)" > "$BINFILE"

BIN_BLOB=$(GIT_DIR="$REPO" git hash-object -w "$BINFILE")
BIN_TREE=$(echo -e "100644 blob $BIN_BLOB\tpayload" | GIT_DIR="$REPO" git mktree)
BIN_COMMIT=$(GIT_DIR="$REPO" git commit-tree "$BIN_TREE" -p "$EMPTY_COMMIT" -m "binary")
GIT_DIR="$REPO" git update-ref refs/heads/main "$BIN_COMMIT"

# Read back and compare
GIT_DIR="$REPO" git cat-file blob "$BIN_BLOB" > "$DIR/binary_readback"
assert_ok "cmp -s '$BINFILE' '$DIR/binary_readback'" "binary payload round-trip"

# ======================================================
# Final: full chain has 5 commits
# ======================================================

TOTAL=$(GIT_DIR="$REPO" git rev-list refs/heads/main | wc -l)
assert_eq "5" "$TOTAL" "chain has 5 blocks total"

report
