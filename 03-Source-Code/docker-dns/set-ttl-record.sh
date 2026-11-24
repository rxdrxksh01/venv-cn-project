#!/bin/sh
# Change only the TTL demonstration record without recreating the container.
# This runtime override lasts until container restart/recreation.
set -eu
cd "$(dirname "$0")"
if [ "$#" -ne 1 ]; then
  echo "Usage: sh set-ttl-record.sh <IPv4-address>" >&2
  exit 1
fi
printf '%s\n' "$1" | awk -F. '
  NF != 4 { exit 1 }
  { for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || length($i)>3 || $i+0>255) exit 1 }
' || { echo 'Invalid IPv4 address' >&2; exit 1; }
docker compose exec -T --user 0 dns sh -eu -c '
  grep -q "^addn-hosts=/tmp/project-ttl.hosts$" /tmp/project-dns.conf || {
    echo "Rebuild the updated DNS image first: docker compose up -d --build --wait" >&2
    exit 1
  }
  printf "%s ttl-demo.team1.test\n" "$1" > /tmp/project-ttl.hosts.next
  mv /tmp/project-ttl.hosts.next /tmp/project-ttl.hosts
  kill -HUP 1
' project-dns "$1"
echo "Changed ttl-demo.team1.test to $1; verify with dig @<this-Mac-IP> ttl-demo.team1.test"
