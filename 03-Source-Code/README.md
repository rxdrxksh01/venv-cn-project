# CN Project — Private Network Service Platform (team1)

Everything runs locally on our 4 Macs. No cloud, no AWS.
This folder has all the configs, code and scripts. **Each person opens only their own guide.**

| Person | Mac | Role | Your guide |
|---|---|---|---|
| Person 1 | Mac 1 | Primary DNS (dnsmasq) + test client + coordinator | [PERSON1-MAC1-DNS.md](PERSON1-MAC1-DNS.md) |
| Person 2 | Mac 2 | Edge: nginx reverse proxy + load balancer + HTTPS/TLS | [PERSON2-MAC2-EDGE.md](PERSON2-MAC2-EDGE.md) |
| Person 3 | Mac 3 | Backend A (port 3001) | [PERSON3-MAC3-BACKEND-A.md](PERSON3-MAC3-BACKEND-A.md) |
| Person 4 | Mac 4 | Backend B (port 3002) + test client (collects most evidence) | [PERSON4-MAC4-BACKEND-B.md](PERSON4-MAC4-BACKEND-B.md) |

Once it works, everyone uses [DEMO-AND-FAILURES.md](DEMO-AND-FAILURES.md) for the required failure demos, the review demo and viva prep.

---

## How a request travels (what we are building)

```
                 (1) DNS query  UDP 53                       Mac 1  dnsmasq
   Client  ───────────────────────────────────────────────▶  "app.team1.test = Mac 2's IP"
 (Mac 1/4) ◀───────────────────────────────────────────────
     │
     │ (2) TCP 3-way handshake → (3) TLS handshake → (4) encrypted HTTP request, port 443
     ▼
   Mac 2  nginx  ── TLS ends here, round robin ──┬──▶ Mac 3  Backend A  :3001  (plain HTTP)
                                                 └──▶ Mac 4  Backend B  :3002  (plain HTTP)
```

The client only ever knows the **name** `app.team1.test`. DNS turns it into Mac 2's IP.
nginx picks a backend, so the client never needs the backend IPs.

| Role | Cloud equivalent |
|---|---|
| Mac 1 dnsmasq | Route 53 (private hosted zone) |
| Mac 2 nginx | AWS ALB / CDN edge, TLS termination |
| Mac 3 / Mac 4 backends | EC2 instances in a target group |

---

## Before you start (every Mac)

1. **Same network.** All 4 Macs join the **same** Wi-Fi. College Wi-Fi often blocks laptops from
   talking to each other ("client isolation"). If ping fails, use a **phone hotspot** or a home router.
2. **Turn off** VPNs and iCloud Private Relay (System Settings → Apple Account → iCloud → Private Relay).
3. **macOS Firewall** (System Settings → Network → Firewall). Easiest: turn it **off** while working on
   the project. If you keep it on, click **Allow** when macOS asks about python3 / nginx / dnsmasq.
4. **Homebrew** is needed on Mac 1 (dnsmasq), Mac 2 (nginx) and Mac 4 (Wireshark). Check with `brew -v`. Install it with:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
5. **python3** (Mac 3, Mac 4): run `python3 --version`. If macOS offers to install developer tools, accept.
6. **Wireshark** (Mac 4, optionally Mac 1): `brew install --cask wireshark`

## Step 0: share IPs, then get the folder

1. Everyone (on the shared Wi-Fi) runs this and sends the IP to Person 1 on the group chat:
   ```bash
   ipconfig getifaddr en0
   ```
2. Person 1 writes the 4 IPs into `team.env`, zips the folder, and sends `cn-project.zip` to everyone (AirDrop is easiest).
3. Everyone unzips it, then:
   ```bash
   cd ~/Downloads/cn-project      # or wherever you unzipped it
   chmod +x lib.sh */*.sh
   cat team.env                   # check the 4 IPs are filled in
   ```

> **If an IP changes** (new day, different hotspot), update `team.env` on **all 4 Macs**, then re-run:
> Person 1 `./dns/setup-dns.sh`, Person 2 `./edge/setup-nginx.sh`, Persons 2/3/4 `./common/use-team-dns.sh primary`.
> Certificates don't need to be redone.

## Order of work

