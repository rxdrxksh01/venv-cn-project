#!/bin/bash
# Point THIS Mac's DNS at the team DNS server(s).   Run on Mac 2, Mac 3 and Mac 4.
#   ./common/use-team-dns.sh primary   -> use Mac 1 as DNS server
#   ./common/use-team-dns.sh wrong     -> a bogus DNS server   (failure demo)
#   ./common/use-team-dns.sh off       -> back to normal (router/DHCP DNS)
# Same as System Settings -> Wi-Fi -> Details -> DNS, but scripted.
source "$(dirname "$0")/../lib.sh"

case "$1" in
  primary) sudo networksetup -setdnsservers "$WIFI_SERVICE" "$MAC1_IP" ;;
  wrong)   sudo networksetup -setdnsservers "$WIFI_SERVICE" 10.255.255.254 ;;
  off)     sudo networksetup -setdnsservers "$WIFI_SERVICE" Empty ;;
  *) echo "Usage: $0 primary|wrong|off"; exit 1 ;;
esac

# Throw away answers cached under the old settings
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

echo "DNS servers for $WIFI_SERVICE now: $(networksetup -getdnsservers "$WIFI_SERVICE" | tr '\n' ' ')"
[ "$1" = off ] && exit 0
echo
echo "Test: dig app.$DOMAIN"
dig "app.$DOMAIN" | grep -E 'status:|IN[[:space:]]+A|SERVER:'
