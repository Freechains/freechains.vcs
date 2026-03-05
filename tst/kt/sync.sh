#!/usr/bin/env bash

echo
echo "=== TESTS-SYNC ==="
echo

PUB=E14E4D7E152272D740C3CA4298D19733768DF7E74551A9472AAE384E8AB34369
KEY=03F09D95821EABE32055921AFAF6D8584759A86C5E3B3126DD138372C148F47D
FC=/tmp/freechains/sync/
./clean.sh

freechains-host start $FC/0 --port=8400 &
freechains-host start $FC/1 --port=8401 &
freechains-host start $FC/2 --port=8402 &
sleep 0.5

echo ==========================================================
echo === 1
echo ==========================================================

freechains --port=8400 chains join "\$sync.xxx" $KEY

freechains --port=8400 chain "\$sync.xxx" post inline "peers localhost:8400 ADD"
freechains --port=8400 chain "\$sync.xxx" post inline "peers localhost:8401 ADD"
freechains --port=8400 chain "\$sync.xxx" post inline "chains #chat ADD"

freechains --port=8401 chains join "#chat" $PUB
freechains --port=8401 chains join "\$family" $KEY
freechains --port=8401 chain "#chat"    post inline "[#chat] Hello World!"
freechains --port=8401 chain "\$family" post inline "[\$family] Hello World!"

freechains --port=8402 chains join "\$sync.xxx" $KEY
freechains-sync --port=8402 "\$sync.xxx" "localhost:8400" &
SYNC=$!
sleep 1
diff -I local $FC/1/chains/\#chat/blocks/ $FC/2/chains/\#chat/blocks/ || exit 1

echo ==========================================================
echo === 2
echo ==========================================================

kill $SYNC
freechains-sync --port=8402 "\$sync.xxx" &
sleep 0.5

freechains --port=8400 chain "\$sync.xxx" post inline "chains \$family 03F09D95821EABE32055921AFAF6D8584759A86C5E3B3126DD138372C148F47D"
freechains --port=8400 peer localhost:8402 send "\$sync.xxx"
sleep 0.5
diff -I local $FC/1/chains/\$family/blocks/ $FC/2/chains/\$family/blocks/ || exit 1

echo ==========================================================
echo === 3
echo ==========================================================

freechains-host start $FC/3 --port=8403 &
sleep 0.5
freechains --port=8403 chains join "\$sync.xxx" $KEY
#freechains --port=8403 peer "localhost:8402" recv "\$sync.xxx"
freechains-sync --port=8403 "\$sync.xxx" &
sleep 0.5

freechains --port=8402 chain "\$sync.xxx" post inline "peers localhost:8403 ADD"
freechains --port=8402 chain "\$sync.xxx" post inline "chains #new ADD"
sleep 0.5
freechains --port=8402 chain "#new" post inline "#new from 8402"
sleep 1

diff -I local $FC/2/chains/ $FC/3/chains/ || exit 1
grep -r "#new from 8402" $FC/3   || exit 1

echo ==========================================================
echo === 4
echo ==========================================================

freechains --port=8402 chain "\$sync.xxx" post inline "chains #new REM"
sleep 1
freechains --port=8402 chains join "#new"
freechains --port=8402 chain "#new" post inline "#new again from 8402"

sleep 5
grep -r "#new again from 8402" $FC/3 || exit 1  # REM is not leaving the chain
grep -r "#new again from 8402" $FC/2 || exit 1

freechains --port=8402 chain "\$sync.xxx" post inline "peers localhost:8403 REM"
sleep 1
freechains --port=8402 chain "#chat" post inline "#chat from 8402"

sleep 1
! grep -r "#chat from 8402" $FC/3 || exit 1
grep -r "#chat from 8402" $FC/2   || exit 1

echo ==========================================================
echo ==========================================================

./clean.sh

echo
echo "=== ALL TESTS PASSED ==="
echo
