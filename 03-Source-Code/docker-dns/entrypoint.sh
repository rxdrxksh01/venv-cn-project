#!/bin/sh
set -eu

ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF != 4 { exit 1 }
    { for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || length($i)>3 || $i+0>255) exit 1 }
  '
}
for value in "${EDGE_IP:-}" "${TTL_TARGET_IP:-${EDGE_IP:-}}" "${UPSTREAM_DNS:-1.1.1.1}"; do
  ipv4 "$value" || { echo "Invalid IPv4 address: $value" >&2; exit 1; }
done
case "${DNS_TTL:-30}" in
  ''|*[!0-9]*) echo 'DNS_TTL must be an integer between 0 and 86400' >&2; exit 1 ;;
esac
[ "${DNS_TTL:-30}" -le 86400 ] || { echo 'DNS_TTL must be <= 86400' >&2; exit 1; }

cat > /tmp/project-dns.conf <<EOF
port=53
interface=eth0
listen-address=127.0.0.1
bind-interfaces
no-resolv
no-hosts
server=${UPSTREAM_DNS:-1.1.1.1}
domain-needed
bogus-priv
local=/team1.test/
local-ttl=${DNS_TTL:-30}
host-record=app.team1.test,${EDGE_IP}
host-record=api.team1.test,${EDGE_IP}
host-record=edge.team1.test,${EDGE_IP}
host-record=ttl-demo.team1.test,${TTL_TARGET_IP:-$EDGE_IP}
log-queries=extra
log-facility=-
EOF
dnsmasq --test --conf-file=/tmp/project-dns.conf
exec dnsmasq --keep-in-foreground --conf-file=/tmp/project-dns.conf