| Step | Who | What |
|---|---|---|
| 1 | everyone | `./common/netinfo.sh` and `./common/ping-all.sh` (Task A evidence) |
| 2 | Person 1 | Start DNS: `./dns/setup-dns.sh` |
| 2 | Person 3, Person 4 | Start backends: `./backend/start-backend.sh` (leave the window open) |
| 2 | Person 2 | Make certs + start nginx: `./edge/make-certs.sh`, `./edge/setup-nginx.sh` |
| 3 | Person 2 | `./edge/share-ca.sh` so the others can download the CA certificate |
| 3 | Persons 1, 3, 4 | `./common/trust-ca.sh` |
| 4 | Persons 2, 3, 4 | Point DNS at Mac 1: `./common/use-team-dns.sh primary` |
| 5 | Person 4, Person 1 | Test: `./common/lb-test.sh`, `./common/cache-test.sh`, `./common/capture.sh` |

Step 2 can happen in parallel. **Phase 1 is done when** a client opens `https://app.team1.test`
with no certificate warning and sees both `X-Backend: A` and `X-Backend: B`.

## What each script does

| Script | Where | Purpose |
|---|---|---|
| `common/netinfo.sh` | all | IP, mask, gateway, interface, MAC address → evidence |
| `common/ping-all.sh` | all | ping every other Mac → evidence |
| `dns/setup-dns.sh` | Mac 1 | install + configure dnsmasq |
| `dns/point-record.sh app <ip>` | Mac 1 | change a DNS record (wrong-IP failure demo) |
| `backend/start-backend.sh` | Mac 3, Mac 4 | run Backend A / B |
| `edge/make-certs.sh` | Mac 2 | create the local CA + server certificate |
| `edge/setup-nginx.sh` | Mac 2 | nginx TLS + load balancer |
| `edge/share-ca.sh` | Mac 2 | serve ca.crt on the LAN for a few minutes |
| `common/trust-ca.sh` | clients | trust the CA in keychain + curl |
| `common/use-team-dns.sh primary\|wrong\|off` | Mac 2/3/4 | set this Mac's DNS server |
| `common/lb-test.sh [n]` | clients | repeated requests showing X-Backend |
| `common/cache-test.sh` | clients | Cache-Control, ETag, 304 |
| `common/capture.sh [tls13]` | Mac 4 | tcpdump → .pcap for Wireshark |
| `common/diagnose.sh` | any | layer-by-layer check (DNS → IP → TCP → TLS → HTTP) |

All evidence (text output, .pcap files) is saved into `evidence/`. Add screenshots there too.

## Common problems

| Symptom | Likely cause / fix |
|---|---|
| ping between Macs fails | Not on the same Wi-Fi, client isolation (use a hotspot), or Firewall "stealth mode" is on |
| `dig app.team1.test` times out | This Mac's DNS isn't Mac 1 (`./common/use-team-dns.sh primary`), or dnsmasq is stopped / blocked by the firewall on Mac 1 |
| `curl: (7) Failed to connect ... 443` | nginx not running on Mac 2 (`sudo nginx`), or wrong IP in DNS |
| `SSL certificate problem` | Run `./common/trust-ca.sh` on that Mac, and quit + reopen the browser |
| 502 Bad Gateway | nginx is fine but can't reach the backends: are they running? Is the IP right in team.env? |
| Backend reachable on its own Mac but not from Mac 2 | macOS firewall blocking python3: click Allow, or turn the firewall off |
| Everything broke after a Wi-Fi change | IPs changed. See the "If an IP changes" note above |

Allow an app through the macOS firewall without turning it off (example for dnsmasq):
```bash
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
sudo $FW --add "$(realpath $(brew --prefix)/sbin/dnsmasq)"; sudo $FW --unblockapp "$(realpath $(brew --prefix)/sbin/dnsmasq)"
```

## Undo everything (after the project)

```bash
./common/use-team-dns.sh off                       # Mac 2/3/4: normal DNS again
sudo brew services stop dnsmasq; sudo rm -f /etc/resolver/team1.test   # Mac 1
sudo nginx -s stop                                 # Mac 2
sudo security delete-certificate -c "team1 Local Root CA" /Library/Keychains/System.keychain  # clients
```
