#!/bin/bash
#
# b3: Directory Replication Setup
#
# Tests the two-directory replication model:
#   - config/ is a git repo (plain files: keys, settings)
#   - chains/ contains bare git repos (one per chain)
#   - Owner peers sync both config/ and chains/ as-is via git
#   - Non-owner peers sync only chains/ with freechains rules
#
# We test:
#   1. host_init creates config/ as a git repo and chains/ dir
#   2. config/ can hold files and track them with git
#   3. Owner-to-owner replication of config/ (git clone + push/pull)
#   4. Owner-to-owner replication of chains/ (git clone per chain)
#   5. Non-owner peer can clone a chain but NOT config/
#   6. Config changes propagate between owner peers
#   7. Chain blocks propagate between owner peers as-is
#

source "$(dirname "$0")/common.sh"

DIR=/tmp/freechains/tests/b3
rm -rf "$DIR"
mkdir -p "$DIR"

# --- Helper: host_init <dir> ---
# Creates the host directory layout:
#   config/ — git working tree for configuration
#   chains/ — directory for bare chain repos
host_init () {
    local base="$1"
    mkdir -p "$base/config" "$base/chains" 2>/dev/null || return 1

    # Initialize config/ as a git repo
    git init -q "$base/config" || return 1
    git -C "$base/config" config user.name "freechains"
    git -C "$base/config" config user.email "freechains@localhost"
    git -C "$base/config" config commit.gpgsign false

    # Initial commit so we have a main branch to push/pull
    git -C "$base/config" commit -q --allow-empty -m "init" || return 1
}

# --- Helper: chain_join <host_dir> <chain_name> ---
# Creates a new chain as a bare git repo inside chains/.
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
# Creates a block (commit) in a bare repo. Returns commit hash.
block_create () {
    local repo="$1"
    local payload="$2"
    local parent="${3:-}"

    local blob_hash
    blob_hash=$(echo -n "$payload" | GIT_DIR="$repo" git hash-object -w --stdin)

    local tree_hash
    tree_hash=$(echo -e "100644 blob $blob_hash\tpayload" | GIT_DIR="$repo" git mktree)

    local parent_flag=""
    [ -n "$parent" ] && parent_flag="-p $parent"

    local commit_hash
    commit_hash=$(GIT_AUTHOR_NAME=freechains GIT_AUTHOR_EMAIL=freechains@localhost \
        GIT_COMMITTER_NAME=freechains GIT_COMMITTER_EMAIL=freechains@localhost \
        GIT_AUTHOR_DATE="2025-01-01T00:00:00+0000" GIT_COMMITTER_DATE="2025-01-01T00:00:00+0000" \
        GIT_DIR="$repo" git commit-tree $tree_hash $parent_flag -m "block")

    GIT_DIR="$repo" git update-ref refs/heads/main "$commit_hash"
    echo "$commit_hash"
}

# --- Helper: block_payload <repo> <commit_hash> ---
# Reads the payload from a block.
block_payload () {
    local repo="$1"
    local commit="$2"

    local tree_hash
    tree_hash=$(GIT_DIR="$repo" git cat-file -p "$commit" | sed -n 's/^tree //p')

    local blob_hash
    blob_hash=$(GIT_DIR="$repo" git cat-file -p "$tree_hash" | awk '{print $3}')

    GIT_DIR="$repo" git cat-file blob "$blob_hash"
}

# ======================================================
# Test 1: host_init creates config/ as git repo + chains/
# ======================================================

host_init "$DIR/peer-A"

assert_ok "test -d '$DIR/peer-A/config'"           "config/ exists"
assert_ok "test -d '$DIR/peer-A/chains'"            "chains/ exists"
assert_ok "test -d '$DIR/peer-A/config/.git'"       "config/ is a git repo"

# config has an initial commit
CONFIG_COMMITS=$(git -C "$DIR/peer-A/config" rev-list --count HEAD 2>/dev/null)
assert_eq "1" "$CONFIG_COMMITS" "config has init commit"

# ======================================================
# Test 2: config/ tracks files with git
# ======================================================

echo "port = 8330" > "$DIR/peer-A/config/config.toml"
mkdir -p "$DIR/peer-A/config/keys"
echo "PUBKEY_ABC123" > "$DIR/peer-A/config/keys/abc123.pub"

git -C "$DIR/peer-A/config" add -A
git -C "$DIR/peer-A/config" commit -q -m "add config and keys"

CONFIG_FILES=$(git -C "$DIR/peer-A/config" ls-files | sort)
assert_ok "echo '$CONFIG_FILES' | grep -q 'config.toml'"     "config.toml tracked"
assert_ok "echo '$CONFIG_FILES' | grep -q 'keys/abc123.pub'" "key file tracked"

# ======================================================
# Test 3: Owner peer B clones config/ from peer A
# ======================================================

host_init "$DIR/peer-B"

# Clone peer A's config into peer B (simulating owner-to-owner sync)
# In practice this would be over the network; here we use local paths
rm -rf "$DIR/peer-B/config"
git clone -q "$DIR/peer-A/config" "$DIR/peer-B/config"

# Verify config replicated
assert_ok "test -f '$DIR/peer-B/config/config.toml'"       "config.toml replicated"
assert_ok "test -f '$DIR/peer-B/config/keys/abc123.pub'"   "key file replicated"

