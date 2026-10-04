# Evidence Index — Team .venv, Phase 1

Every requirement of Phase 1 → the file that proves it. Captured on 3 October 2026 on the college Wi-Fi (10.7.0.0/19).
Machines: Mac 1 10.7.6.171 (DNS) · Mac 2 10.7.20.28 (edge) · Mac 3 10.7.20.243 (Backend A) · Mac 4 10.7.8.144 (Backend B + client).

## A — Private LAN (Task A)

| File | Shows |
|---|---|
| `A-LAN-Setup/taskA-netinfo-*.txt` (all 4 Macs) | Each Mac's IPv4, subnet mask (255.255.224.0), gateway (10.7.0.1), interface (en0), MAC address |
| **`A-LAN-Setup/round2-2026-10-04/taskA-ping-from-*.txt`** (all 4 Macs) | **Every Mac → the other three: 3/3 replies, 0 % loss — all 12 directions** |
| `A-LAN-Setup/round1-2026-10-03/taskA-ping-from-*.txt` | First round on build day: Mac 4 reached all; ICMP between Mac 2 and Mac 3 was lost on the busy Wi-Fi (TCP between them worked throughout, see D3/H3) |

Note: Mac 2 got a new DHCP address on 4 Oct (10.7.22.181; it was 10.7.20.28 on 3 Oct, used in all other evidence). Round 2 pings use the new address.
| Topology diagram | `../01-Architecture-Document/` (Figure 1) |

## B — Private DNS server (Task B)

| File | Shows |
|---|---|
| `B-Private-DNS/B1_mac4_dig_app.team1.test.png` | `dig app.team1.test` on Mac 4 → `A 10.7.20.28`, TTL 30, flag `aa`, `SERVER: 10.7.6.171#53` |
| `B-Private-DNS/B2_mac1_dnsmasq_query_log.png` | dnsmasq log on Mac 1: `query[A] app.team1.test from 10.7.8.144` → `config app.team1.test is 10.7.20.28`; other names `forwarded` upstream |
| `B-Private-DNS/B3_mac3_trust-ca_use-team-dns_lb-test.png` | Mac 3 switched to Mac 1 as resolver (second client), resolves app.team1.test, CA fingerprint, load-balanced requests |

## C — Two backend services (Task C)

| File | Shows |
|---|---|
| `C-Backends/C1_mac3_backendA_request_log.png` | Backend A log: every request arrives from 10.7.20.28 (Mac 2, the edge), `GET /api/status 200` |
| `E-HTTPS-TLS/E1_…png` (bottom) | JSON `{"backend": "A", "status": "ok", "tcp_peer": "10.7.20.28:…", "x_forwarded_for": "10.7.8.144"}` and `x-backend` header |

## D — Edge reverse proxy and load balancing (Task D)

| File | Shows |
|---|---|
| `D-Load-Balancing/D1_mac4_lb-test_10_requests.png` | 10 requests by name: all HTTP 200 via edge-mac2, `X-Backend` alternates B, A, B, A … |
| `D-Load-Balancing/D2a_…backendA.png`, `D2b_…backendB.png` | Browser at `app.team1.test`: page A then page B on refresh; TCP peer 10.7.20.28, X-Forwarded-For 10.7.6.171 |
| `D-Load-Balancing/D3_mac2_nginx_access_log_round_robin.png` | nginx access log: `upstream=10.7.20.243:3001` / `10.7.8.144:3002` alternating, `HTTP/2.0`, two clients |
| `D-Load-Balancing/D4_recovery_backendA_rejoins_rotation.png` | After Backend A restart: B, B, then A/B alternation (fail_timeout 10 s) |
| `D-Load-Balancing/text-logs/` | Raw text output of every lb-test run on Mac 3 and Mac 4 |

## E — HTTPS / TLS (Task E)

| File | Shows |
|---|---|
| `E-HTTPS-TLS/E1_mac4_curl-v_TLS1.3_cert_verified_HTTP2.png` | `curl -v` without `-k`: TLS 1.3 handshake, issuer `team1 Local Root CA`, SAN match, `SSL certificate verify ok`, ALPN h2 |
| `B-Private-DNS/B3_…png` (top) | CA downloaded and trusted on Mac 3, SHA-256 fingerprint `AF:86:E7:…:04:31` |
| `G-Packet-Capture/G1_…png` | Full TLS 1.2 handshake as printed by curl |
| `../02-Configuration-Bundle/edge/TLS-SETUP.md` | How the CA and certificate were created and trusted |

