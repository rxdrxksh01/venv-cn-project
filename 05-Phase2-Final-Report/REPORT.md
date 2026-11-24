# Private Network Service Platform
## Phase 2 report - Harden, Recover and Troubleshoot

Team: .venv. Course: Computer Networks. Demonstration session: 24-25 November
2026, IST. Domain: team1.test. This report records demonstrated results for
Extensions A-E and a read-only troubleshooting rehearsal. The faculty-injected
challenge is pending evaluation; its actual outcome must be added afterward.

### 1. Changes from Phase 1

The Python REST application and native nginx reverse-proxy design were retained.
Rudraksh's unavailable DNS laptop was replaced by dnsmasq in Docker on Anshuman's
Mac. A second Docker DNS service was deployed on Vridhi's Mac. The three available
Macs stayed on the same LAN, using newly recorded addresses rather than the
October submission addresses. Docker was used for DNS, not to replace the entire
application platform.

| Member / host | Current IP | Services |
|---|---|---|
| Anshuman | 10.7.31.231 | Primary DNS UDP/TCP 53; nginx TLS/load balancer 443 |
| Bineet | 10.7.1.112 | Backend A, TCP 3001; client |
| Vridhi / Pranshus-MacBook-Pro | 10.7.2.240 | Backup DNS UDP/TCP 53; Backend B TCP 3002; temporary standby nginx 443 |

Clients resolve app.team1.test or api.team1.test through a team DNS server, then
establish TCP and TLS with the selected edge. nginx terminates TLS, chooses A/B,
and opens a new plain-HTTP backend connection. Responses identify the edge and
backend. The original local CA/server certificate remained valid and trusted.

Added artifacts include a reusable Docker DNS recipe, live DNS record-change
helpers, source-IP firewall templates, a standalone standby nginx configuration,
updated architecture/configuration bundle, and indexed screenshots/transcripts.

### 2. Result overview

| Extension | Result | Scope |
|---|---|---|
| A: Backup DNS | Demonstrated | Uncached lookup answered by backup with primary stopped |
| B: TTL and cache flush | Demonstrated | Cached old answer, later change, manual flush before TTL |
| C: Backend isolation | Demonstrated | Both ports tested separately; edge allowed, client denied; rollback |
| D: Backend failover | Demonstrated | B serves while A stopped; A/B resumes after A restarts |
| E: Edge migration | Demonstrated | Trusted standby, DNS cutover, client transition, rollback |
| F: Faculty fault | Pending | Read-only wrong-port rehearsal completed; faculty result not claimed |

Evidence is indexed in 04-Evidence/Phase2/EVIDENCE-INDEX.md. The original Phase 1
packet capture remains available with its historical addresses.

<!-- pagebreak -->

## 3. Extension A - Backup DNS

Matching project records were served by containers on two physical Macs. Clients
listed 10.7.31.231 and 10.7.2.240 as resolvers. The primary container was stopped;
Bineet flushed the host cache and queried api.team1.test through the macOS system
resolver. His result was 10.7.31.231. The backup log recorded the API query and
IPv4 answer, distinguishing it from automatic app-name healthcheck traffic.
Primary DNS was subsequently restored.

The backup logs used a Docker-side source address. This was not interpreted as
the original client IP. IPv6 NODATA was expected because the private records
contained IPv4 addresses. Resolver-list order was not treated as a guaranteed
strict failover sequence; macOS resolver selection is adaptive.

Learning: name resolution is independent of service availability. Backup DNS can
answer a new lookup when another resolver fails, but a correct address does not
make an unavailable application work. Because primary DNS and the normal edge
share a Mac, loss of that whole Mac also affects the edge; this test isolated a
DNS-service failure rather than a full-machine failure.

## 4. Extension B - DNS TTL and controlled change

A separate ttl-demo.team1.test record isolated the cache experiment from the
working website. Bineet temporarily used only the primary resolver so mismatched
answers from two resolvers could not confuse the test. The advertised TTL was
30 seconds. A reloadable hosts file allowed record changes without restarting DNS.

| Time, IST, 24 November | Observation |
|---|---|
| 23:33:39 | Client first receives old address 10.7.31.231 |
| 23:33:55 | Direct primary DNS query already returns new address 10.7.2.240 |
| 23:34:14 | Client still reports the old address |
| 23:34:19 | First sampled client result with the new address |

