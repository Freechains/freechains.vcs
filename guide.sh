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

# same as FC, but also keeps the printed id in $HASH, for the commands
# that take an action id later on (votes, revokes, abandon)
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

FC --root="$A" --now=$((T0+0))  chains add /chat init --pioneer="$KEYS/alice"
FCH --root="$A" --now=$((T0+10)) chain /chat post inline $'Hello World\n' --sign="$KEYS/alice"
HELLO=$HASH
FCH --root="$A" --now=$((T0+20)) chain /chat post inline $'I am here\n'   --sign="$KEYS/alice"
HERE=$HASH

# DAG (A):
#   'Hello World'
#         |
#   'I am here'
FC --root="$A" chain /chat list dag
FC --root="$A" chain /chat list order

# each action can be queried individually: its payload and its metadata
FC --root="$A" chain /chat get payload "$HELLO"
FC --root="$A" chain /chat get payload "$HERE"
FC --root="$A" chain /chat get metadata "$HERE"

echo
echo "############ Synchronization ############"
echo

# peer A serves on $A_PORT (upload-pack)
# --listen=127.0.0.1 forces IPv4-only: a dual-stack [::] bind would
# reserve the port and then fail its own 0.0.0.0 bind
FC --root="$A" daemon start --port=$A_PORT -- --listen=127.0.0.1 --reuseaddr &
sleep 1

FC --root="$B" chains add /chat clone localhost:$A_PORT

# DAG (B): same as A after the clone
#   'Hello World'
#         |
#   'I am here'
FC --root="$B" chain /chat list dag

FC --root="$A" --now=$((T0+30)) chain /chat post inline $'Sync me\n' --sign="$KEYS/alice"
FC --root="$B" chain /chat sync recv localhost:$A_PORT

# DAG (B): grows with the received post
#   'Hello World'
#         |
#   'I am here'
#         |
#   'Sync me'
FC --root="$B" chain /chat list dag

echo
echo "############ Reputation ############"
echo

ssh-keygen -t ed25519 -C '' -N '' -q -f "$KEYS/bob"

# Bob has no reps yet: this post is expected to fail
echo "-- expected failure:"
FC --root="$B" --now=$((T0+50)) chain /chat post inline $'Possibly malicious\n' --sign="$KEYS/bob" || true

FC --root="$A" --now=$((T0+50)) chain /chat reps author "$KEYS/alice.pub"
FC --root="$B" --now=$((T0+50)) chain /chat reps author "$KEYS/bob.pub"

# Alice welcomes Bob with 10000 reps
FC --root="$A" --now=$((T0+60)) chain /chat like 10000 author "$KEYS/bob.pub" --sign="$KEYS/alice"
FC --root="$B" chain /chat sync recv localhost:$A_PORT
FC --root="$B" --now=$((T0+70)) chain /chat reps author "$KEYS/alice.pub"
FC --root="$B" --now=$((T0+70)) chain /chat reps author "$KEYS/bob.pub"

# Bob welcomes Charlie with 5000 reps
ssh-keygen -t ed25519 -C '' -N '' -q -f "$KEYS/charlie"
FC --root="$B" --now=$((T0+80)) chain /chat like 5000 author "$KEYS/charlie.pub" --sign="$KEYS/bob"
FC --root="$B" --now=$((T0+80)) chain /chat reps author "$KEYS/charlie.pub"

echo
echo "############ Posts Reputation & Begging ############"
echo

# Charlie likes and Bob dislikes Alice's first two posts: the target is a
# post, not an author, so the reps land on the content (half) and on
# Alice (half)
FC --root="$B" --now=$((T0+81)) chain /chat like    1000 action "$HELLO" --sign="$KEYS/charlie"
FC --root="$B" --now=$((T0+82)) chain /chat dislike 1000 action "$HERE"  --sign="$KEYS/bob"

# expected: 'Hello World' 450 , 'Sync me' 0 , 'I am here' -450
FC --root="$B" --now=$((T0+82)) chain /chat reps actions

# expected: alice 40000 (her two received votes cancel out), while bob
# and charlie each pay in full for the single vote they cast
FC --root="$B" --now=$((T0+82)) chain /chat reps authors

# Dave holds no reps at all, so he begs: the post is parked on
# refs/begs/, outside the chain, until someone likes it
ssh-keygen -t ed25519 -C '' -N '' -q -f "$KEYS/dave"
FCH --root="$A" --now=$((T0+83)) chain /chat post inline $'A great post!\n' --beg --sign="$KEYS/dave"
BEG=$HASH
FC --root="$A" chain /chat list begs

# Alice likes the beg, which admits both the post and its author
FC --root="$A" --now=$((T0+84)) chain /chat like 4000 action "$BEG" --sign="$KEYS/alice"
echo "-- no begs pending anymore:"
FC --root="$A" chain /chat list begs

# DAG (A): the beg merges in line (same column), and the like backs two
# posts, so the older one shows up as a (^cid) annotation row
#   like(alice->bob)
#         |
#   'A great post!'
#         |
#   like(alice->beg)
#   (^like(alice->bob))
FC --root="$A" chain /chat list dag

echo
echo "############ Consensus ############"
echo

