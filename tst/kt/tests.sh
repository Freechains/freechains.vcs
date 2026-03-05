#!/usr/bin/env bash

while :
do
  ./general.sh   || exit 1
  ./peer.sh      || exit 1
  ./pubpvt.sh    || exit 1
  ./like.sh      || exit 1
  #./sync.sh      || exit 1
done