These observations demonstrate a cached old answer despite a changed server
answer, followed by a new answer. They do not establish an exact 30-second client
cache lifetime: sampling and OS resolver behavior affect the observed timing.

For manual flushing, the client primed 10.7.2.240 at 23:36:31; the server restored
10.7.31.231 at 23:36:34; after a manual flush the client obtained 10.7.31.231 at
23:36:45. The new answer arrived only 14 seconds after priming. The original
record and the client's two-resolver configuration were restored afterward.

Learning: direct dig queries show a server's current answer, while system lookups
may reuse cached data. DNS TTL concerns name-to-address mappings, distinct from
HTTP Cache-Control and ETag validation of content. Cache expiry makes a migration
gradual, while manual flushing can force a fresh lookup during diagnosis.

<!-- pagebreak -->

## 5. Extension C - Service isolation

Each backend initially accepted direct HTTP from a non-edge client. A scoped PF
anchor then allowed incoming IPv4 TCP from the original edge, 10.7.31.231, to the
relevant backend port and rejected other remote sources. Existing main PF files
were preserved. Syntax was checked before loading; PF was enabled with an enable
reference, and the reference was released during rollback.

| Backend | Allowed path | Denied path | Recovery |
|---|---|---|---|
| B: 10.7.2.240:3002 | Anshuman direct HTTP | Bineet direct HTTP | Bineet direct HTTP restored |
| A: 10.7.1.112:3001 | Anshuman direct HTTP | Vridhi direct HTTP | Vridhi direct HTTP restored |

For B, Bineet's direct request failed while his trusted HTTPS request through
nginx succeeded and was served by B. B's counters recorded 52 allowed packets
and 2 blocked packets in the supplied sample. For A, the edge remained allowed
while Vridhi's direct request failed; A's counters recorded 33 allowed packets
and 2 blocked packets. Vridhi initially had a separate DNS setup issue; after
configuring team resolvers she obtained trusted HTTPS HTTP/2 200 through nginx
(that supplied request was served by B).

Both isolation tests were followed by rollback and successful direct client
access. Bineet's screenshot also showed PF disabled after releasing the enable
reference. The tests demonstrate the policy and rollback; the filters were not
left active for the later standby migration.

Learning: binding a backend on a LAN interface permits access but does not restrict
who may connect. Source-IP filtering enforces the intended edge-only path. It is
important to distinguish an intentionally blocked backend connection from broken
DNS or TLS, and to preserve existing firewall configuration and scoped rollback.

## 6. Extension D - Backend failover and recovery

The original nginx upstream policy already used passive detection with
max_fails=1, fail_timeout=10s, and retry on upstream connection errors/timeouts.
When A stopped, six demonstrated requests returned HTTP/2 200 from B. The first
upstream header listed A followed by B, showing a failed attempt and retry. After
A restarted and traffic resumed, six demonstrated requests alternated A/B with
HTTP 200.

Learning: passive detection reacts to real failed requests; it is not a background
probe of /health. Retrying a healthy backend can hide a selected backend failure,
and a restarted backend can rejoin rotation after its exclusion window. This
protects against a backend outage, but does not remove the normal edge's single
point of failure.

<!-- pagebreak -->

## 7. Extension E - Controlled edge migration

Native standby nginx was installed on Vridhi's Mac using a standalone configuration
and the existing trusted server identity. An encrypted PKCS#12 transfer provisioned
the certificate/key locally. A preparation request with --resolve verified TLS,
HTTP/2 200 and X-Edge: edge-standby before changing DNS. No TLS verification bypass
was used.

Vridhi's unrelated Supportdesk nginx container occupied ports 80/443. The team
paused only that container during the standby demonstration. Both backend PF
restrictions had been rolled back so the standby could reach the upstreams.

For the actual migration, both DNS servers changed app/api records to 10.7.2.240
with TTL 30, while both edges stayed running. Bineet issued ordinary HTTPS requests
without --resolve and recorded the connected IP, edge identity and status.

| Sample, IST, 25 November | Edge / IP | Result |
|---|---|---|
| 00:28:59, last visible old-edge sample | edge-mac2 / 10.7.31.231 | HTTP/2 200 |
| 00:29:05, first visible standby sample | edge-standby / 10.7.2.240 | HTTP/2 200 |
| 00:29:10, 00:29:15, 00:29:20 | Standby, with A/B responses | HTTP/2 200 |

