#!/bin/bash
# Task E (Mac 2): create our own local Certificate Authority (CA) and use it to sign
# a server certificate for app.<domain> and api.<domain>.
#   ca.crt      -> give to EVERY client Mac and mark as trusted (public, safe to share)
#   ca.key      -> stays on Mac 2 only (whoever has it can mint trusted certs)
#   server.crt  -> nginx presents this in the TLS handshake
#   server.key  -> nginx's private key (never leaves Mac 2)
source "$(dirname "$0")/../lib.sh"

OUT="$ROOT/edge/certs"
mkdir -p "$OUT" "$ROOT/edge/ca-public"
cd "$OUT" || exit 1

if [ ! -f ca.key ]; then
  say "Creating the team Root CA (valid 10 years)"
  cat > ca.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions    = v3_ca
prompt             = no
[dn]
CN = $TEAM Local Root CA
O  = CN Project $TEAM
[v3_ca]
basicConstraints     = critical, CA:TRUE
keyUsage             = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF
  openssl genrsa -out ca.key 2048
  openssl req -x509 -new -key ca.key -sha256 -days 3650 -config ca.cnf -out ca.crt
else
  say "Team CA already exists — reusing it (clients don't need to re-trust)"
fi

say "Creating the server certificate for app.$DOMAIN / api.$DOMAIN (valid 1 year)"
cat > server.ext <<EOF
basicConstraints       = CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = DNS:app.$DOMAIN, DNS:api.$DOMAIN
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
EOF
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=app.$DOMAIN/O=CN Project $TEAM" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 365 -sha256 -extfile server.ext -out server.crt

cp ca.crt "$ROOT/edge/ca-public/ca.crt"   # only the public CA cert goes in the shareable folder

say "Verifying the chain"
openssl verify -CAfile ca.crt server.crt
openssl x509 -in server.crt -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null \
  || openssl x509 -in server.crt -noout -subject -issuer -dates
echo
echo "Done. Files in $OUT"
