#!/bin/bash
# Mac 2: temporarily serve ONLY the public CA certificate on the LAN so the other Macs can
# download it with ./common/trust-ca.sh. Press Ctrl+C once everyone has it.
source "$(dirname "$0")/../lib.sh"

[ -f "$ROOT/edge/ca-public/ca.crt" ] || { echo "Run ./edge/make-certs.sh first"; exit 1; }
echo "Serving http://$MY_IP:8000/ca.crt  (only ca.crt — the private keys are NOT in this folder)"
cd "$ROOT/edge/ca-public" && python3 -m http.server 8000
