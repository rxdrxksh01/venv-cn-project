# Phase 1 understanding and Phase 2 evaluation guide

Prepared 24 November 2026. This is a plan and runbook, not a report claiming
Phase 2 has been demonstrated. Keep actual results and screenshots separately.
Faculty confirmed through the team that Docker replaces the missing DNS host only.

## What this project actually does

It is a private service platform, not a feature-heavy website. The same simple
Python app is run twice so the network can demonstrate routing and resilience.

```text
Client --DNS query UDP/TCP 53--> dnsmasq --answer: edge IP--> client
Client --TCP handshake, then TLS, then HTTPS :443--> nginx edge
nginx --a separate TCP connection, plain HTTP--> Backend A :3001 or B :3002
nginx <--backend response-- backend
Client <--encrypted HTTPS response-- nginx
```

DNS returns an address; it does not forward the HTTPS request. nginx terminates
TLS and creates a different connection to the chosen backend. The backend's TCP
peer is the edge; `X-Forwarded-For` carries the original client address as an HTTP
header. Backend ports need not be known by clients.

## Repo map and what to understand

| Location | What it contains / why it matters |
|---|---|
| `01-Architecture-Document/` | 13-page Phase 1 report, topology and request-flow diagrams |
| `02-Configuration-Bundle/` | Historical deployed DNS/nginx configs, public CA certificate, launch notes |
| `03-Source-Code/team.env` | Runtime inputs to the existing native Mac scripts; old IPs need updating |
| `03-Source-Code/lib.sh` | Loads team.env, discovers interface/IP and creates an evidence folder |
| `backend/server.py` | Shared Python standard-library HTTP server; arguments select backend A/B and port |
| `backend/start-backend.sh` | Starts Python, prefers Apple's interpreter for the managed Mac |
| `dns/setup-dns.sh`, `dns/point-record.sh` | Original native Mac DNS setup/change scripts; **not** Docker management commands |
| `edge/make-certs.sh` | Creates a CA and server certificate with app/api DNS SANs |
| `edge/setup-nginx.sh` | Generates native nginx TLS, reverse proxy and upstream load-balancing config |
| `edge/share-ca.sh`, `common/trust-ca.sh` | Distribute public CA and configure client trust |
| `common/` | LAN inventory, pings, requests, HTTP cache, capture and diagnostics |
| `PERSON*.md` | Original role-specific Phase 1 instructions |
| `DEMO-AND-FAILURES.md` | Phase 1 failure demonstrations and viva notes |
| `04-Evidence/` | Existing screenshots, logs, raw pcap, and requirement-to-evidence index |
| `docker-dns/` | New replacement DNS container, used on two different Macs for primary and backup |

The configuration bundle is a snapshot, not what scripts read at runtime. Runtime
scripts source **03-Source-Code/team.env**, not the duplicate in the bundle.

### Python endpoints

* `/`: page showing A or B, hostname, TCP peer and forwarded client; `no-store`.
* `/api/status`: JSON identity/status/port/client info; `no-store` so repeat requests reach nginx.
* `/api/cached`: stable identical JSON on A/B, `public, max-age=60`, same ETag;
  matching `If-None-Match` returns 304 with no body.
* `/health`: simple `ok`; it exists, but nginx's current config does not actively poll it.

nginx has round robin by default. `max_fails=1 fail_timeout=10s` plus
`proxy_next_upstream` implement **passive** failure detection and request retry.
They do not run a background health probe. After the exclusion interval nginx can
try the recovered backend on subsequent traffic. Exact A/B alternation is not a
universal guarantee with multiple workers, clients or failures; show both identities.
For shared upstream failure state across workers, consider `zone team1_pool 64k;`
inside the upstream block, then `nginx -t` before reloading.

HTTP caching here is client caching/conditional validation. The nginx config has
no `proxy_cache`; do not describe this as a working nginx response cache.

## What Phase 1 already establishes

