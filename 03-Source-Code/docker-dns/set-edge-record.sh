#!/bin/sh
# Live DNS cutover for app/api only. Startup EDGE_IP in .env is unchanged.
set -eu
cd "$(dirname "$0")"
if [ "$#" -ne 1 ]; then
  echo "Usage: sh set-edge-record.sh <edge-IPv4-address>" >&2
  exit 1
fi
printf '%s\n' "$1" | awk -F. '
  NF != 4 { exit 1 }
  { for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || length($i)>3 || $i+0>255) exit 1 }
' || { echo 'Invalid IPv4 address' >&2; exit 1; }
docker compose exec -T --user 0 dns sh -eu -c '
  grep -q "^addn-hosts=/tmp/project-edge.hosts$" /tmp/project-dns.conf || {
    echo "Rebuild the updated DNS image first: docker compose up -d --build --wait" >&2
    exit 1
  }
  printf "%s app.team1.test api.team1.test\n" "$1" > /tmp/project-edge.hosts.next
  mv /tmp/project-edge.hosts.next /tmp/project-edge.hosts
  kill -HUP 1
' project-dns "$1"
echo "Changed app.team1.test and api.team1.test to $1 without restarting DNS."
echo 'Runtime override only; restart restores EDGE_IP from .env.'
