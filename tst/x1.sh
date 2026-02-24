#!/bin/bash
#
# x1: Genesis Block — Deterministic Chain Identity
#
# The genesis block is the first and oldest block in a chain.
# It is deterministic: all author/timestamp fields are zeroed, and the
# commit message is a canonical serialization of (version, type).
# The commit hash becomes the unique chain identifier.
#
# We test:
#   1. Genesis creation and structure (commit, no parent, empty tree)
#   2. Commit metadata matches spec (author, email, date all zeroed)
#   3. Commit message is canonical serialization of (version, type)
#   4. Determinism: same parameters → same hash across repos
#   5. Uniqueness: different parameters → different hash
#   6. user field exclusion: not serialized, does not affect hash
#   7. All chain types: public (plain + pioneers), private, personal
#   8. Genesis hash as chain identifier across independent peers
#

source "$(dirname "$0")/common.sh"

DIR=/tmp/freechains/tests/x1
rm -rf "$DIR"
mkdir -p "$DIR"

# --- Helper: genesis_serialize ---
# Canonical serialization of (version, type) as a Lua-style literal.
# Keys are sorted alphabetically at each level. user is excluded.
#
# Usage: genesis_serialize <major> <minor> <patch> <type_name> [key=value ...]
#   pioneers="key1,key2,..."   (public chains — sorted canonically)
#   shared="x25519:..."        (private chains)
#   personal="ed25519:..."     (personal chains)
#   writeable=true|false       (personal chains; defaults to true)
genesis_serialize () {
    local major="$1" minor="$2" patch="$3" type_name="$4"
    shift 4

    local pioneers="" personal="" shared="" writeable=""
    while [ $# -gt 0 ]; do
        case "$1" in
            pioneers=*)  pioneers="${1#pioneers=}" ;;
            personal=*)  personal="${1#personal=}" ;;
            shared=*)    shared="${1#shared=}" ;;
            writeable=*) writeable="${1#writeable=}" ;;
        esac
        shift
    done

    # Build keys sub-table (keys sorted alphabetically)
    local keys_str=""
    if [ -n "$personal" ]; then
        keys_str="{personal=\"$personal\"}"
    elif [ -n "$pioneers" ]; then
        # Sort pioneers for canonical ordering
        local sorted
        sorted=$(echo "$pioneers" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
        local arr=""
        IFS=',' read -ra PARTS <<< "$sorted"
        for p in "${PARTS[@]}"; do
            [ -n "$arr" ] && arr="$arr,"
            arr="$arr\"$p\""
        done
        keys_str="{pioneers={$arr}}"
    elif [ -n "$shared" ]; then
        keys_str="{shared=\"$shared\"}"
    else
        keys_str="{}"
    fi

    # Build type sub-table (keys sorted: keys, name, writeable)
    local type_str
    if [ "$type_name" = "personal" ]; then
        [ -z "$writeable" ] && writeable="true"
        type_str="{keys=$keys_str,name=\"$type_name\",writeable=$writeable}"
    else
        type_str="{keys=$keys_str,name=\"$type_name\"}"
    fi

    echo "{type=$type_str,version={$major,$minor,$patch}}"
}

# --- Helper: genesis_create <repo> <major> <minor> <patch> <type_name> [key=value ...] ---
# Creates the genesis commit (first commit) in a bare repo.
# All author/committer fields are zeroed per the spec.
# Returns the commit hash (= chain identifier).
genesis_create () {
    local repo="$1"
    shift

    local msg
    msg=$(genesis_serialize "$@")

    # Empty tree — genesis carries no payload
    local empty_tree
    empty_tree=$(GIT_DIR="$repo" git hash-object -t tree /dev/null)

    # Deterministic commit: all fields zeroed
    local commit_hash
    commit_hash=$(
        GIT_AUTHOR_NAME="freechains" \
        GIT_AUTHOR_EMAIL="freechains" \
        GIT_AUTHOR_DATE="1970-01-01T00:00:00+0000" \
        GIT_COMMITTER_NAME="freechains" \
        GIT_COMMITTER_EMAIL="freechains" \
        GIT_COMMITTER_DATE="1970-01-01T00:00:00+0000" \
        GIT_DIR="$repo" git commit-tree "$empty_tree" -m "$msg"
    )

    GIT_DIR="$repo" git update-ref refs/heads/main "$commit_hash"
    echo "$commit_hash"
}