GOT_PORT=$(cat "$DIR/peer-B/config/config.toml")
assert_eq "port = 8330" "$GOT_PORT" "config content matches"

GOT_KEY=$(cat "$DIR/peer-B/config/keys/abc123.pub")
assert_eq "PUBKEY_ABC123" "$GOT_KEY" "key content matches"

# ======================================================
# Test 4: Create chain on peer A, clone to peer B (owner sync)
# ======================================================

CHAIN_HASH=$(chain_join "$DIR/peer-A" '#news')
REPO_A="$DIR/peer-A/chains/$CHAIN_HASH"

# Create two blocks on the chain
BLOCK1=$(block_create "$REPO_A" "Breaking news!")
BLOCK2=$(block_create "$REPO_A" "More news!" "$BLOCK1")

# Clone chain to peer B (owner-to-owner: as-is)
git clone --bare -q "$REPO_A" "$DIR/peer-B/chains/$CHAIN_HASH"
ln -sf "$CHAIN_HASH" "$DIR/peer-B/chains/#news"

REPO_B="$DIR/peer-B/chains/$CHAIN_HASH"

# Verify all blocks transferred
TOTAL_B=$(GIT_DIR="$REPO_B" git rev-list --count refs/heads/main)
assert_eq "2" "$TOTAL_B" "both blocks replicated to peer B"

# Verify payloads match
PAY1_B=$(block_payload "$REPO_B" "$BLOCK1")
PAY2_B=$(block_payload "$REPO_B" "$BLOCK2")
assert_eq "Breaking news!" "$PAY1_B" "block 1 payload matches on peer B"
assert_eq "More news!" "$PAY2_B" "block 2 payload matches on peer B"

# ======================================================
# Test 5: Config changes on peer A propagate to peer B (pull)
# ======================================================

# Peer A updates config
echo "port = 9000" > "$DIR/peer-A/config/config.toml"
git -C "$DIR/peer-A/config" add config.toml
git -C "$DIR/peer-A/config" commit -q -m "change port"

# Peer B pulls from peer A (origin was set during clone)
# Use HEAD to avoid hardcoding branch name (master vs main)
git -C "$DIR/peer-B/config" pull -q origin HEAD

GOT_NEW_PORT=$(cat "$DIR/peer-B/config/config.toml")
assert_eq "port = 9000" "$GOT_NEW_PORT" "config update propagated"

# ======================================================
# Test 6: New blocks on peer A propagate to peer B (owner chain sync)
# ======================================================

BLOCK3=$(block_create "$REPO_A" "Third story" "$BLOCK2")

# Push new block from A to B
GIT_DIR="$REPO_A" git push -q "$REPO_B" main 2>/dev/null

TOTAL_B_AFTER=$(GIT_DIR="$REPO_B" git rev-list --count refs/heads/main)
assert_eq "3" "$TOTAL_B_AFTER" "new block propagated to peer B"

PAY3_B=$(block_payload "$REPO_B" "$BLOCK3")
assert_eq "Third story" "$PAY3_B" "block 3 payload matches on peer B"

# ======================================================
# Test 7: Non-owner peer C clones chain but NOT config
# ======================================================

mkdir -p "$DIR/peer-C/chains"

# Non-owner can clone a specific chain
git clone --bare -q "$REPO_A" "$DIR/peer-C/chains/$CHAIN_HASH"
REPO_C="$DIR/peer-C/chains/$CHAIN_HASH"

# Chain data transferred
TOTAL_C=$(GIT_DIR="$REPO_C" git rev-list --count refs/heads/main)
assert_eq "3" "$TOTAL_C" "non-owner peer C has all 3 blocks"

# Non-owner does NOT have config/
assert_fail "test -d '$DIR/peer-C/config'" "non-owner peer C has no config/"

# ======================================================
# Test 8: Peer B creates blocks, peer A fetches (bidirectional owner sync)
# ======================================================

BLOCK_B1=$(block_create "$REPO_B" "Peer B exclusive" "$BLOCK3")

# Peer A fetches from peer B
GIT_DIR="$REPO_A" git fetch -q "$REPO_B" main 2>/dev/null
GIT_DIR="$REPO_A" git merge -q FETCH_HEAD --no-edit 2>/dev/null \
    || GIT_DIR="$REPO_A" git update-ref refs/heads/main FETCH_HEAD

TOTAL_A_AFTER=$(GIT_DIR="$REPO_A" git rev-list --count refs/heads/main)
# Should have at least 4 (original 3 + peer B's 1, possibly +1 merge commit)
assert_ok "[ $TOTAL_A_AFTER -ge 4 ]" "peer A has peer B's blocks after fetch"

PAY_B1_ON_A=$(block_payload "$REPO_A" "$BLOCK_B1")
assert_eq "Peer B exclusive" "$PAY_B1_ON_A" "peer B's block readable on peer A"

# ======================================================
# Test 9: Config git history is preserved across owner peers
# ======================================================

COMMITS_A=$(git -C "$DIR/peer-A/config" rev-list --count HEAD)
COMMITS_B=$(git -C "$DIR/peer-B/config" rev-list --count HEAD)
assert_eq "$COMMITS_A" "$COMMITS_B" "config commit count matches between owner peers"

report
