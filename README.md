# Team .venv — Private Network Service Platform · Phase 1 Deliverables

Computer Networks course project. Four macOS laptops on one Wi-Fi network serve `https://app.team1.test`
through a private DNS server, an nginx TLS edge / load balancer and two REST backends. No cloud.

Team name: **.venv** · private DNS zone: **team1.test** (the zone name used in all configs and evidence).

| Machine | Member | Role | IP |
|---|---|---|---|
| Mac 1 | Rudraksh | Private DNS (dnsmasq) + test client | 10.7.6.171 |
| Mac 2 | Anshuman | Edge: nginx reverse proxy, TLS termination, load balancer | 10.7.20.28 |
| Mac 3 | Bineet | Backend A (port 3001) | 10.7.20.243 |
| Mac 4 | Vridhi Chaudhary | Backend B (port 3002) + main test client | 10.7.8.144 |

## Where everything is

| Deliverable (Section 9 of the brief) | Folder | Start with |
|---|---|---|
| **Architecture Document** — topology, roles/IP/service table, request-flow diagram per protocol layer | [`01-Architecture-Document/`](01-Architecture-Document/) | `Architecture-Document.pdf` |
| **Configuration Bundle** — dnsmasq config, nginx config, TLS setup notes, backend launch instructions | [`02-Configuration-Bundle/`](02-Configuration-Bundle/) | `README.md` |
| **Backend Source Code** — both backends and all helper scripts | [`03-Source-Code/`](03-Source-Code/) | `README.md`, `backend/server.py` |
| **Evidence Folder** — DNS, curl/browser headers, Wireshark (DNS, TCP, TLS), caching, all failure scenarios | [`04-Evidence/`](04-Evidence/) | `EVIDENCE-INDEX.md` |

## Phase 1 at a glance

| Task | Result | Evidence |
|---|---|---|
| A · Private LAN | Pass | `04-Evidence/A-LAN-Setup/` |
| B · Private DNS | Pass — `app.team1.test → 10.7.20.28`, used by Mac 2, 3, 4 | `B-Private-DNS/` |
| C · Two backends | Pass — :3001 and :3002 with `X-Backend` | `C-Backends/` |
| D · Edge + load balancing | Pass — A/B round robin over HTTP/2 | `D-Load-Balancing/` |
| E · HTTPS / TLS | Pass — own CA, `SSL certificate verify ok`, no `-k` | `E-HTTPS-TLS/` |
| F · HTTP caching | Pass — `Cache-Control`, `ETag`, `304 Not Modified` | `F-HTTP-Caching/` |
| G · Protocol capture | Pass — DNS → TCP → TLS → encrypted HTTP in Wireshark | `G-Packet-Capture/` |
| 6.3 Failure scenarios (all 5) | Done — wrong DNS server, wrong record, one backend down, both down (502), wrong port | `H-Failure-Scenarios/` |
