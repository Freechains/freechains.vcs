#!/usr/bin/env bash

echo
echo "=== CLEANING... ==="
echo

ps | grep java | awk '{print $1}' | xargs kill 2> /dev/null
sleep 0.5

rm -Rf /tmp/freechains/
mkdir /tmp/freechains/

echo
echo "=== CLEAN OK ==="
echo