The evidence folder documents LAN reachability, private DNS, both backends,
nginx reverse proxy/load balancing, CA-verified TLS, HTTP caching/304, a complete
packet capture, and the five required failures. The raw `.pcap` is present.
These are historical results from October, not proof today's services are up.

Old addresses: DNS 10.7.6.171, edge 10.7.20.28, A 10.7.20.243, B 10.7.8.144.
The evidence itself notes a later edge DHCP change to 10.7.22.181. Re-inventory
every available laptop on the network you will use tomorrow; do not reuse old IPs.

The local installed nginx server certificate is still within its stated validity
and has app/api.team1.test SANs. The repo contains public CA certs but no private
keys. A fresh checkout alone cannot recreate the old CA identity. Preserve the
existing working local key/certificate pair. If a new CA is generated, distribute
and trust that new CA; a same-name CA is not the same cryptographic identity.
`trust-ca.sh` reuses a checked-in CA file if present, so compare fingerprints with
the actual active edge certificate chain before trusting it. Never commit keys.

## Mandatory Phase 2 scope (brief Section 7)

All A-F are required in the supplied brief. Extension E is **not marked optional**,
and is included in Review 2 marks. The shorter final-demo table does not waive tasks.

| Extension | Current repo state | Required evidence |
|---|---|---|
| A: backup DNS | New Docker recipe supplied; two-Mac deployment still needed | Two matching resolvers, client configured for both, primary stopped, uncached resolution handled by backup |
| B: DNS TTL | TTL 30 already configured; no Phase 2 cache-expiry evidence | Old cached answer, changed server answer, expiry/new answer, separate manual-flush test |
| C: isolation | No backend port firewall rules | Edge allowed to :3001/:3002, remote non-edge client blocked, rollback demonstrated |
| D: backend failover | Existing passive failover + recovery evidence | Repeat stop-A / B-only success / restart-A / both return, with current addresses |
| E: edge migration | No standby edge config/evidence | Standby on another Mac, valid TLS, DNS cutover, cached versus fresh clients, rollback |
| F: troubleshooting | Phase 1 diagnostic helper available | Diagnose faculty's fault in DNS -> TCP -> TLS -> HTTP order, explain reasoning |

Review 2: A/B/D 15 marks; C/E 10; F 10; report 5; individual viva 10.

## Proposed three-Mac topology

* Anshuman: nginx primary edge + Docker primary DNS. Ports 443 and 53 coexist.
* Bineet: Backend A :3001, using the known-working Apple Python if still MDM-managed.
* Vridhi: Backend B :3002 + Docker backup DNS + client; standby nginx for migration.

Physical machines can combine roles. Primary and backup DNS are on different
physical hosts. DNS resilience here covers a DNS-service failure: if Anshuman's
whole Mac fails, the primary edge also fails. Backup DNS alone cannot repair that.
The edge remains a single point of failure until a standby is activated.

## Tonight: restore the baseline first

1. Join the same LAN/hotspot and inventory available Macs with `common/netinfo.sh`.
   Record current IP, subnet, gateway, interface and MAC; verify pairwise ping.
2. Update **03-Source-Code/team.env on all Macs**: MAC1_IP becomes the primary
   Docker DNS host's LAN IP (same as MAC2_IP for this plan); MAC2/3/4 get today's IPs.
   Docker also has its own `.env`; keep its EDGE_IP consistent with team.env.
3. Start native backends: from 03-Source-Code use
   `bash backend/start-backend.sh A` on Bineet's Mac and
   `bash backend/start-backend.sh B` on Vridhi's Mac.
4. On the edge, preserve working local certificates. The setup script expects
   `edge/certs/server.crt` and `server.key`, which a clean clone does not contain.
   If using existing `/opt/homebrew/etc/nginx/team-certs/` files, back up the active
   nginx config and update its upstream IPs directly; otherwise put a matching
   existing certificate/key in the expected local directory before running setup.
   Check `sudo nginx -t`, then reload. Do not regenerate a CA just because DNS moved.
