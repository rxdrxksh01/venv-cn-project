# Evaluation-day checklist - Team .venv

These are role-specific commands. A command starting with a relative path assumes
the stated folder. Do not paste the terminal prompt or output as a command.
Current addresses are from the 24-25 November session; DHCP may change them.

## Before the slot

1. All three available Macs join the same LAN; confirm `ipconfig getifaddr en0`.
   Record the actual interface if different. From 03-Source-Code, run
   `bash common/netinfo.sh` on each Mac and capture pairwise pings between the
   three current addresses. The old ping helper still lists a logical Mac 1
   role on Anshuman's physical Mac, so label the combined role clearly.
2. If IPs changed, update native team.env on all Macs, both Docker .env bind/edge
   addresses, both nginx upstream configs, firewall templates, topology and notes.
   Regenerate/reload DNS/native configs as appropriate. Certificates use DNS SANs
   and do not need replacement solely because the IP changed.
3. On each DNS host, from 03-Source-Code/docker-dns:
   `docker compose up -d --wait` and `docker compose ps`.
   Check both host UDP and TCP lookups from another Mac. A healthy internal
   container check alone does not establish published-port reachability.
4. Bineet, from 03-Source-Code:
   `/usr/bin/python3 backend/server.py A 3001`.
   Vridhi, from 03-Source-Code: `python3 backend/server.py B 3002`.
   Leave both terminals running and allow incoming Python connections if asked.
5. Anshuman: `sudo /opt/homebrew/bin/nginx -t`; start nginx if not running,
   or reload its checked configuration if already running.
6. Clients list both DNS servers. Save original DNS settings once before changing
   them. Do not overwrite an earlier original-settings backup with project values.
   `sudo networksetup -setdnsservers Wi-Fi 10.7.31.231 10.7.2.240`.
7. Check trusted HTTPS and A/B responses; from 03-Source-Code run
   `bash common/lb-test.sh 10` and `bash common/cache-test.sh`.
8. Open the Phase 2 evidence index, report PDF, and historical Phase 1 pcap before
   presenting. Keep Macs awake/on power. Pre-build images on both Macs.

## Fixed demonstration sequence

| Step | Show |
|---|---|
| 1 | Current three-Mac topology, IP/service inventory, combined DNS+edge role |
| 2 | Current LAN inventory and pairwise reachability |
| 3 | Both team resolvers answering app/api, with TTL |
| 4 | HTTPS by domain name; certificate verified, no -k |
| 5 | X-Backend A/B and nginx's X-Edge / X-Upstream-Addr |
| 6 | Wireshark DNS, TCP SYN/SYN-ACK/ACK, TLS and encrypted data; label old captures |
| 7 | Cache-Control, ETag and 304 using the original cache script |
| 8 | Stop A, B-only HTTP 200; restart A and show recovery |
| 9 | Backup DNS, TTL/cache flush, backend isolation, standby DNS cutover |
| 10 | Faculty-injected fault: diagnose layer by layer, record actual result |
| 11 | Individual viva: everyone explains the complete flow |

## A: backup DNS

Client has both resolver IPs. On Anshuman, from docker-dns, `docker compose stop dns`.
On Bineet, flush (`sudo dscacheutil -flushcache`, `sudo killall -HUP mDNSResponder`),
then `dscacheutil -q host -a name api.team1.test`. On Vridhi, from docker-dns,
`docker compose logs --since=2m dns | grep 'api.team1.test'`. Record the API query
on backup, not loopback healthcheck noise. Restore primary with `docker compose start dns`.

## B: TTL and manual flush

Use ttl-demo.team1.test, not the production app record. Temporarily give the test
client only primary DNS to isolate the experiment. In primary docker-dns, use
`sh set-ttl-record.sh 10.7.31.231` for the starting value. Prime the client, then
change to `10.7.2.240` with the same helper. Timestamp direct DNS and system
answers every five seconds. Do not flush during expiry observation. For a second
experiment, prime, change, manually flush before 30 seconds and observe the new
answer. Restore the original record and both client resolver addresses.

## C: isolation and rollback

Before applying anything, save the current main PF file/rules, confirm the existing
parent anchor, syntax-check the project rule, and have rollback ready. On Bineet
load only the A rule into com.apple/cn-team1-a; on Vridhi load only the B rule into
com.apple/cn-team1-b. Use `pfctl -E` once per test and save its newly issued token.
Do not reuse a token from a previous night's test.

Show edge direct HTTP succeeds, a non-edge remote client direct request fails,
and trusted HTTPS through nginx succeeds. Capture anchor counters. Remove only
the project rules using `pfctl -a PROJECT_ANCHOR -F rules`, then release only that
test's enable reference with `pfctl -X TOKEN`. Confirm restored direct access.
Do not flush the main ruleset or use blanket `pfctl -d` as rollback.

The source templates have labels; the demonstrated pasted rules omitted labels
but enforced the same source/destination policy. For migration, rollback these
filters first or deliberately allow the standby source as well.

## E: standby migration and cleanup

Vridhi: check port 443, pause only supportdesk_nginx if needed/authorized, then
start the already-provisioned standalone edge:

```bash
sudo "$(command -v nginx)" -p "$HOME/cn-standby/" -c nginx.conf -t
sudo "$(command -v nginx)" -p "$HOME/cn-standby/" -c nginx.conf
```

Preparation only: test standby using --resolve app.team1.test:443:10.7.2.240.
For the actual demonstration, Bineet uses ordinary HTTPS in a timestamped loop
showing HTTP status, X-Edge and remote_ip. No --resolve, no cache flush during
the transition. In docker-dns on BOTH DNS hosts run:

```bash
sh set-edge-record.sh 10.7.2.240
```

Verify both direct DNS answers are the standby IP, and observe the client move
from original to standby while requests succeed. Keep both edges up throughout.
To restore, use `sh set-edge-record.sh 10.7.31.231` on BOTH hosts. Flush clients
and verify edge-mac2 / 10.7.31.231 / HTTP 200 before stopping standby:

```bash
sudo "$(command -v nginx)" -p "$HOME/cn-standby/" -c nginx.conf -s stop
docker start supportdesk_nginx
```

Do not stop backup DNS or Backend B during this cleanup. The record helpers
require the updated image. Their overrides last until restart; .env EDGE_IP
remains the baseline original edge. Run helpers inside docker-dns or use their
absolute paths; running `sh set-edge-record.sh` from ~ cannot find the script.

## F: systematic diagnosis

1. DNS settings: `networksetup -getdnsservers Wi-Fi`, `scutil --dns`.
2. Compare `dig @PRIMARY app.team1.test`, `dig @BACKUP ...` and the system lookup.
3. Check resolved IP/port: `nc -vz -G 3 EDGE_IP 443`. Ping alone is not sufficient.
4. TLS: `curl -v --max-time 10 https://app.team1.test/api/status`; check trust/name/date.
5. HTTP: status and edge/backend headers; inspect nginx logs and backends from the edge.
6. Explain the affected layer, make the smallest correction, verify and record.

Actual faculty fault, diagnosis, fix/isolation, result and learning remain to be
recorded in REPORT.md after evaluation. The existing wrong-port transcript is a
read-only rehearsal, not the faculty challenge.