## F — HTTP caching (Task F)

| File | Shows |
|---|---|
| `F-HTTP-Caching/F1_mac4_cache-test_CacheControl_ETag_304.png` | `Cache-Control: public, max-age=60`, `ETag "25c29d02c99e446f"`, conditional request → `HTTP/2 304`; `/api/status` is `no-store` |
| `F-HTTP-Caching/F2_mac4_taskF-caching.txt` | Same output as text |

## G — Complete protocol flow capture (Task G)

| File | Shows |
|---|---|
| `G-Packet-Capture/G1_mac4_capture_run_TLS1.2_handshake_curl.png` | The capture run: tcpdump on en0, DNS flush, `curl --tls-max 1.2`, 31 packets saved |
| `G-Packet-Capture/G2_wireshark_dns_query_and_response.png` | Frame 9 query `A app.team1.test` 10.7.8.144:56376 → 10.7.6.171:53; frame 10 response `A 10.7.20.28`; UDP |
| `G-Packet-Capture/G3_wireshark_tcp_SYN_SYNACK.png` | Frame 11 SYN `64222 → 443` Seq=0; frame 12 SYN-ACK Seq=0 Ack=1 (socket pair 10.7.8.144:64222 ↔ 10.7.20.28:443) |
| `G-Packet-Capture/G4_wireshark_tls_handshake_certificate.png` | Client Hello (SNI=app.team1.test), Server Hello + Certificate (expanded) + Server Key Exchange, Client Key Exchange + Change Cipher Spec |
| `G-Packet-Capture/G5_wireshark_encrypted_application_data.png` | Application Data (content type 23): the HTTP request is encrypted bytes |
| `G-Packet-Capture/G0_mac4_capture_taskG-flow-tls12-164445.pcap` | **The raw capture (31 packets)** — open in Wireshark |
| `G-Packet-Capture/G6_full_packet_list_tcpdump.txt` | Every packet as text: DNS query from port 56376 → 53 and answer, SYN / SYN-ACK / **ACK**, TLS records, FIN and RST at the end |
| `G-Packet-Capture/G7_mac4_curl-verbose-tls12.txt` | curl's view of the same request: every TLS 1.2 handshake message and the HTTP headers |

## H — Required failure demonstrations (Section 6.3)

| File | Scenario → observation |
|---|---|
| `H-Failure-Scenarios/H1_wrong_dns_server_on_client.png` | Resolver 10.255.255.254 → dig timed out, **ping 10.7.20.28 works**, curl "Could not resolve host" |
| `H-Failure-Scenarios/H2_dns_record_points_to_wrong_ip.png` | Record → 10.7.6.171 → dig succeeds with the wrong IP, curl "Connection refused" on 443 |
| `H-Failure-Scenarios/H3a_one_backend_stopped_failover.png` | Backend A stopped → all HTTP 200 from B; first request `upstream=…3001, …3002` (retry) |
| `H-Failure-Scenarios/H3b_mac2_nginx_error_log_connection_refused.png` | nginx: `connect() failed (61: Connection refused) … upstream http://10.7.20.243:3001` at 17:32:32 |
| `H-Failure-Scenarios/H4_both_backends_stopped_502.png` | Both stopped → `HTTP/2 502 Bad Gateway` from nginx, both upstreams tried |
| `H-Failure-Scenarios/H5_wrong_destination_port.png` | Port 8443 → Connection refused; `nc -vz app.team1.test 443` → succeeded |

## I — Troubleshooting notes

| File | Shows |
|---|---|
| `I-Troubleshooting-Notes/I1_mac3_managed_mac_python_blocked_then_fixed.png` | Mac 3 (managed Mac): Homebrew Python connections reset (`Errno 57`), firewall locked by MDM, `nc -l 3001` receives "hello-from-mac2", Backend A works with `/usr/bin/python3` |

`_raw-extra/` holds additional unedited screenshots kept for completeness.