All visible loop requests returned HTTP 200. A failed helper invocation from the
home directory is visible in the server screenshot; it did not change DNS and
must not be used as a successful-cutover timestamp. Subsequent direct DNS answers
and ordinary client requests establish the final DNS state and edge transition.

Both DNS servers were restored to 10.7.31.231. After a client flush, the supplied
rollback screenshot showed HTTP/2 200 from edge-mac2 at 10.7.31.231. The user then
confirmed standby nginx was stopped and Supportdesk nginx restarted. Those remote
service cleanup actions are user-confirmed rather than independently inspected.

Learning: DNS-based migration changes the edge address while preserving the name,
port and TLS identity. Cached clients may continue to use an old address, and
established connections need not move when DNS TTL expires. This was a manual
cutover, not automatic edge health detection; the old edge must remain available
during the transition.

## 8. Troubleshooting findings

Docker initially required privileged port forwarding permission on the backup
host. Later, container recreation intermittently left host UDP forwarding stale
even while internal healthchecks and TCP DNS worked. Testing internal DNS, host
UDP and host TCP separately isolated the path; Docker restart restored UDP in the
observed case. Live hosts-file reloads then avoided restarts during timed tests.
Vridhi's DNS-container role did not configure her host resolver automatically.
Adding both resolver IPs and flushing her cache fixed her separate name-resolution
failure. The standby port conflict was resolved without stopping backup DNS.

<!-- pagebreak -->

## 9. Extension F - Troubleshooting readiness

The faculty-injected challenge has not yet occurred. A read-only wrong-port
rehearsal was recorded locally after restoration: both team resolvers returned
the correct edge IP; HTTPS to unused port 8443 failed with curl exit code 7;
trusted HTTPS on 443 returned an application response with curl exit code 0.
No running configuration was changed for that rehearsal.

Learning: diagnose from DNS to TCP, then TLS and HTTP. Correct DNS plus a failed
connection to one destination port does not imply an application outage. Compare
the failing path to a known-good port and use evidence to name the affected layer.
During evaluation, record the actual injected fault, tests, diagnosis, fix and
outcome; do not substitute this rehearsal for faculty evidence.

| Layer | Primary checks | Typical finding |
|---|---|---|
| DNS | Both direct dig queries; system lookup; resolver settings | Timeout, stale answer or wrong record |
| TCP | nc to resolved IP/port | Refused connection or timeout |
| TLS | curl -v with verification enabled | Wrong CA, SAN, date or handshake |
| HTTP/upstream | Status, X-Edge, X-Backend, nginx logs | 502/504, wrong upstream or stopped backend |

## 10. Final state and evaluation preparation

At the restoration check, both DNS servers answered 10.7.31.231 and trusted HTTPS
returned HTTP/2 200 from edge-mac2. The primary DNS container was healthy. Backend
isolation rules were rolled back, standby nginx was stopped, and Supportdesk was
restored as confirmed by the user. The standby configuration remains available
for the evaluation demo, but is not claimed to be continuously active.

Before evaluation, confirm current DHCP addresses, collect the three available
Macs' LAN inventory/pings, start services, and verify both DNS servers, trusted
HTTPS, A/B responses and HTTP caching. Build Docker images ahead of time. Update
all address-dependent configs if the network changes. Keep existing Phase 1
packet evidence clearly labeled as historical, and take a fresh capture if needed.

Follow the brief's demonstration sequence: topology, LAN, DNS, HTTPS, A/B load
balancing, Wireshark, HTTP cache/304, backend failure, DNS resilience/migration,
faculty troubleshooting, and individual viva. For isolation/migration, apply and
restore the scoped policy deliberately; a standby needs an allowed source path.

Submission artifacts: updated architecture under 01-Architecture-Document;
sanitized configurations under 02-Configuration-Bundle/Phase2; executable source
and runbooks under 03-Source-Code; indexed evidence under 04-Evidence/Phase2; this
editable report under 05-Phase2-Final-Report; printable PDF under output/pdf.

### Evaluation-time addition

Faculty fault, affected layer, checks used, fix/isolation, observed outcome and
team learning: pending. Add the actual result after the challenge. Do not mark
the entire Phase 2 evaluation complete before this requirement and viva occur.
