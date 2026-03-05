#!/usr/bin/env bash

echo
echo "=== TESTS-PUBPVT ==="
echo

FC=/tmp/freechains
./clean.sh

# 8400 (public and private keys)
freechains-host start $FC/8400 --port=8400 &
sleep 0.5
KEYS=`freechains --host=localhost:8400 keys pubpvt correct`
PUB=`echo $KEYS | cut -d ' ' -f 1`
PVT=`echo $KEYS | cut -d ' ' -f 2`
freechains --host=localhost:8400 chains join "@$PUB"

# 8401 (no keys)
freechains-host start $FC/8401 --port=8401 &
sleep 0.5
freechains --host=localhost:8401 chains join "#"

# 8402 (public key only)
freechains-host start $FC/8402 --port=8402 &
sleep 0.5
freechains --host=localhost:8402 chains join "@$PUB"

# get genesis block of each host
g0=`freechains --host=localhost:8400 chain "@$PUB" genesis`
g1=`freechains --host=localhost:8401 chain "#" genesis`
g2=`freechains --host=localhost:8402 chain "@$PUB" genesis`

# compare them
! diff -q <(echo "$g0") <(echo "$g1") || exit 1
diff <(echo "$g0") <(echo "$g2") || exit 1

# post to 8400, send to 8401 (fail) 8402 (succees)
freechains --host=localhost:8400 --sign=$PVT chain "@$PUB" post inline Hello_World
freechains --host=localhost:8400 peer localhost:8401 send "@$PUB"  # FAIL
freechains --host=localhost:8402 peer localhost:8400 recv "@$PUB"  # SUCCESS

# compare them
! diff -q -I local $FC/8400/chains/@$PUB/blocks/ $FC/8401/chains/@$PUB/blocks/ || exit 1
diff -I local $FC/8400/chains/@$PUB/blocks/ $FC/8402/chains/@$PUB/blocks/      || exit 1

# post to 8400, send to 8401 (fail) 8402 (succees, but crypted)
h=`freechains --host=localhost:8400 --sign=$PVT --encrypt chain "@$PUB" post inline Hello_World`
freechains --host=localhost:8400 peer localhost:8401 send "@$PUB"  # FAIL
freechains --host=localhost:8400 peer localhost:8402 send "@$PUB"  # SUCCESS

freechains --host=localhost:8400 --decrypt=$PVT chain "@$PUB" get payload $h file $FC/dec.pay
diff $FC/dec.pay <(echo -n 'Hello_World') || exit 1
freechains --host=localhost:8402 chain "@$PUB" get block $h file $FC/enc.blk
diff <(jq ".pay.crypt" $FC/enc.blk) <(echo 'true') || exit 1

# stop hosts
freechains-host stop --port=8400 &
freechains-host stop --port=8401 &
freechains-host stop --port=8402 &
sleep 0.5

echo
echo "=== ALL TESTS PASSED ==="
echo