# ======================================================
# Test 1: Basic genesis — public chain, no keys
# ======================================================

git init --bare "$DIR/repo1" -q
GENESIS1=$(genesis_create "$DIR/repo1" 0 11 0 public)

# Genesis is a commit
assert_ok "GIT_DIR='$DIR/repo1' git cat-file -t '$GENESIS1' | grep -q commit" \
    "genesis is a commit"

# HEAD points to genesis
HEAD1=$(GIT_DIR="$DIR/repo1" git rev-parse refs/heads/main)
assert_eq "$GENESIS1" "$HEAD1" "HEAD is genesis"

# ======================================================
# Test 2: Genesis has no parent
# ======================================================

PARENTS=$(GIT_DIR="$DIR/repo1" git cat-file -p "$GENESIS1" | grep -c '^parent ' || true)
assert_eq "0" "$PARENTS" "genesis has no parent"

# ======================================================
# Test 3: Genesis has empty tree
# ======================================================

TREE_HASH=$(GIT_DIR="$DIR/repo1" git cat-file -p "$GENESIS1" | sed -n 's/^tree //p')
TREE_ENTRIES=$(GIT_DIR="$DIR/repo1" git cat-file -p "$TREE_HASH" | wc -l)
assert_eq "0" "$TREE_ENTRIES" "genesis tree is empty"

# ======================================================
# Test 4: Author/committer fields match spec
# ======================================================

AUTHOR_NAME=$(GIT_DIR="$DIR/repo1" git log -1 --format='%an' "$GENESIS1")
AUTHOR_EMAIL=$(GIT_DIR="$DIR/repo1" git log -1 --format='%ae' "$GENESIS1")
COMMITTER_NAME=$(GIT_DIR="$DIR/repo1" git log -1 --format='%cn' "$GENESIS1")
COMMITTER_EMAIL=$(GIT_DIR="$DIR/repo1" git log -1 --format='%ce' "$GENESIS1")

assert_eq "freechains" "$AUTHOR_NAME" "author name is freechains"
assert_eq "freechains" "$AUTHOR_EMAIL" "author email is freechains"
assert_eq "freechains" "$COMMITTER_NAME" "committer name is freechains"
assert_eq "freechains" "$COMMITTER_EMAIL" "committer email is freechains"

# ======================================================
# Test 5: Dates are epoch zero
# ======================================================

AUTHOR_DATE=$(GIT_DIR="$DIR/repo1" git log -1 --format='%ai' "$GENESIS1")
COMMITTER_DATE=$(GIT_DIR="$DIR/repo1" git log -1 --format='%ci' "$GENESIS1")

assert_eq "1970-01-01 00:00:00 +0000" "$AUTHOR_DATE" "author date is epoch zero"
assert_eq "1970-01-01 00:00:00 +0000" "$COMMITTER_DATE" "committer date is epoch zero"

# ======================================================
# Test 6: Commit message is canonical serialization
# ======================================================

MSG=$(GIT_DIR="$DIR/repo1" git log -1 --format='%s' "$GENESIS1")
EXPECTED='{type={keys={},name="public"},version={0,11,0}}'
assert_eq "$EXPECTED" "$MSG" "message is canonical serialization"

# ======================================================
# Test 7: Determinism — same params, two repos, same hash
# ======================================================

git init --bare "$DIR/repo2" -q
GENESIS2=$(genesis_create "$DIR/repo2" 0 11 0 public)
assert_eq "$GENESIS1" "$GENESIS2" "same params produce same hash"

# ======================================================
# Test 8: Different version → different hash
# ======================================================

git init --bare "$DIR/repo3" -q
GENESIS3=$(genesis_create "$DIR/repo3" 0 12 0 public)
assert_neq "$GENESIS1" "$GENESIS3" "different version produces different hash"

# ======================================================
# Test 9: Different type name → different hash
# ======================================================

git init --bare "$DIR/repo4" -q
GENESIS4=$(genesis_create "$DIR/repo4" 0 11 0 private)
assert_neq "$GENESIS1" "$GENESIS4" "different type produces different hash"

# ======================================================
# Test 10: user field does not affect hash
# ======================================================

