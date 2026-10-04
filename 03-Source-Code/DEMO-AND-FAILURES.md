# Failure demos · Phase 1 review demo · Viva prep

## Required failure demonstrations (Section 6.3)

Run each from **Mac 4** (client) unless noted. Save the output or a screenshot to `evidence/`, then **restore**.

| # | Break it | Observe | Restore | What it proves |
|---|---|---|---|---|
| 1 | Mac 4: `./common/use-team-dns.sh wrong` | `dig app.team1.test` → timed out; `ping <MAC2_IP>` → **works**; `./common/diagnose.sh` fails at step [2] | `./common/use-team-dns.sh primary` | DNS and IP connectivity are independent layers |
| 2 | Mac 1: `./dns/point-record.sh app <MAC3_IP>`. Mac 4: flush cache (`sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`) | `dig` **succeeds** but returns Mac 3. `curl https://app.team1.test` → *Connection refused* (nothing on Mac 3:443) | Mac 1: `./dns/point-record.sh app <MAC2_IP>`, Mac 4 flush | DNS is only a directory. It doesn't check that the destination works |
| 3 | Mac 3: **Ctrl+C** Backend A | `./common/lb-test.sh 8` → all 200, all `X-Backend: B` | restart Backend A | the edge hides a backend failure |
| 4 | Mac 3 **and** Mac 4: Ctrl+C both backends | `curl -i https://app.team1.test/` → **502 Bad Gateway** from nginx. `curl -v` shows the TLS handshake still **succeeds** | restart both | where the edge ends and the backend begins |
| 5 | Mac 4: `curl -v https://app.team1.test:8443/` | *Connection refused* (host up, nothing on that port). `nc -vz app.team1.test 443` → succeeded | — | IP address and port are separate identifiers |

---

## Phase 1 review demo: who does what

The review is a working live system plus a short structured demo, and everyone must be able to explain any part.

| # | Step | Who / Command |
|---|---|---|
| 1 | Topology + IP/service table | Show the diagram in README / architecture doc + `team.env` + `evidence/taskA-netinfo-*.txt` |
| 2 | All Macs on the LAN | Each person: `ipconfig getifaddr en0`, then `./common/ping-all.sh` |
| 3 | Resolve the private name | Mac 4: `dig app.team1.test` → Mac 2's IP, `SERVER: <MAC1_IP>#53`. Mac 1: `tail -f` the dnsmasq log shows the query arriving |
| 4 | HTTPS by name, no warning | Mac 4: browser `https://app.team1.test` (padlock) + `curl -i https://app.team1.test/api/status` (no -k) |
| 5 | Load balancing | Mac 4: `./common/lb-test.sh 10` → A, B, A, B |
| 6 | Wireshark evidence | Mac 4: open the saved `evidence/taskG-flow-tls12-*.pcap`, filters `dns`, `tcp.flags.syn==1`, `tls.handshake` |
| 7 | Headers + caching | Mac 4: `./common/cache-test.sh` → Cache-Control, ETag, **304** |
| 8 | Failure demos | The 5 rows of the table above |
| 9 | Questions | everyone (see viva prep below) |

If something breaks live, run `./common/diagnose.sh` and explain layer by layer:
DNS (dig) → IP (ping) → TCP (`nc -vz <ip> 443`) → TLS (`openssl s_client`) → HTTP (`curl -v`).

**Morning-of checklist:** same Wi-Fi → IPs unchanged? (`ipconfig getifaddr en0` vs team.env) →
Mac 1 `sudo brew services list` shows dnsmasq started → Mac 3/4 backends running → Mac 2 `sudo nginx -t` and nginx running →
Mac 4 `./common/diagnose.sh` all PASS.

---

## Viva prep: every person must be able to explain ALL of this

**Request journey:** browser → DNS lookup (UDP 53 to Mac 1) → gets Mac 2's IP → TCP 3-way handshake to
Mac 2:443 → TLS handshake (certificate check) → encrypted HTTP GET → nginx decrypts, picks a backend, opens a
new TCP connection to Mac 3:3001 or Mac 4:3002 → backend answers → nginx encrypts the response and sends it back.

**Layers:** DNS, HTTP = Application · TLS = between Application and Transport (Session/Presentation in OSI) ·
TCP/UDP = Transport (ports) · IP = Network (addresses) · Ethernet/Wi-Fi = Link (MAC addresses).

**Socket pair:** (client IP, ephemeral port e.g. 54321) ↔ (Mac 2 IP, 443). The ephemeral port is chosen by the OS, the server port is well known.

**Why DNS uses UDP:** a small single question/answer, no handshake needed, so it's fast. TCP 53 is used for big answers or zone transfers.

**TCP handshake:** SYN (seq=x) → SYN-ACK (seq=y, ack=x+1) → ACK (ack=y+1). Sequence and ack numbers give
ordering and reliability, and lost segments are retransmitted. The receive window gives flow control.

**TLS:** ClientHello (SNI, ciphers, random) → ServerHello → Certificate → key exchange (ECDHE) → Finished.
The client trusts the cert because our CA is in its trust store, and the name matches the SAN. After the
handshake everything is encrypted with symmetric keys. TLS 1.3 needs 1 RTT and encrypts the certificate.

**Self-signed vs CA:** our CA is self-signed and trusted manually. The server cert is *signed by* the CA. Real sites use public CAs that come pre-installed in browsers.

**Load balancing:** round robin = take turns. least_conn = send to the server with the fewest active connections. The client
doesn't need backend IPs because it only talks to the edge (reverse proxy).
Reverse proxy = sits in front of servers. Forward proxy = sits in front of clients.

**HTTP versions:** 1.1 = one request at a time per connection (keep-alive). 2 = binary framing, many streams
multiplexed on one TCP connection, header compression. 3 = runs over QUIC (UDP), so there's no TCP head-of-line blocking (explanation only).

**Caching:** fresh hit = within max-age, no request sent at all. Conditional = cache expired, so the client sends
`If-None-Match: <etag>`, and the server replies **304** with no body if unchanged. Full request = no cache, so 200 + the whole body.
Why /api/status is `no-store`: otherwise the browser would reuse the answer and you couldn't see load balancing.

**DNS:** TTL = how long a client may cache an answer. dig asks the server directly. Browsers and curl use the
OS cache. Flush: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`. Why `.test` not `.local`: `.local` is reserved for mDNS/Bonjour on macOS.

**Failure meanings:** NXDOMAIN / timeout = DNS layer · connection refused = host is up, nothing listening on the port (TCP) ·
timeout = host down or firewall dropping · cert error = TLS layer · 502 = edge OK, backend unreachable · 504 = backend too slow · 404 = app layer.

**Email (explanation only):** SMTP (port 25/587) sends mail between servers. IMAP (993) / POP3 (995) let clients read it.
MX records in DNS say which server receives mail for a domain.

**CDN:** edge servers near users cache content (Cache-Control decides what they may cache). Our nginx edge plays the role of a CDN edge / ALB.
