# Configuration Bundle — Team .venv (Phase 1)

Every configuration file that runs the private service platform, as deployed on 3 October 2026.

| File | Machine | Deployed at | Purpose |
|---|---|---|---|
| [`team.env`](team.env) | all 4 Macs | `cn-project/team.env` | Single source of truth: domain, the 4 IP addresses, backend ports. Every script reads it |
| [`dns/dnsmasq.conf`](dns/dnsmasq.conf) | Mac 1 | `/opt/homebrew/etc/dnsmasq.conf` | Private DNS server for the `team1.test` zone (A records, TTL, upstream forwarding, query logging) |
| [`dns/etc-resolver-team1.test`](dns/etc-resolver-team1.test) | Mac 1 | `/etc/resolver/team1.test` | Makes Mac 1 itself (also a client) send only `*.team1.test` lookups to its local dnsmasq |
| [`edge/nginx-servers-team1.conf`](edge/nginx-servers-team1.conf) | Mac 2 | `/opt/homebrew/etc/nginx/servers/team1.conf` | Edge: HTTP→HTTPS redirect, TLS termination, HTTP/2, round-robin upstream pool, passive health checks, evidence headers |
| [`edge/team1-root-ca.crt`](edge/team1-root-ca.crt) | all clients | System keychain (trusted root) | Public certificate of the team's local CA (safe to share; the private keys are not included) |
| [`edge/TLS-SETUP.md`](edge/TLS-SETUP.md) | Mac 2 + clients | — | How the CA and server certificate were created and trusted |
| [`backend/BACKEND-LAUNCH.md`](backend/BACKEND-LAUNCH.md) | Mac 3, Mac 4 | — | How to start Backend A and Backend B, endpoints, and the managed-Mac note |

Client DNS setting (Mac 2, Mac 3, Mac 4) was applied with:

```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.6.171     # use Mac 1 as resolver
sudo networksetup -setdnsservers Wi-Fi Empty          # revert to DHCP-provided DNS
```

Firewall rules: none were used in Phase 1 (pf / service isolation is a Phase 2 extension).

The scripts that generated these files are in [`../03-Source-Code/`](../03-Source-Code/).
