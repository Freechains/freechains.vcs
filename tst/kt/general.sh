#!/usr/bin/env bash

echo
echo "=== TESTS-GENERAL ==="
echo

FC=/tmp/freechains
./clean.sh

PVT=6F99999751DE615705B9B1A987D8422D75D16F5D55AF43520765FA8C5329F7053CCAF4839B1FDDF406552AF175613D7A247C5703683AEC6DBDF0BB3932DD8322
PUB=3CCAF4839B1FDDF406552AF175613D7A247C5703683AEC6DBDF0BB3932DD8322

###############################################################################
echo "#### 1"

freechains-host start $FC/8400 --port=8400 &
sleep 0.5
freechains --host=localhost:8400 chains join "@!$PUB"
freechains-host --port=8400 now 0
g=`freechains --host=localhost:8400 chain "@!$PUB" genesis`
h=`freechains --host=localhost:8400 --sign=$PVT chain "@!$PUB" post inline Hello_World`
freechains --host=localhost:8400 chain "@!$PUB" get block "$h" file $FC/freechains-tests-get-1.out
freechains --host=localhost:8400 chain "@!$PUB" get block 0_5A4D0352572474796BB1E4878D8AB12F749C7BC335AA76D71D4B5239BF6B68F4 file $FC/freechains-tests-get-0.out
hs=`freechains --host=localhost:8400 chain "@!$PUB" heads`
freechains --host=localhost:8400 chain "@!$PUB" get block "$g" file $FC/freechains-tests-gen.out
freechains --host=localhost:8400 chain "@!$PUB" get block "$hs" file $FC/freechains-tests-heads.out

diff -I local $FC/freechains-tests-gen.out   chk/freechains-tests-get-0.out || exit 1
diff -I local $FC/freechains-tests-get-0.out chk/freechains-tests-get-0.out || exit 1
diff -I local -I time -I hash $FC/freechains-tests-get-1.out chk/freechains-tests-get-1.out || exit 1
diff -I local -I time -I hash $FC/freechains-tests-heads.out chk/freechains-tests-get-1.out || exit 1

###############################################################################

h=`freechains --host=localhost:8400 --sign=$PVT chain "@!$PUB" post file /bin/cat`
echo $h
freechains --host=localhost:8400 chain "@!$PUB" get payload "$h" file /tmp/cat
diff /tmp/cat /bin/cat || exit 1

###############################################################################
echo "#### 2"

freechains-host start $FC/8401 --port=8401 &
sleep 0.5
freechains-host --port=8401 now 0
freechains --host=localhost:8401 chains join "@!$PUB"
echo 111 | freechains --host=localhost:8400 --sign=$PVT chain "@!$PUB" post -
freechains --host=localhost:8400 --sign=$PVT chain "@!$PUB" post inline 222
freechains --host=localhost:8400 peer localhost:8401 send "@!$PUB"

diff -I local "$FC/8400/chains/@!$PUB/blocks/" "$FC/8401/chains/@!$PUB/blocks/" || exit 1
ret=`ls $FC/8400/chains/@!$PUB/blocks/ | wc`
if [ "$ret" != "     10      10     710" ]; then
  echo "$ret"
  exit 1
fi

###############################################################################
echo "#### 3"

rm -Rf $FC/8402
freechains-host start $FC/8402 --port=8402 &
sleep 0.5
freechains-host --port=8402 now 0
freechains --host=localhost:8402 chains join "@!$PUB"
freechains --host=localhost:8402 peer localhost:8400 recv "@!$PUB" &
P1=$!
freechains --host=localhost:8401 peer localhost:8402 send "@!$PUB" &
P2=$!
wait $P1 $P2
#sleep 10

diff -I local "$FC/8401/chains/@!$PUB/blocks/" "$FC/8402/chains/@!$PUB/blocks/" || exit 1
ret=`ls "$FC/8401/chains/@!$PUB/blocks/" | wc`
if [ "$ret" != "     10      10     710" ]; then
  echo "$ret"
  exit 1
fi

#exit 0

###############################################################################
###############################################################################
echo "#### 4"

for i in $(seq 1 50)
do
  freechains --host=localhost:8400 --sign=$PVT chain "@!$PUB" post inline $i
done
freechains --host=localhost:8400 peer localhost:8401 send "@!$PUB"
freechains --host=localhost:8400 peer localhost:8402 send "@!$PUB"

diff -I local $FC/8400/chains/@!$PUB/blocks/ $FC/8401/chains/@!$PUB/blocks/ || exit 1
diff -I local $FC/8401/chains/@!$PUB/blocks/ $FC/8402/chains/@!$PUB/blocks/ || exit 1
ret=`ls $FC/8401/chains/@!$PUB/blocks/ | wc`
if [ "$ret" != "    110     110    7900" ]; then
  echo "$ret"
  exit 1
fi

###############################################################################
echo "#### 5"

for i in $(seq 8411 8430)
do
  freechains-host start $FC/$i --port=$i &
  sleep 0.5
  freechains-host --port=$i now 0
  freechains --host=localhost:$i chains join "@!$PUB"
done

echo "#### 5.1"

for i in $(seq 8411 8420)
do
  freechains --host=localhost:8400 peer localhost:$i send "@!$PUB"
done

echo "#### 5.2"

for i in $(seq 8411 8420)
do
  echo ">>> $i"
  diff -I local "$FC/8400/chains/@!$PUB/blocks/" "$FC/$i/chains/@!$PUB/blocks/" || exit 1
done

for i in $(seq 8411 8420)
do
  freechains --host=localhost:$(($i+10)) peer localhost:$i recv "@!$PUB" &
done

echo "### SLEEP ###"
sleep 30

for i in $(seq 8421 8430)
do
  diff -I local "$FC/8400/chains/@!$PUB/blocks/" "$FC/$i/chains/@!$PUB/blocks/" || exit 1
done

###############################################################################

echo
echo "=== ALL TESTS PASSED ==="
echo
