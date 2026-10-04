#!/bin/bash
# Task D / demo steps 5 & 8: send N requests by NAME and show which backend answered each one.
#   ./common/lb-test.sh        (6 requests)
#   ./common/lb-test.sh 10
source "$(dirname "$0")/../lib.sh"

N="${1:-6}"
URL="https://app.$DOMAIN/api/status"
OUT="$EVIDENCE/lb-test-$(date +%H%M%S).txt"
echo "GET $URL  x$N" | tee "$OUT"
for i in $(seq 1 "$N"); do
  hdrs=$(curl -s -o /dev/null -D - -w 'HTTP_CODE:%{http_code} IP:%{remote_ip}\n' "$URL")
  code=$(echo "$hdrs" | sed -n 's/.*HTTP_CODE:\([0-9]*\).*/\1/p')
  ip=$(echo "$hdrs" | sed -n 's/.*IP:\([0-9.]*\).*/\1/p')
  hdr() { echo "$hdrs" | awk -F': ' -v h="$1" 'tolower($1)==h{print $2}' | tr -d '\r'; }
  printf '%2d  %s  HTTP %s  edge=%s(%s)  X-Backend: %-2s  upstream=%s\n' \
    "$i" "$(date +%T)" "${code:-ERR}" "$(hdr x-edge)" "$ip" "$(hdr x-backend)" "$(hdr x-upstream-addr)" | tee -a "$OUT"
  sleep 0.3
done
echo "Saved to $OUT"
