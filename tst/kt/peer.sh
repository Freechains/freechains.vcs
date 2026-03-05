#!/usr/bin/env bash

echo
echo "=== TESTS-PEER ==="
echo

FC=/tmp/freechains
./clean.sh

PVT0=6F99999751DE615705B9B1A987D8422D75D16F5D55AF43520765FA8C5329F7053CCAF4839B1FDDF406552AF175613D7A247C5703683AEC6DBDF0BB3932DD8322
PUB0=3CCAF4839B1FDDF406552AF175613D7A247C5703683AEC6DBDF0BB3932DD8322
S0=--sign=$PVT0

PUB1=E14E4D7E152272D740C3CA4298D19733768DF7E74551A9472AAE384E8AB34369
PVT1=6A416117B8F7627A3910C34F8B35921B15CF1AC386E9BB20E4B94AF0EDBE24F4E14E4D7E152272D740C3CA4298D19733768DF7E74551A9472AAE384E8AB34369
S1=--sign=$PVT1

H0=--host=localhost:8400
H1=--host=localhost:8401
P0=--port=8400
P1=--port=8401

###############################################################################
echo "#### 1"

freechains-host start $FC/8400 --port=8400 &
sleep 0.5
freechains $H0 chains join "#" $PUB0

freechains-host start $FC/8401 --port=8401 &
sleep 0.5
freechains $H1 chains join "#" $PUB0

freechains-host $P0 now 0
freechains-host $P1 now 0

freechains $H0 $S0 chain "#" post inline zero
freechains $H0 $S1 chain "#" post inline xxxx
freechains $H0 $S0 chain "#" like `freechains $H0 chain "#" heads blocked` --why="like xxxx"

freechains $H0 peer localhost:8401 send "#"

# h0 <- zero <-- lxxxx
#             \- xxxx

freechains-host $P0 now 90000000
freechains-host $P1 now 90000000

echo ">>> LIKES"

h1111=`freechains $H0 chain "#" post inline 1111`
haaaa=`freechains $H1 chain "#" post inline aaaa`

#                         1111
# h0 <- zero <-- lxxxx <-/
#             \- xxxx <-/ \
#                          aaaa

! diff -q -I local $FC/8400/chains/\#/blocks/ $FC/8401/chains/\#/blocks/ || exit 1

freechains $H0 $S0 chain "#" like $h1111 --why="like 1111"
freechains $H1 $S1 chain "#" like $haaaa --why="like aaaa"

#                         111
# h0 <- zero <-- lxxxx <-/  <-- l111
#             \- xxxx <-/ \ <-- laaa
#                          aaa

freechains-host $P0 now 98000000
freechains-host $P1 now 98000000

freechains $H0 peer localhost:8401 send "#"
freechains $H1 peer localhost:8400 send "#"

diff -I local $FC/8400/chains/\#/blocks/ $FC/8401/chains/\#/blocks/ || exit 1

###############################################################################

echo
echo "=== ALL TESTS PASSED ==="
echo