#!/bin/bash
# Failure demos / troubleshooting: check each layer in the order a request uses them:
#   1 DNS config -> 2 name resolution -> 3 IP reachability -> 4 TCP port -> 5 TLS -> 6 HTTP/app
# The first FAIL tells you which layer is broken.
source "$(dirname "$0")/../lib.sh"

NAME="app.$DOMAIN"
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
info() { printf '       %s\n' "$*"; }

echo "Diagnosing https://$NAME from $(scutil --get ComputerName) ($MY_IP)"

echo; echo "[1] DNS configuration (which DNS server does this Mac ask?)"
info "Wi-Fi DNS servers: $(networksetup -getdnsservers "$WIFI_SERVICE" | tr '\n' ' ')"
[ -f "/etc/resolver/$DOMAIN" ] && info "/etc/resolver/$DOMAIN: $(tr '\n' ' ' < "/etc/resolver/$DOMAIN")"

echo; echo "[2] Name resolution (DNS layer, UDP 53)"
for s in "$MAC1_IP"; do
  a=$(dig +short +time=2 +tries=1 @"$s" "$NAME" 2>/dev/null | head -1)
  if [[ "$a" =~ ^[0-9.]+$ ]]; then ok "DNS server $s answers $NAME -> $a"; else bad "DNS server $s gives no answer"; fi
done
SYS=$(dscacheutil -q host -a name "$NAME" | awk '/ip_address/{print $2; exit}')
if [ -n "$SYS" ]; then ok "This Mac's resolver gives $NAME -> $SYS"; else bad "This Mac cannot resolve $NAME (check [1])"; fi
EDGE_IP="${SYS:-$MAC2_IP}"
[ -n "$SYS" ] && [ "$SYS" != "$MAC2_IP" ] && \
  bad "$NAME resolves to $SYS, which is NOT an edge (Mac 2 is $MAC2_IP) -> wrong DNS record"

echo; echo "[3] IP reachability (network layer, ICMP)"
if ping -c 2 -t 3 "$EDGE_IP" >/dev/null 2>&1; then ok "ping $EDGE_IP"; else bad "ping $EDGE_IP (host down, different Wi-Fi, or firewall stealth mode)"; fi

echo; echo "[4] TCP port (transport layer)"
for p in 443 80; do
  if nc -z -G 3 "$EDGE_IP" $p 2>/dev/null; then ok "TCP $EDGE_IP:$p open"; else bad "TCP $EDGE_IP:$p refused/timeout (nginx down or wrong port)"; fi
done

echo; echo "[5] TLS (handshake + certificate chain + name check)"
T=$(curl -sS -o /dev/null --max-time 5 --resolve "$NAME:443:$EDGE_IP" "https://$NAME/health" 2>&1); rc=$?
case $rc in
  0)           ok "TLS handshake OK, certificate valid for $NAME and signed by a trusted CA" ;;
  60|51|58|77) bad "Certificate problem ($T) -> CA not trusted here (./common/trust-ca.sh) or wrong cert on nginx" ;;
  35)          bad "TLS handshake failed ($T)" ;;
  *)           bad "No TLS connection (curl exit $rc: $T)" ;;
esac

echo; echo "[6] HTTP / application (through the edge)"
R=$(curl -s -o /dev/null -D - -w 'CODE:%{http_code}\n' --max-time 6 "https://$NAME/api/status")
CODE=$(echo "$R" | sed -n 's/^CODE://p')
BE=$(echo "$R" | awk -F': ' 'tolower($1)=="x-backend"{print $2}' | tr -d '\r')
case "$CODE" in
  200) ok "HTTP 200 from backend ${BE:-?}" ;;
  502|504) bad "HTTP $CODE from nginx: edge is fine, but NO backend reachable (backends down / wrong upstream)" ;;
  000|"") bad "No HTTP response (see layers above)" ;;
  *) bad "HTTP $CODE" ;;
esac

echo; echo "[7] Backends directly (can nginx's targets be reached?)"
for hp in "$MAC3_IP:$PORT_A:A" "$MAC4_IP:$PORT_B:B"; do
  IFS=: read -r h p n <<<"$hp"
  if nc -z -G 2 "$h" "$p" 2>/dev/null; then ok "Backend $n $h:$p accepting TCP"; else bad "Backend $n $h:$p not reachable from here"; fi
done