# neutral hub X clones from A, then serves on $X_PORT (hub: recv + upload)
FC --root="$X" chains add /chat clone localhost:$A_PORT
FC --root="$X" daemon start --hub --port=$X_PORT -- --listen=127.0.0.1 --reuseaddr &
sleep 1

# Alice and Charlie post at the same time, without syncing
FC --root="$A" --now=$((T0+90)) chain /chat post inline $'Alice was here\n'   --sign="$KEYS/alice"
FC --root="$B" --now=$((T0+90)) chain /chat post inline $'Charlie was here\n' --sign="$KEYS/charlie"

# DAG (A): grows with the admitted beg and Alice's own post
#   like(alice->bob)
#         |
#   'A great post!'
#         |
#   like(alice->beg)
#         |
#   'Alice was here'
FC --root="$A" chain /chat list dag

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
FC --root="$B" chain /chat list dag

# both send to the hub, which merges the fork by reps (Alice first)
FC --root="$A" chain /chat sync send localhost:$X_PORT
FC --root="$B" chain /chat sync send localhost:$X_PORT

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
FC --root="$X" chain /chat list dag
FC --root="$X" chain /chat list order

echo
echo "############ Hard Forks ############"
echo

# fork reference = Alice's last synced post (t = T0+90)
FORK=$((T0+90))

# Bob and Charlie keep posting directly THROUGH the hub peer X (a
# peer is just a device), which already holds the merged branches.
# Alice (peer A) stays offline the whole time.
FCH --root="$X" --now=$((FORK+1*DAY)) chain /chat post inline $'day 1\n' --sign="$KEYS/bob"
DAY1=$HASH
FC --root="$X" --now=$((FORK+7*DAY)) chain /chat post inline $'day 7\n' --sign="$KEYS/charlie"

# the hub is now entrenched: measured back from its newest message, its
# history reaches 7 days (day 7 vs the fork-era posts), so everything
# before that point is settled
echo "-- hub X order (day 1 ... day 7):"
FC --root="$X" chain /chat list order

# Alice comes back and posts on her own branch, which the hub has not seen
FCH --root="$A" --now=$((FORK+7*DAY+100)) chain /chat post inline $'Alice takes over\n' --sign="$KEYS/alice"

# the post she just made (its printed cid)
REJECTED=$HASH

# A sends to X: the hub is entrenched and REFUSES to merge Alice's fork
echo "-- expected failure (the hub is entrenched):"
FC --root="$A" chain /chat sync send localhost:$X_PORT || true

# Alice's escape hatch: abandon the rejected post, receive the settled
# branch, repost the message on top of it; the hub then pulls the result
# DAG (A): untouched since the fork, plus the post the hub refused
#   like(alice->bob)
#         |
#   'Alice was here'       <-- common history
#         |
#   'Alice takes over'     <-- rejected post ($REJECTED)
echo "-- Alice's diverging branch (common history + rejected post):"
FC --root="$A" chain /chat list dag
FC --root="$A" chain /chat abandon "$REJECTED"
FC --root="$A" --now=$((FORK+7*DAY)) chain /chat sync recv localhost:$X_PORT
FC --root="$A" --now=$((FORK+7*DAY+400)) chain /chat post inline $'Alice takes over\n' --sign="$KEYS/alice"
# the hub PULLS the updated history: `--now` is local to each
# command, so the simulated clock cannot travel with a push
FC --root="$X" --now=$((FORK+7*DAY+400)) chain /chat sync recv localhost:$A_PORT

# Alice is compatible again: her repost is ordered after the settled branch
# DAG (A): the abandoned branch is replaced by the hub's settled one
#   'Alice was here'   like(bob->charlie)
#            \                |
#             \        'Charlie was here'
#              \            /
#                 'day 1'
#                    |
#                 'day 7'
#                    |
#           'Alice takes over'    <-- repost (new cid, new time)
FC --root="$A" chain /chat list dag
FC --root="$A" chain /chat list order

echo
echo "############ Moderation ############"
echo

# the 7-day fork was only a simulation: abandon it in A to return to
# the present, so the next commands need no future clock (here the
# "present" is the consensus era, right after the fork reference)
FC --root="$A" chain /chat abandon "$DAY1"

MOD=$((FORK+100))

# all members now act through peer A on the current clock
# Dave still holds the reps from his admitted beg, enough to post spam
FCH --root="$A" --now=$((MOD+0)) chain /chat post inline $'BUY NOW\n' --sign="$KEYS/dave"
SPAM=$HASH

# Alice detects the spam and revokes it with 1000 reps: the payload vanishes
FC --root="$A" --now=$((MOD+10)) chain /chat revoke 1000 "$SPAM" --sign="$KEYS/alice"
echo "-- expected failure (revoked payload):"
FC --root="$A" chain /chat get payload "$SPAM" || true

# Bob posts something he regrets and self-revokes: a self-revoke is
# free (ungated) and absolute (no community reps lift it)
FCH --root="$A" --now=$((MOD+20)) chain /chat post inline $'my address is ...\n' --sign="$KEYS/bob"
REGRET=$HASH
FC --root="$A" --now=$((MOD+30)) chain /chat revoke 1000 "$REGRET" --sign="$KEYS/bob"
echo "-- expected failure (self-revoke is absolute):"
FC --root="$A" chain /chat get payload "$REGRET" || true

echo
echo "############ DONE ############"
echo
