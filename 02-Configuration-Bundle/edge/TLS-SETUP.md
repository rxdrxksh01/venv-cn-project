# TLS Certificate Setup Notes (Task E)

We created our **own local Certificate Authority (CA)** with OpenSSL and used it to sign the
server certificate that nginx presents. Clients trust the CA once, so every certificate it
signs is accepted without warnings — the same trust model as public HTTPS, with our own root.
No step bypasses certificate validation (no `curl -k`, no browser "proceed anyway").

## 1. Certificates (created on Mac 2 with `edge/make-certs.sh`)

| Item | Value |
|---|---|
| Root CA subject | `CN=team1 Local Root CA, O=CN Project team1` (self-signed) |
| Root CA validity | 3 Oct 2026 → 30 Sep 2036 |
| Root CA extensions | `basicConstraints: critical, CA:TRUE` · `keyUsage: critical, keyCertSign, cRLSign` |
| Root CA SHA-256 fingerprint | `AF:86:E7:EF:AA:D4:36:B3:35:34:C7:7B:54:6E:43:B6:C8:7E:BA:01:FA:B3:A4:6B:D3:08:70:8E:6F:B3:04:31` |
| Server certificate subject | `CN=app.team1.test, O=CN Project team1` |
| Server certificate SAN | `DNS:app.team1.test, DNS:api.team1.test` |
| Server certificate validity | 3 Oct 2026 → 3 Oct 2027 (365 days, within Apple's limit for trusted TLS certificates) |
| Server certificate extensions | `CA:FALSE` · `keyUsage: digitalSignature, keyEncipherment` · `extendedKeyUsage: serverAuth` |
| Keys | RSA 2048-bit, SHA-256 signatures |

Commands (simplified from the script):

```bash
# Root CA
openssl genrsa -out ca.key 2048
openssl req -x509 -new -key ca.key -sha256 -days 3650 -config ca.cnf -out ca.crt

# Server certificate signed by the CA
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=app.team1.test/O=CN Project team1" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
        -days 365 -sha256 -extfile server.ext -out server.crt     # server.ext holds the SAN

openssl verify -CAfile ca.crt server.crt          # → server.crt: OK
```

Who holds what:

| File | Location | Shared? |
|---|---|---|
| `ca.key` | Mac 2 only | Never — whoever has it can issue trusted certificates |
| `ca.crt` | every client | Yes (public) — included in this bundle as `team1-root-ca.crt` |
| `server.key` | Mac 2 nginx (`/opt/homebrew/etc/nginx/team-certs/`, mode 600) | Never |
| `server.crt` | Mac 2 nginx | Sent to clients in every TLS handshake |

## 2. Distribution and trust (on every client, `common/trust-ca.sh`)

1. Mac 2 temporarily served **only** `ca.crt` over the LAN (`python3 -m http.server 8000` in a folder
   containing nothing else); clients downloaded it and compared the SHA-256 fingerprint.
2. Trusted for browsers (Safari/Chrome use the macOS keychain):
   ```bash
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt
   ```
3. Trusted for curl (macOS curl/LibreSSL reads a CA bundle file, not the keychain):
   ```bash
   cat /etc/ssl/cert.pem ca.crt > ~/.cn-project-ca-bundle.pem
   echo 'cacert = "~/.cn-project-ca-bundle.pem"' >> ~/.curlrc
   ```
   Full verification still happens — evidence: `SSL certificate verify ok` in `curl -v`.

## 3. nginx TLS termination (Mac 2)

```nginx
listen 443 ssl;
http2 on;
ssl_certificate     /opt/homebrew/etc/nginx/team-certs/server.crt;
ssl_certificate_key /opt/homebrew/etc/nginx/team-certs/server.key;
ssl_protocols       TLSv1.2 TLSv1.3;
```

TLS ends at nginx; nginx forwards to the backends over plain HTTP on the LAN.

## 4. Observed handshakes

| Client | Negotiated | Notes |
|---|---|---|
| `curl -v` (default) | TLS 1.3, `AEAD-CHACHA20-POLY1305-SHA256`, ALPN `h2` (HTTP/2) | 1-RTT handshake; certificate is encrypted on the wire |
| `curl --tls-max 1.2` (used for the Wireshark capture) | TLS 1.2, `ECDHE-RSA-CHACHA20-POLY1305`, HTTP/1.1 | Certificate visible in plain text, so every handshake message can be shown |

TLS 1.2 handshake sequence as captured: ClientHello (SNI = `app.team1.test`) → ServerHello +
Certificate + ServerKeyExchange + ServerHelloDone → ClientKeyExchange + ChangeCipherSpec +
Finished → ChangeCipherSpec + Finished → encrypted Application Data.
