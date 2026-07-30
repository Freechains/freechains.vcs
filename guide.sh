#!/usr/bin/env bash

# Simulates the full README guide end to end, using --now to drive time
# so the 7-day hard-fork section is reproducible. Peers A, B, X each use
# their own --root; daemons serve A (upload-pack) and the hub X
# (receive-pack + upload-pack).

set -euo pipefail

cd "$(dirname "$0")"

FC () {
    echo "\$ freechains $*"
    LUA_PATH="src/?.lua;src/?/init.lua;;" lua5.4 src/freechains.lua "$@"
}

# same as FC, but also keeps the printed hash in $HASH, for the commands
# that take a post hash later on (votes, revokes, destroy)
FCH () {
    local out
    out=$(LUA_PATH="src/?.lua;src/?/init.lua;;" lua5.4 src/freechains.lua "$@")
    echo "\$ freechains $*"
    echo "$out"
    HASH=${out##*$'\n'}
}

# roots and keys
BASE=/tmp/guide
A=$BASE/A
B=$BASE/B
X=$BASE/X
KEYS=$BASE/keys

# daemon ports (A serves, X is the hub; B does not serve)
A_PORT=10000
B_PORT=10001
X_PORT=10002

# kill daemons left over from a previous run (we do not clean up on
# exit; each run clears the old daemons on enter). Match on base-path:
# the real listener is "git-daemon" (hyphen), not "git daemon".
pkill -f "base-path=$BASE" 2>/dev/null || true
sleep 1

rm -rf "$BASE"
mkdir -p "$A" "$B" "$X" "$KEYS"

# time base (epoch seconds); increments simulate elapsed time
T0=1780000000
DAY=86400

echo
echo "############ Basics ############"
echo

ssh-keygen -t ed25519 -C '' -N '' -q -f "$KEYS/alice"

FC --root="$A" --now=$((T0+0))  chains add '#chat' init inline --sign="$KEYS/alice"
FCH --root="$A" --now=$((T0+10)) chain '#chat' post inline $'Hello World\n' --sign="$KEYS/alice"
HELLO=$HASH
FCH --root="$A" --now=$((T0+20)) chain '#chat' post inline $'I am here\n'   --sign="$KEYS/alice"
HERE=$HASH

# DAG (A):
#   'Hello World'
#         |
#   'I am here'
FC --root="$A" chain '#chat' list dag
FC --root="$A" chain '#chat' list order

echo
echo "############ Synchronization ############"
echo

# peer A serves on $A_PORT (upload-pack)
# --listen=127.0.0.1 forces IPv4-only: a dual-stack [::] bind would
# reserve the port and then fail its own 0.0.0.0 bind
FC --root="$A" daemon --port=$A_PORT -- --listen=127.0.0.1 --reuseaddr &
sleep 1

FC --root="$B" chains add '#chat' clone localhost:$A_PORT

# DAG (B): same as A after the clone
#   'Hello World'
#         |
#   'I am here'
FC --root="$B" chain '#chat' list dag

FC --root="$A" --now=$((T0+30)) chain '#chat' post inline $'Sync me\n' --sign="$KEYS/alice"
FC --root="$B" --now=$((T0+40)) chain '#chat' sync recv localhost:$A_PORT

# DAG (B): grows with the received post
#   'Hello World'
#         |
#   'I am here'
#         |
#   'Sync me'
FC --root="$B" chain '#chat' list dag

echo
echo "############ Reputation ############"
echo

ssh-keygen -t ed25519 -C '' -N '' -q -f "$KEYS/bob"

# Bob has no reps yet: this post is expected to fail
echo "-- expected failure:"
FC --root="$B" --now=$((T0+50)) chain '#chat' post inline $'Possibly malicious\n' --sign="$KEYS/bob" || true

FC --root="$A" chain '#chat' reps author "$(awk '{print $1" "$2}' "$KEYS/alice.pub")"
FC --root="$B" chain '#chat' reps author "$(awk '{print $1" "$2}' "$KEYS/bob.pub")"

# Alice welcomes Bob with 10 reps
FC --root="$A" --now=$((T0+60)) chain '#chat' like 10 author "$(awk '{print $1" "$2}' "$KEYS/bob.pub")" --sign="$KEYS/alice"
FC --root="$B" --now=$((T0+70)) chain '#chat' sync recv localhost:$A_PORT
FC --root="$B" chain '#chat' reps author "$(awk '{print $1" "$2}' "$KEYS/alice.pub")"
FC --root="$B" chain '#chat' reps author "$(awk '{print $1" "$2}' "$KEYS/bob.pub")"

# Bob welcomes Charlie with 5 reps
ssh-keygen -t ed25519 -C '' -N '' -q -f "$KEYS/charlie"
FC --root="$B" --now=$((T0+80)) chain '#chat' like 5 author "$(awk '{print $1" "$2}' "$KEYS/charlie.pub")" --sign="$KEYS/bob"
FC --root="$B" chain '#chat' reps author "$(awk '{print $1" "$2}' "$KEYS/charlie.pub")"

echo
echo "############ Posts Reputation & Begging ############"
echo

# Charlie rates Alice's first two posts: the target is a post, not an
# author, so the reps land on the content (half) and on Alice (half)
FC --root="$B" --now=$((T0+81)) chain '#chat' like    1 post "$HELLO" --sign="$KEYS/charlie"
FC --root="$B" --now=$((T0+82)) chain '#chat' dislike 1 post "$HERE"  --sign="$KEYS/charlie"

# expected: 'Hello World' 1 , 'Sync me' 0 , 'I am here' -1
FC --root="$B" chain '#chat' reps posts

# expected: alice 20 , bob 4 , charlie 3 (the two votes cancel out for
# Alice, while Charlie pays each of them in full)
FC --root="$B" chain '#chat' reps authors

# Dave holds no reps at all, so he begs: the post is parked on
# refs/begs/, outside the chain, until someone likes it
ssh-keygen -t ed25519 -C '' -N '' -q -f "$KEYS/dave"
FCH --root="$A" --now=$((T0+83)) chain '#chat' post inline $'A great post!\n' --beg --sign="$KEYS/dave"
BEG=$HASH
FC --root="$A" chain '#chat' list begs

# Alice likes the beg, which admits both the post and its author
FC --root="$A" --now=$((T0+84)) chain '#chat' like 4 post "$BEG" --sign="$KEYS/alice"
echo "-- no begs pending anymore:"
FC --root="$A" chain '#chat' list begs

# DAG (A): the beg merges in line (same column), and the like backs two
# posts, so the older one shows up as a (^hash) annotation row
#   like(alice->bob)
#         |
#   'A great post!'
#         |
#   like(alice->beg)
#   (^like(alice->bob))
FC --root="$A" chain '#chat' list dag

echo
echo "############ Consensus ############"
echo

# neutral hub X clones from A, then serves on $X_PORT (hub: recv + upload)
FC --root="$X" chains add '#chat' clone localhost:$A_PORT
FC --root="$X" daemon --hub --port=$X_PORT -- --listen=127.0.0.1 --reuseaddr &
sleep 1

# Alice and Charlie post at the same time, without syncing
FC --root="$A" --now=$((T0+90)) chain '#chat' post inline $'Alice was here\n'   --sign="$KEYS/alice"
FC --root="$B" --now=$((T0+90)) chain '#chat' post inline $'Charlie was here\n' --sign="$KEYS/charlie"

# DAG (A): grows with the admitted beg and Alice's own post
#   like(alice->bob)
#         |
#   'A great post!'
#         |
#   like(alice->beg)
#         |
#   'Alice was here'
FC --root="$A" chain '#chat' list dag

# DAG (B): same trunk up to the like on Bob, then B's own votes and post
#   like(alice->bob)
#         |
#   like(bob->charlie)
#         |
#   like(charlie->'Hello World')
#         |
#   dislike(charlie->'I am here')
#         |
#   'Charlie was here'
FC --root="$B" chain '#chat' list dag

# both send to the hub, which merges the fork by reps (Alice first)
FC --root="$A" --now=$((T0+100)) chain '#chat' sync send localhost:$X_PORT
FC --root="$B" --now=$((T0+100)) chain '#chat' sync send localhost:$X_PORT

# DAG (X): both branches arrive and the DAG forks at the like on Bob,
# which is where B last synced from A
#              like(alice->bob)
#               /          \
#   'A great post!'      like(bob->charlie)
#          |                    |
#   like(alice->beg)     like(charlie->'Hello World')
#          |                    |
#   'Alice was here'     dislike(charlie->'I am here')
#                               |
#                        'Charlie was here'
FC --root="$X" chain '#chat' list dag
FC --root="$X" chain '#chat' list order

echo
echo "############ Hard Forks ############"
echo

# fork reference = Alice's last synced post (t = T0+90)
FORK=$((T0+90))

# Bob and Charlie adopt the canonical order, then keep posting/syncing
# to the hub over 7 days. Alice (peer A) stays offline the whole time.
FC --root="$B" --now=$((T0+110)) chain '#chat' sync recv localhost:$X_PORT

FC --root="$B" --now=$((FORK+1*DAY))   chain '#chat' post inline $'day 1\n' --sign="$KEYS/bob"
FC --root="$B" --now=$((FORK+1*DAY+5)) chain '#chat' sync send localhost:$X_PORT
# ...                                                    # (days go by)
FC --root="$B" --now=$((FORK+7*DAY))   chain '#chat' post inline $'day 7\n' --sign="$KEYS/charlie"
FC --root="$B" --now=$((FORK+7*DAY+5)) chain '#chat' sync send localhost:$X_PORT

# the hub is now entrenched: measured back from its newest message, its
# history reaches 7 days (day 7 vs the fork-era posts), so everything
# before that point is settled
echo "-- hub X order (day 1 ... day 7):"
FC --root="$X" chain '#chat' list order

# Alice comes back and posts on her own branch, which the hub has not seen
FC --root="$A" --now=$((FORK+7*DAY+100)) chain '#chat' post inline $'Alice takes over\n' --sign="$KEYS/alice"

# the post she just made, one below HEAD (the state commit that follows it)
REJECTED=$(git -C "$A/chains/#chat" rev-parse HEAD^1)

# A sends to X: the hub is entrenched and REFUSES to merge Alice's fork
echo "-- expected failure (the hub is entrenched):"
FC --root="$A" --now=$((FORK+7*DAY+200)) chain '#chat' sync send localhost:$X_PORT || true

# Alice's escape hatch: destroy the rejected post, receive the settled
# branch, repost the message on top of it, and send the result
# DAG (A): untouched since the fork, plus the post the hub refused
#   like(alice->bob)
#         |
#   'Alice was here'       <-- common history
#         |
#   'Alice takes over'     <-- rejected post ($REJECTED)
echo "-- Alice's diverging branch (common history + rejected post):"
FC --root="$A" chain '#chat' list dag
FC --root="$A" chain '#chat' destroy "$REJECTED"
FC --root="$A" --now=$((FORK+7*DAY+300)) chain '#chat' sync recv localhost:$X_PORT
FC --root="$A" --now=$((FORK+7*DAY+400)) chain '#chat' post inline $'Alice takes over\n' --sign="$KEYS/alice"
FC --root="$A" --now=$((FORK+7*DAY+500)) chain '#chat' sync send localhost:$X_PORT

# Alice is compatible again: her repost is ordered after the settled branch
# DAG (A): the destroyed branch is replaced by the hub's settled one
#   'Alice was here'   like(bob->charlie)
#            \                |
#             \        'Charlie was here'
#              \            /
#                 'day 1'
#                    |
#                 'day 7'
#                    |
#           'Alice takes over'    <-- repost (new hash, new time)
FC --root="$A" chain '#chat' list dag
FC --root="$A" chain '#chat' list order

echo
echo "############ Moderation ############"
echo

MOD=$((FORK+7*DAY+600))

# Charlie spams the chain from peer B
FCH --root="$B" --now=$((MOD+0)) chain '#chat' post inline $'BUY NOW\n' --sign="$KEYS/charlie"
SPAM=$HASH
FC --root="$B" chain '#chat' get payload "$SPAM"

# Bob revokes it with 3 reps: the community channel goes to -3
FC --root="$B" --now=$((MOD+10)) chain '#chat' revoke 3 "$SPAM" --sign="$KEYS/bob"

# revoked posts print as ~hash~ and refuse their payload
FC --root="$B" chain '#chat' list order
echo "-- expected failure (revoked post):"
FC --root="$B" chain '#chat' get payload "$SPAM" || true

# a revoke is an ordinary commit, so it propagates like any other
FC --root="$B" --now=$((MOD+20)) chain '#chat' sync send localhost:$X_PORT
FC --root="$X" chain '#chat' list revokes

# Alice unrevokes with 2 reps: not enough against Bob's 3
FC --root="$A" --now=$((MOD+30)) chain '#chat' sync recv localhost:$X_PORT
FC --root="$A" --now=$((MOD+40)) chain '#chat' unrevoke 2 "$SPAM" --sign="$KEYS/alice"
echo "-- expected failure (still revoked: -3 +2 = -1):"
FC --root="$A" chain '#chat' get payload "$SPAM" || true

# both channels of the post, then of every post (author others)
FC --root="$A" chain '#chat' reps revoke "$SPAM"
FC --root="$A" chain '#chat' reps revokes

# Bob regrets a post of his own and self-revokes: free and ungated
FCH --root="$B" --now=$((MOD+50)) chain '#chat' post inline $'my address is ...\n' --sign="$KEYS/bob"
REGRET=$HASH
FC --root="$B" --now=$((MOD+60)) chain '#chat' revoke 1 "$REGRET" --sign="$KEYS/bob"

# the community channel cannot lift the author channel: Alice casts the
# attempt, since she is the only one still holding spare reps
FC --root="$B" --now=$((MOD+70)) chain '#chat' sync send localhost:$X_PORT
FC --root="$A" --now=$((MOD+80)) chain '#chat' sync recv localhost:$X_PORT
FC --root="$A" --now=$((MOD+90)) chain '#chat' unrevoke 4 "$REGRET" --sign="$KEYS/alice"
echo "-- expected failure (self-revoke is absolute):"
FC --root="$A" chain '#chat' get payload "$REGRET" || true

# only Bob can lift it, and this one does spend reps: a day goes by so
# that his own posts consolidate and refund him (`common.lua:186-207`)
FC --root="$B" chain '#chat' reps authors
FC --root="$B" --now=$((MOD+1*DAY)) chain '#chat' unrevoke 1 "$REGRET" --sign="$KEYS/bob"
FC --root="$B" chain '#chat' get payload "$REGRET"

echo
echo "############ DONE ############"
echo