5. From the edge, direct HTTP to both backend IPs must work. Then establish HTTPS
   by name with certificate verification. `curl --cacert /path/to/actual-ca.crt`
   validates TLS for terminal testing; browser trust still needs the Keychain CA.
6. Deploy primary and backup DNS using [docker-dns/README.md](docker-dns/README.md).
   Configure both resolver IPs manually as that guide shows. The old
   `use-team-dns.sh primary` sets **one** server only and would remove the backup.
7. Repeat load-balancing and cache tests, collect fresh evidence, then add Phase 2.

## Extension C: backend isolation without breaking the machine

Use a faculty-provided macOS pf template if available. The stock application
firewall's app allow-list is not equivalent to a source-IP allow-list.
On each backend host, the intended **inbound TCP filter logic** is:

```text
allow edge-LAN-IP -> this-backend-LAN-IP : its backend port
block other remote sources -> this-backend-LAN-IP : its backend port
leave other services/ports alone
```

Apply only to Backend A :3001 on its host and Backend B :3002 on its host, on the
actual LAN interface. Keep loopback behavior separate: a backend testing itself
via localhost is not proof a remote client can bypass the firewall.

Before applying: save `/etc/pf.conf`, any affected anchor files, `pfctl -s info`
and current filter rules. Use a dedicated project anchor, syntax-check with
`sudo pfctl -nf /path/to/candidate.conf`, and retain the OS's existing rules/anchors.
The parent ruleset must actually reference the project anchor; loading an unused
anchor changes no traffic. Rule order matters: earlier matching `quick` rules can
bypass a later anchor. Inspect the effective rules and counters, not just files.
Have the rollback commands ready in a second terminal before loading anything.
Do not flush all rules, overwrite Apple anchors, or use blanket `pfctl -d` as rollback.
An exact live ruleset must be prepared against each Mac's existing pf state;
this repo does not automatically install firewall rules.

Test the same backend from two hosts: Anshuman's direct HTTP succeeds; another
Mac's direct HTTP times out/fails. HTTPS via nginx must still succeed from the
blocked client. Save the allow result, deny result, successful HTTPS, effective
rules/counters and rollback result. Bineet's MDM restrictions may require faculty
help; identify this tonight, not during evaluation.

## Extension D: repeat existing failover and recovery

Keep edge access/error logs visible. From a client run `bash common/lb-test.sh 10`.
Stop A with Ctrl+C; requests should succeed using B. Restart A and generate more
traffic after the 10-second failure interval; show both A and B returning.
Explain passive detection, retry, recovery, and why the edge is still a single
point of failure. Do not stop the whole Docker/edge host to demonstrate DNS failure.

## Extension E: standby edge and DNS cutover

1. On Vridhi's Mac install/configure a second nginx with the same upstream IPs,
   app/api server names, and TLS coverage. Change `X-Edge` to `edge-standby`.
   Use a separate config copy; the old generator hardcodes `edge-mac2`.
2. Provision a matching TLS certificate and key securely. Both edges must chain to
   the CA trusted by clients (or both CAs must be trusted). A public CA certificate
   alone cannot sign a new server certificate. Keep CA private keys private.
3. For port 443 test before cutover:
   `curl --resolve app.team1.test:443:STANDBY_IP https://app.team1.test/api/status`
   with a trusted CA or explicit `--cacert`. This preserves name/SNI/certificate
   verification but bypasses DNS, so it is a preparation test only.
4. Isolation from C must now permit the standby edge's source address too, or the
   standby cannot reach A. Record this temporary policy change and restore after
   migration. Vridhi's host will also legitimately reach its local B. Do the
   non-edge blocked-client test from Bineet against B, not from an edge host.
