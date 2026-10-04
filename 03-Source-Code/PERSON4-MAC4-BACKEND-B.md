# Person 4 — Mac 4: Backend B (port 3002) + test client

**Your job:** run Backend B, and be the **main test client**. You collect most of the evidence
(dig, curl, Wireshark capture), because your DNS queries travel over Wi-Fi to Mac 1 and are visible in the capture.

```bash
cd ~/Downloads/cn-project        # wherever you unzipped it
chmod +x lib.sh */*.sh
cat team.env                     # IPs filled in?
python3 --version
brew install --cask wireshark    # needs Homebrew (see README)
```

## 1. Task A

```bash
./common/netinfo.sh
./common/ping-all.sh
```

## 2. Task C: start Backend B

```bash
./backend/start-backend.sh       # = python3 backend/server.py B 3002
```
Click **Allow** if macOS asks about incoming connections. Leave this window open. Ctrl+C stops it.
```bash
curl -i http://localhost:3002/api/status     # in a second Terminal
```
(Endpoints are explained in PERSON3's guide. They're identical, but with `"backend": "B"` and `X-Backend: B`.)

## 3. Client setup: use team DNS + trust the CA

```bash
./common/use-team-dns.sh primary     # this Mac now asks Mac 1 for DNS
./common/trust-ca.sh                 # while Person 2 runs share-ca.sh
```

## 4. Collect the Phase 1 evidence (all saved in evidence/)

```bash
dig app.team1.test                       # Task B: ANSWER → Mac 2's IP, "SERVER: <Mac 1 IP>#53"
nslookup api.team1.test
curl -v https://app.team1.test/api/status   # Task E/G: TLS details + headers, no -k
curl -sI --http2 https://app.team1.test/ | head -1     # HTTP/2
curl -sI --http1.1 https://app.team1.test/ | head -1   # HTTP/1.1
./common/lb-test.sh 10                   # Task D: A, B, A, B ...
./common/cache-test.sh                   # Task F: Cache-Control, ETag, 304
./common/capture.sh                      # Task G: .pcap with DNS + TCP + TLS 1.2 handshake
./common/capture.sh tls13                # comparison: TLS 1.3 (certificate encrypted)
open -a Wireshark evidence/taskG-flow-tls12-*.pcap
```

In Wireshark, find these and **take screenshots** into `evidence/`:
| Filter | What to point at |
|---|---|
| `dns` | Query `A app.team1.test` from your IP:ephemeral port → Mac 1:**53/UDP**. Response with Mac 2's IP and TTL 30 |
| `tcp.flags.syn==1` | **SYN** (you → Mac 2:443), **SYN-ACK**, then the **ACK** right after. Note your ephemeral source port (e.g. 54321) |
| `tls.handshake` | **Client Hello** (look for SNI = app.team1.test), **Server Hello**, **Certificate** (expand it: CN/SAN), Server Key Exchange, Change Cipher Spec, Finished |
| `tls.record.content_type==23` | **Application Data**: the HTTP request/response, encrypted (you can't read the JSON) |
| `tcp.stream eq 0` → right-click → Follow → TCP Stream | the whole connection as gibberish → proof of encryption |
| Statistics → Flow Graph | a nice diagram of the whole exchange for the report |

For seq/ack (TCP reliability): click a packet → Transmission Control Protocol → see the
*Sequence Number* and *Acknowledgment Number*, and how ACK = previous seq + length.

Browser evidence: open `https://app.team1.test` in Chrome/Safari → padlock → certificate (issued by
team1 Local Root CA). DevTools (⌥⌘I) → Network → click the request → Headers (X-Backend, Cache-Control).

## 5. Your part in the failure demos
You run most of them from your Mac. Follow the table in [DEMO-AND-FAILURES.md](DEMO-AND-FAILURES.md).
For each one, save the terminal output or a screenshot into `evidence/`.
`./common/diagnose.sh` shows which layer fails (DNS → IP → TCP → TLS → HTTP).
