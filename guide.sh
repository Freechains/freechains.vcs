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
FC --root="$A" --now=$((T0+10)) chain '#chat' post inline $'Hello World\n' --sign="$KEYS/alice"
FC --root="$A" --now=$((T0+20)) chain '#chat' post inline $'I am here\n'   --sign="$KEYS/alice"

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
FC --root="$B" chain '#chat' list dag

FC --root="$A" --now=$((T0+30)) chain '#chat' post inline $'Sync me\n' --sign="$KEYS/alice"
FC --root="$B" --now=$((T0+40)) chain '#chat' sync recv localhost:$A_PORT
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
echo "############ Consensus ############"
echo

# neutral hub X clones from A, then serves on $X_PORT (hub: recv + upload)
FC --root="$X" chains add '#chat' clone localhost:$A_PORT
FC --root="$X" daemon --hub --port=$X_PORT -- --listen=127.0.0.1 --reuseaddr &
sleep 1

# Alice and Charlie post at the same time, without syncing
FC --root="$A" --now=$((T0+90)) chain '#chat' post inline $'Alice was here\n'   --sign="$KEYS/alice"
FC --root="$B" --now=$((T0+90)) chain '#chat' post inline $'Charlie was here\n' --sign="$KEYS/charlie"

FC --root="$A" chain '#chat' list dag
FC --root="$B" chain '#chat' list dag

# both send to the hub, which merges the fork by reps (Alice first)
FC --root="$A" --now=$((T0+100)) chain '#chat' sync send localhost:$X_PORT
FC --root="$B" --now=$((T0+100)) chain '#chat' sync send localhost:$X_PORT

FC --root="$X" chain '#chat' list dag
FC --root="$X" chain '#chat' list order

echo
echo "############ Hard Forks ############"
echo

# fork reference = Alice's last synced post (t = T0+90)
FORK=$((T0+90))

# Bob and Charlie adopt the canonical order, then keep posting/syncing
# to the hub over 8 days. Alice (peer A) stays offline the whole time.
FC --root="$B" --now=$((T0+110)) chain '#chat' sync recv localhost:$X_PORT

FC --root="$B" --now=$((FORK+1*DAY))   chain '#chat' post inline $'day 1\n' --sign="$KEYS/bob"
FC --root="$B" --now=$((FORK+1*DAY+5)) chain '#chat' sync send localhost:$X_PORT
# ...                                                    # (days go by)
FC --root="$B" --now=$((FORK+8*DAY))   chain '#chat' post inline $'day 8\n' --sign="$KEYS/charlie"
FC --root="$B" --now=$((FORK+8*DAY+5)) chain '#chat' sync send localhost:$X_PORT

# the hub branch is now entrenched: its own messages span 7 days
echo "-- hub X order (day 1 ... day 8):"
FC --root="$X" chain '#chat' list order

# Alice comes back and posts on her own branch, which the hub has not seen
FC --root="$A" --now=$((FORK+8*DAY+100)) chain '#chat' post inline $'Alice takes over\n' --sign="$KEYS/alice"

# A sends to X: the hub is entrenched and REFUSES to merge Alice's fork
echo "-- expected failure (the hub is entrenched):"
FC --root="$A" --now=$((FORK+8*DAY+200)) chain '#chat' sync send localhost:$X_PORT || true

echo
echo "############ DONE ############"
echo
