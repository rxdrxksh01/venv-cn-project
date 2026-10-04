#!/bin/bash
# Change where a record points, e.g.:
#   ./dns/point-record.sh app <MAC3_IP>     (failure demo: record points to the wrong IP)
#   ./dns/point-record.sh app <MAC2_IP>     (put it back)
# Run it on Mac 1.
source "$(dirname "$0")/../lib.sh"

NAME="$1"; NEWIP="$2"
if [ -z "$NAME" ] || ! [[ "$NEWIP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <app|api|...> <new-ip>"; exit 1
fi

CONF="$BREW_PREFIX/etc/dnsmasq.conf"
grep -q "^host-record=$NAME\.$DOMAIN," "$CONF" || { echo "No record for $NAME.$DOMAIN in $CONF"; exit 1; }

echo "Before: $(grep "^host-record=$NAME\.$DOMAIN," "$CONF")"
sed -i '' "s/^host-record=$NAME\.$DOMAIN,.*/host-record=$NAME.$DOMAIN,$NEWIP/" "$CONF"
echo "After : $(grep "^host-record=$NAME\.$DOMAIN," "$CONF")"

sudo brew services restart dnsmasq >/dev/null
sleep 1
echo "$(date +%T)  dnsmasq now answers:"
dig @127.0.0.1 "$NAME.$DOMAIN" +noall +answer
