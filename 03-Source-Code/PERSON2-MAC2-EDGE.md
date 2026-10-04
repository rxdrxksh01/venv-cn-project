# Person 2 — Mac 2: Edge (nginx reverse proxy + load balancer + HTTPS)

**Your job:** Mac 2 is the **only** entry point. Clients connect to you on port 443. You terminate
TLS (decrypt) and forward each request over plain HTTP to Backend A (Mac 3:3001) or Backend B
(Mac 4:3002), alternating between them (round robin).

You need: the shared Wi-Fi, Homebrew, admin password.

```bash
cd ~/Downloads/cn-project        # wherever you unzipped it
chmod +x lib.sh */*.sh
cat team.env                     # IPs filled in?
```

## 1. Task A

```bash
./common/netinfo.sh
./common/ping-all.sh
```

## 2. Task E (part 1): create the certificates

```bash
./edge/make-certs.sh
```
This creates `edge/certs/`:
| File | What it is | Who gets it |
|---|---|---|
| `ca.key` | private key of our own Certificate Authority | **nobody, stays on Mac 2** |
| `ca.crt` | the CA's public certificate | every client trusts it |
| `server.key` | nginx's private key | only you, never shared |
| `server.crt` | certificate for `app.team1.test` + `api.team1.test`, signed by our CA | sent to clients in every TLS handshake |

Why a CA instead of a plain self-signed cert: clients trust the CA once, and then every
certificate it signs is valid. This is the same trust model as real HTTPS (Let's Encrypt, DigiCert),
just with our own root.

Inspect it (viva):
```bash
openssl x509 -in edge/certs/server.crt -noout -text | less    # Subject, Issuer, SAN, validity, key
openssl verify -CAfile edge/certs/ca.crt edge/certs/server.crt
```

## 3. Task D + E: start nginx

The backends don't have to be running yet.
```bash
./edge/setup-nginx.sh
```
It installs nginx and writes `/opt/homebrew/etc/nginx/servers/team1.conf`. **Read that file.** Key parts:
- `upstream team1_backends { server <Mac3>:3001; server <Mac4>:3002; }`: the pool, round robin by default
- `listen 443 ssl; http2 on;` + `ssl_certificate ...`: TLS termination, HTTP/2 enabled
- `listen 80` → `301` redirect to HTTPS
- `proxy_pass http://team1_backends;` + `X-Forwarded-For`: forward the request, remember the real client IP
- `max_fails=1 fail_timeout=10s` + `proxy_next_upstream error timeout`: if a backend is down, skip it and retry the other one (failure demo 3)
- `add_header X-Edge` / `X-Upstream-Addr`: evidence headers showing which edge and which backend

Useful nginx commands:
```bash
sudo nginx -t                    # test config
sudo nginx -s reload             # apply changes without dropping connections
sudo nginx -s stop / sudo nginx  # stop / start
tail -f /opt/homebrew/var/log/nginx/team1_access.log   # every request + which upstream served it
tail -f /opt/homebrew/var/log/nginx/error.log          # "connect() failed" when a backend is down
sudo lsof -nP -iTCP:443 -sTCP:LISTEN                   # prove nginx listens on 443
```

Once Mac 3 and Mac 4 have their backends running, test from Mac 2 itself:
```bash
curl -i http://<MAC3_IP>:3001/api/status     # backend A directly
curl -i http://<MAC4_IP>:3002/api/status     # backend B directly
curl -i --cacert edge/certs/ca.crt --resolve app.team1.test:443:127.0.0.1 https://app.team1.test/api/status
```

## 4. Task E (part 2): give the CA to the clients

```bash
./edge/share-ca.sh
openssl x509 -in edge/certs/ca.crt -noout -fingerprint -sha256   # read this out to the others
```
Leave it running while Persons 1, 3, 4 run `./common/trust-ca.sh`, then press Ctrl+C.
It serves **only** `ca.crt`, never the keys.

## 5. Point Mac 2's DNS at Mac 1, and test by name

```bash
./common/use-team-dns.sh primary
./common/trust-ca.sh             # finds ca.crt locally, no download needed
./common/lb-test.sh
```

## 6. TLS knowledge you must explain
- Handshake (TLS 1.2): **ClientHello** (versions, ciphers, random, SNI = app.team1.test) → **ServerHello** (chosen cipher)
  → **Certificate** (server.crt) → **ServerKeyExchange / ClientKeyExchange** (ECDHE key agreement) →
  **ChangeCipherSpec + Finished** → encrypted Application Data.
- TLS 1.3 does it in one round trip, and the Certificate is already encrypted. That's why the capture uses TLS 1.2 to show it.
- The client checks: is the cert signed by a trusted CA? Does the name match the SAN (`app.team1.test`)? Is it within its validity dates?
- **TLS termination:** encryption ends at nginx. Mac 2 → backends is plain HTTP on the LAN (trusted internal network).

## 7. Your part in the failure demos
- **Failure 3/4 (backends stopped):** keep `tail -f /opt/homebrew/var/log/nginx/error.log` open. It shows
  `connect() failed (61: Connection refused)`, then nginx retries the other backend, or returns 502 if both are down.
- Be ready to explain why the client never needs the backend IPs (it only talks to you, the reverse proxy).
