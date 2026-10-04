#!/bin/bash
# Task A — print this Mac's network details (run on EVERY Mac).
# Does not need team.env to be filled in: use it to find the IPs in the first place.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/evidence"
OUT="$ROOT/evidence/taskA-netinfo-$(scutil --get LocalHostName).txt"

IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
{
  echo "Hostname        : $(scutil --get ComputerName)"
  echo "Date            : $(date)"
  echo "Active interface: $IFACE"
  echo "IPv4 address    : $(ipconfig getifaddr "$IFACE")"
  echo "Subnet mask     : $(ipconfig getoption "$IFACE" subnet_mask)"
  echo "Default gateway : $(route -n get default | awk '/gateway:/{print $2}')"
  echo "MAC address     : $(ifconfig "$IFACE" | awk '/ether/{print $2}')"
  echo "DNS servers     : $(networksetup -getdnsservers Wi-Fi | tr '\n' ' ')"
  echo
  echo "--- ifconfig $IFACE ---"
  ifconfig "$IFACE"
} | tee "$OUT"

echo
echo "Saved to $OUT"
echo "Send your 'IPv4 address' to Person 1 so they can fill in team.env."
