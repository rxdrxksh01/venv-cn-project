#!/bin/bash
# Task E: trust the team CA on THIS Mac, so browsers and curl accept https://app.<domain>
# without warnings and without curl -k. Run on every client Mac (Mac 1, Mac 4; Mac 2/3 too is fine).
# Mac 2 must be running ./edge/share-ca.sh at the same time (not needed on Mac 2 itself).
source "$(dirname "$0")/../lib.sh"

CA="$ROOT/edge/ca-public/ca.crt"
if [ ! -f "$CA" ]; then
  say "Downloading the CA certificate from Mac 2"
  mkdir -p "$(dirname "$CA")"
  curl -fsS "http://$MAC2_IP:8000/ca.crt" -o "$CA" || { echo "Download failed — is share-ca.sh running on Mac 2?"; exit 1; }
fi

say "CA certificate:"
openssl x509 -in "$CA" -noout -subject -fingerprint -sha256
echo "(Compare this fingerprint with the one on Mac 2 — that's how you know it's the right CA.)"

say "Adding it to the System keychain as a trusted root (Safari/Chrome use this)"
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CA"

# macOS's curl checks a CA bundle file, not the keychain. Build a bundle = normal public CAs + ours,
# and point curl at it via ~/.curlrc. Certificates are still fully verified — no -k anywhere.
say "Making curl trust it too (~/.curlrc)"
BUNDLE="$HOME/.cn-project-ca-bundle.pem"
cat /etc/ssl/cert.pem "$CA" > "$BUNDLE"
touch "$HOME/.curlrc"
grep -q "cn-project-ca-bundle" "$HOME/.curlrc" || echo "cacert = \"$BUNDLE\"" >> "$HOME/.curlrc"

echo
echo "Done. Quit and reopen your browser, then open https://app.$DOMAIN"
