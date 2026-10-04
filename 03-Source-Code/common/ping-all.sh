#!/bin/bash
# Task A — ping every other team Mac and save the result as evidence.
source "$(dirname "$0")/../lib.sh"

OUT="$EVIDENCE/taskA-ping-from-$(scutil --get LocalHostName).txt"
{
  echo "Ping test from $(scutil --get ComputerName) ($MY_IP) at $(date)"
  for pair in "Mac1:$MAC1_IP" "Mac2:$MAC2_IP" "Mac3:$MAC3_IP" "Mac4:$MAC4_IP"; do
    name=${pair%%:*}; ip=${pair#*:}
    [ "$ip" = "$MY_IP" ] && continue
    echo
    echo "### $name ($ip)"
    ping -c 3 -t 5 "$ip"
  done
} | tee "$OUT"
echo
echo "Saved to $OUT"