5. Prime a real client's app.team1.test DNS cache with the old edge IP. Keep both
   edges running. Change EDGE_IP in **both DNS hosts' Docker `.env` files** to the
   standby IP; recreate DNS containers. Update both app and api consistently.
6. A fresh lookup gets the standby IP. A previously cached client may still use
   the old IP until remaining TTL expires. Show remote IP and X-Edge in curl output
   and DNS logs, then show that client moving to the standby. Do not use --resolve
   in this DNS-based demonstration. Existing TCP connections may outlive DNS TTL:
   TTL expiration does not forcibly move established sessions.
7. Restore both DNS EDGE_IP values to Anshuman's IP, recreate, verify clients
   return, then restore the temporary isolation-policy exception. Keep old edge
   online for the TTL window; manual DNS cutover is not automatic edge failover.

## Extension F: diagnose out loud

| Check | Command idea | Interpretation |
|---|---|---|
| Resolver settings | `networksetup -getdnsservers Wi-Fi`, `scutil --dns` | Are both intended resolvers configured? Any stale per-domain resolver? |
| DNS servers | `dig @PRIMARY app.team1.test`, repeat @BACKUP | Correct answer? Service timeout? Mismatched records? |
| OS DNS | `dscacheutil -q host -a name app.team1.test` | Compare cached/system answer to direct server answers |
| IP / TCP | `ping EDGE_IP`, `nc -vz -G 3 EDGE_IP 443` | Ping failure alone does not prove TCP is blocked |
| TLS | `curl -v --max-time 10 https://app.team1.test/health` | Check CA trust, SAN/name, dates and handshake |
| HTTP | `curl -i --max-time 10 https://app.team1.test/api/status` | 502/504 suggests upstream issue; inspect nginx logs and backend reachability from the edge |

The old diagnose.sh knows only one DNS and one edge. It flags standby resolution
as a wrong record, and flags intentional client-to-backend blocking as a problem.
Interpret it accordingly; these are Phase 1 assumptions. Existing capture.sh also
filters only the primary DNS and original edge; adapt the filter for backup/standby.
For Wireshark evidence, capture on a **remote client** interface: traffic to a
service on the same Mac may not traverse en0.

## Evidence, report, and evaluation

Keep fresh outputs under `04-Evidence/Phase2/` with A-F subfolders. For each
extension record setup, fault/change, timestamp, observed result, explanation,
recovery and screenshot/log/pcap filename. Update the architecture and configuration
bundle with the actual deployed topology, IPs, two DNS configs, standby nginx and
firewall rules. Add an evidence index so each item can be found quickly.

Write the Phase 2 final report only after tests: changes from Phase 1, actual
resilience results, troubleshooting findings, and a paragraph of learning per
extension. Do not turn intended results into reported measurements.

Rehearse the brief's 11 steps: topology; LAN; DNS; trusted HTTPS; A/B load balancing;
Wireshark DNS/TCP/TLS; cache/304; backend failure; DNS/TTL/cutover; fault diagnosis;
individual viva. Assign one operator, one evidence/log observer and one narrator,
then rotate so everyone can explain the full flow.

### Viva essentials

* Backup DNS survives resolver failure, not application/edge failure.
* DNS TTL caches name-to-IP mappings; HTTP max-age caches representations.
* 304 validates a cached representation; it does not contain a replacement body.
* Reverse proxy terminates the client connection and opens a backend connection.
* TLS ends at nginx; backend traffic here is plain HTTP.
* Passive backend failover is already present; automatic edge failover is not.
* Port publishing exposes a container service via the host IP; it is not backend isolation.
* `--resolve` bypasses DNS for a controlled test; `-k` disables TLS verification and
  must not be used to claim a successful trusted-HTTPS demo.

Technical references: [Docker Desktop networking](https://docs.docker.com/desktop/features/networking/),
[dnsmasq TTL/configuration](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html),
[nginx upstream failure parameters](https://nginx.org/en/docs/http/ngx_http_upstream_module.html).