# The user field is not part of the serialization.
# Two genesis blocks with same (version, type) but different "user"
# values produce the same hash. Since genesis_create excludes user
# entirely, we verify a third repo matches repo1 exactly.
git init --bare "$DIR/repo5" -q
GENESIS5=$(genesis_create "$DIR/repo5" 0 11 0 public)
assert_eq "$GENESIS1" "$GENESIS5" "user excluded — hash unchanged"

# ======================================================
# Test 11: Public chain with pioneers
# ======================================================

git init --bare "$DIR/repo6" -q
GENESIS6=$(genesis_create "$DIR/repo6" 0 11 0 public pioneers="ed25519:abc,ed25519:xyz")

# Pioneers change the hash
assert_neq "$GENESIS1" "$GENESIS6" "pioneers change hash"

# Message contains pioneer keys
MSG6=$(GIT_DIR="$DIR/repo6" git log -1 --format='%s' "$GENESIS6")
EXPECTED6='{type={keys={pioneers={"ed25519:abc","ed25519:xyz"}},name="public"},version={0,11,0}}'
assert_eq "$EXPECTED6" "$MSG6" "pioneer message is canonical"

# Reversed input order → same hash (canonical sorting)
git init --bare "$DIR/repo6b" -q
GENESIS6B=$(genesis_create "$DIR/repo6b" 0 11 0 public pioneers="ed25519:xyz,ed25519:abc")
assert_eq "$GENESIS6" "$GENESIS6B" "pioneer order canonicalized"

# ======================================================
# Test 12: Private chain with shared key
# ======================================================

git init --bare "$DIR/repo7" -q
GENESIS7=$(genesis_create "$DIR/repo7" 0 11 0 private shared="x25519:def123")

assert_neq "$GENESIS1" "$GENESIS7" "private chain differs from public"

MSG7=$(GIT_DIR="$DIR/repo7" git log -1 --format='%s' "$GENESIS7")
EXPECTED7='{type={keys={shared="x25519:def123"},name="private"},version={0,11,0}}'
assert_eq "$EXPECTED7" "$MSG7" "private chain message correct"

# ======================================================
# Test 13: Personal chain, writeable=true
# ======================================================

git init --bare "$DIR/repo8" -q
GENESIS8=$(genesis_create "$DIR/repo8" 0 11 0 personal personal="ed25519:mypub" writeable=true)

MSG8=$(GIT_DIR="$DIR/repo8" git log -1 --format='%s' "$GENESIS8")
EXPECTED8='{type={keys={personal="ed25519:mypub"},name="personal",writeable=true},version={0,11,0}}'
assert_eq "$EXPECTED8" "$MSG8" "personal writeable=true message"

# ======================================================
# Test 14: Personal chain, writeable=false
# ======================================================

git init --bare "$DIR/repo9" -q
GENESIS9=$(genesis_create "$DIR/repo9" 0 11 0 personal personal="ed25519:mypub" writeable=false)

MSG9=$(GIT_DIR="$DIR/repo9" git log -1 --format='%s' "$GENESIS9")
EXPECTED9='{type={keys={personal="ed25519:mypub"},name="personal",writeable=false},version={0,11,0}}'
assert_eq "$EXPECTED9" "$MSG9" "personal writeable=false message"

# ======================================================
# Test 15: writeable=true vs writeable=false → different hash
# ======================================================

assert_neq "$GENESIS8" "$GENESIS9" "writeable flag changes hash"

# ======================================================
# Test 16: Personal chain defaults writeable to true
# ======================================================

git init --bare "$DIR/repo10" -q
GENESIS10=$(genesis_create "$DIR/repo10" 0 11 0 personal personal="ed25519:mypub")
assert_eq "$GENESIS8" "$GENESIS10" "personal defaults writeable=true"

# ======================================================
# Test 17: Genesis hash as chain identifier across peers
# ======================================================

git init --bare "$DIR/peer_a" -q
git init --bare "$DIR/peer_b" -q
ID_A=$(genesis_create "$DIR/peer_a" 0 11 0 public pioneers="ed25519:alice,ed25519:bob")
ID_B=$(genesis_create "$DIR/peer_b" 0 11 0 public pioneers="ed25519:alice,ed25519:bob")
assert_eq "$ID_A" "$ID_B" "chain ID matches across peers"

# The hash is a valid 40-char hex string
VALID_HEX=$(echo "$ID_A" | grep -cE '^[0-9a-f]{40}$')
assert_eq "1" "$VALID_HEX" "chain ID is 40-char hex"

report
