# Team .venv - Live evaluation command book
## What to run, who runs it, what it proves, and how to restore

Use CLASSROOM-RESTART.md first if you have moved networks. These commands load
the current team.env; they do not assume last night's IPs. Use one fault at a
time and save output before rollback. Keep backend Terminal windows open.
Copy executable commands from this Markdown file; PDF lines may wrap for print.

## 0. Start EVERY new Terminal correctly

Open a Terminal inside your own project repo, then:

```bash
source "$(git rev-parse --show-toplevel)/03-Source-Code/classroom-shell.sh"
```

It prints current addresses. CN_EDGE_IP is Anshuman, CN_A_IP is Bineet, CN_B_IP
and CN_BACKUP_DNS_IP are Vridhi. CN_REPO is this Mac's repo path. If the command
says this is not a Git repository, change to the repo first. Variables do not
automatically carry over into another Terminal window.

## 1. "Show the topology, IPs and LAN connectivity"

Every Mac:

```bash
ipconfig getifaddr "$CN_IFACE"
ipconfig getoption "$CN_IFACE" subnet_mask
route -n get default
ifconfig "$CN_IFACE"
bash "$CN_REPO/03-Source-Code/common/netinfo.sh"
```

Each Mac pings the OTHER TWO physical Macs using the current variables:

```bash
ping -c 3 "$CN_EDGE_IP"
ping -c 3 "$CN_A_IP"
ping -c 3 "$CN_B_IP"
```

Skip the self-ping when presenting pairwise reachability. Show the updated
topology diagram and live team.env. Explain that primary DNS and edge now share
one physical Mac; do not pretend Rudraksh's original laptop is present.

## 2. "Show the backend processes and ports"

On Bineet:

```bash
lsof -nP -iTCP:3001 -sTCP:LISTEN
curl -i http://127.0.0.1:3001/api/status
```

On Vridhi use 3002. On Anshuman, before isolation:

```bash
curl -i --max-time 5 "http://$CN_A_IP:3001/api/status"
curl -i --max-time 5 "http://$CN_B_IP:3002/api/status"
```

Expected: correct A/B identifiers and ports. Null X-Forwarded-For is normal for
direct tests; requests through nginx include the forwarded client. Binding on
0.0.0.0 permits LAN access; direct access becomes intentionally restricted in C.

<!-- pagebreak -->

## 3. "Prove DNS, TCP, TLS and HTTP work"

Any remote client, preferably Bineet:

```bash
networksetup -getdnsservers Wi-Fi
dig @"$CN_PRIMARY_DNS_IP" app.team1.test +noall +answer
dig @"$CN_BACKUP_DNS_IP" api.team1.test +noall +answer
dig @"$CN_PRIMARY_DNS_IP" app.team1.test +tcp +short
dscacheutil -q host -a name app.team1.test
nc -vz -G 3 "$CN_EDGE_IP" 443
curl -v --max-time 15 https://app.team1.test/api/status
```

Expected: edge IP from DNS, open TCP 443, certificate verification succeeds,
HTTP 200, edge/backend identifiers. dig @IP tests that server; dscacheutil/curl
use the system resolver. The real demo uses the name without --resolve or -k.

Anshuman can inspect the public installed certificate without revealing keys:

```bash
openssl x509 -in "$CN_BREW_PREFIX/etc/nginx/team-certs/server.crt" \
  -noout -subject -issuer -dates -ext subjectAltName
```

## 4. "Show load balancing and HTTP versions"

```bash
bash "$CN_REPO/03-Source-Code/common/lb-test.sh" 10
curl -sSI --http1.1 https://app.team1.test/api/status
curl -sSI --http2 https://app.team1.test/api/status
```

Show X-Backend A and B, X-Edge and X-Upstream-Addr. Healthy round robin should
distribute requests; exact alternation is not a universal guarantee with several
workers/clients or failures. HTTP/2 is between client and nginx, not the Python app.

## 5. "Show caching / ETag / 304"

```bash
bash "$CN_REPO/03-Source-Code/common/cache-test.sh"
```

Or show the steps explicitly:

```bash
curl -sSI https://app.team1.test/api/cached
CN_ETAG="$(curl -sSI https://app.team1.test/api/cached |
  awk -F': ' 'tolower($1)=="etag"{gsub("\r","",$2);print $2;exit}')"
curl -i -H "If-None-Match: $CN_ETAG" https://app.team1.test/api/cached
curl -sSI https://app.team1.test/api/status
```

Expected: max-age=60 and ETag; matching conditional request returns 304 with
no body; status is no-store. curl is not itself a persistent browser cache.

<!-- pagebreak -->

## 6. "Stop primary DNS and prove backup works" - Extension A

All clients list both current DNS addresses. Bineet:

```bash
sudo networksetup -setdnsservers Wi-Fi "$CN_PRIMARY_DNS_IP" "$CN_BACKUP_DNS_IP"
```

Anshuman, from the DNS folder:

```bash
cd "$CN_DNS_DIR"
docker compose stop dns
docker compose ps -a
```

Bineet:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
date '+%H:%M:%S'
dscacheutil -q host -a name api.team1.test
curl --max-time 15 https://api.team1.test/api/status
```

Vridhi, from the DNS folder:

```bash
cd "$CN_DNS_DIR"
docker compose logs --since=2m dns | grep 'api.team1.test'
```

Expected: uncached system lookup succeeds; backup logs the API query; HTTPS
can still use the edge. Healthchecks now use edge.team1.test, so API queries
are distinct. DNS failure detection may take time; report observed behavior.

Restore on Anshuman:

```bash
cd "$CN_DNS_DIR"
docker compose start dns
docker compose ps
```

## 7. "Stop A, then recover it" - Extension D

Bineet presses Control+C in the Terminal running A. Client:

```bash
bash "$CN_REPO/03-Source-Code/common/lb-test.sh" 6
```

Expected: HTTP 200 from B. On Anshuman, observe error/access logs:

```bash
sudo tail -n 20 "$CN_BREW_PREFIX/var/log/nginx/error.log"
sudo tail -n 20 "$CN_BREW_PREFIX/var/log/nginx/team1_access.log"
```

Restore A on Bineet: `/usr/bin/python3 "$CN_REPO/03-Source-Code/backend/server.py" A 3001`.
After about 10-15 seconds and new requests, show both A/B again. If asked to
stop BOTH backends, expect nginx 502 while DNS/TLS still work; restart both
immediately afterward. Stop only the Python processes with Control+C, not laptops.

<!-- pagebreak -->

## 8. "Demonstrate DNS TTL" - Extension B

Prepare the record first. Anshuman:

```bash
cd "$CN_DNS_DIR"
sh set-ttl-record.sh "$CN_EDGE_IP"
```

For this controlled experiment Bineet temporarily uses only primary DNS, then
starts a sampled system-lookup loop. Have the record-change command ready first:

```bash
sudo networksetup -setdnsservers Wi-Fi "$CN_PRIMARY_DNS_IP"
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
for i in {1..12}; do
  date '+%H:%M:%S'
  dscacheutil -q host -a name ttl-demo.team1.test
  sleep 5
done
```

Immediately after the first old-IP answer, Anshuman:

```bash
cd "$CN_DNS_DIR"
sh set-ttl-record.sh "$CN_B_IP"
date '+%H:%M:%S'
dig @"$CN_PRIMARY_DNS_IP" ttl-demo.team1.test +noall +answer
```

Observe: server already has the new answer, client may retain the old one, then
later gets the new one. Do not flush during this loop. Report actual sampled
timestamps, not an invented exact expiry. This name is DNS-only; pointing it to
Vridhi does not itself migrate the real application.

## 9. "Flush the cache manually and show immediate change"

After the first experiment, Bineet flushes and primes the current B-IP answer:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
date '+%H:%M:%S'
dscacheutil -q host -a name ttl-demo.team1.test
```

Immediately Anshuman restores the server record:

```bash
cd "$CN_DNS_DIR"
sh set-ttl-record.sh "$CN_EDGE_IP"
date '+%H:%M:%S'
dig @"$CN_PRIMARY_DNS_IP" ttl-demo.team1.test +noall +answer
```

Bineet repeats the flush and lookup within 30 seconds of priming. Expected:
new edge IP without waiting for advertised expiry. Save timestamps. Finally:

```bash
sudo networksetup -setdnsservers Wi-Fi "$CN_PRIMARY_DNS_IP" "$CN_BACKUP_DNS_IP"
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

<!-- pagebreak -->

## 10. "Restrict a backend to the edge" - Extension C

Use templates updated for the CURRENT addresses/interface. Demonstrate each
backend separately; check the non-edge direct request succeeds before loading
the restriction. Do not apply filters during initial startup or migration.

For A, Bineet sets these in the SAME Terminal used for the whole PF test:

```bash
CN_PF_ANCHOR='com.apple/cn-team1-a'
CN_PF_FILE="$CN_REPO/03-Source-Code/firewall/backend-a.pf"
```

For B, Vridhi instead sets:

```bash
CN_PF_ANCHOR='com.apple/cn-team1-b'
CN_PF_FILE="$CN_REPO/03-Source-Code/firewall/backend-b.pf"
```

On the selected backend Mac, inspect/backup and syntax-check:

```bash
CN_PF_BACKUP="$HOME/cn-pf-demo-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$CN_PF_BACKUP"
cp /etc/pf.conf "$CN_PF_BACKUP/pf.conf.before"
sudo pfctl -s info | tee "$CN_PF_BACKUP/status.before"
sudo pfctl -sr > "$CN_PF_BACKUP/main-rules.before"
cat "$CN_PF_FILE"
sudo pfctl -a "$CN_PF_ANCHOR" -nf "$CN_PF_FILE"
```

Confirm the main ruleset still references com.apple/* as in our recorded setup.
If it differs or the project anchor contains rules from an unfinished prior
test, inspect/restore that state first. Stop if syntax fails; do not run the
next block. The generic -f warning does not mean we replaced the main rules.

Apply and enable ONCE:

```bash
sudo pfctl -a "$CN_PF_ANCHOR" -f "$CN_PF_FILE"
sudo pfctl -E 2>&1 | tee "$CN_PF_BACKUP/enable.txt"
sudo pfctl -a "$CN_PF_ANCHOR" -sr
```

Test with fresh curl processes. Edge direct HTTP to the selected backend must
succeed; Vridhi direct to A or Bineet direct to B must fail. That same remote
client's `curl https://app.team1.test/api/status` must still succeed. Then:

```bash
sudo pfctl -a "$CN_PF_ANCHOR" -vvsr
sudo pfctl -a "$CN_PF_ANCHOR" -F rules
CN_PF_TOKEN="$(awk '/Token/ {print $NF; exit}' "$CN_PF_BACKUP/enable.txt")"
```

If the token is present, release it and compare to the original status:

```bash
sudo pfctl -X "$CN_PF_TOKEN"
sudo pfctl -s info
```

Do not run -X with an empty token, do not reuse an old token, do not flush all
rules, and do not use blanket -d. Verify the remote client's direct access works
again. Keep the new token file until rollback is confirmed.

<!-- pagebreak -->

## 11. "Migrate to the standby edge" - Extension E

Preparation: both PF tests are rolled back (or standby source is deliberately
allowed). Vridhi's ~/cn-standby/nginx.conf has CURRENT upstream IPs; tls.pem is
already provisioned and trusted. DNS containers remain running. Vridhi checks:

```bash
lsof -nP -iTCP:443 -sTCP:LISTEN
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

If supportdesk_nginx owns 443 and can be paused for the demo, stop ONLY that
container with `docker stop supportdesk_nginx`. Then on Vridhi:

```bash
sudo "$CN_NGINX" -p "$HOME/cn-standby/" -c nginx.conf -t
sudo "$CN_NGINX" -p "$HOME/cn-standby/" -c nginx.conf
```

Anshuman tests preparation (this bypasses DNS but still verifies TLS):

```bash
curl -v --max-time 15 --resolve "app.team1.test:443:$CN_B_IP" \
  https://app.team1.test/api/status
```

Expected: verified certificate, HTTP 200, X-Edge edge-standby. For the ACTUAL
cutover Bineet flushes cache, then runs ordinary requests:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
for i in {1..20}; do
  date '+%H:%M:%S'
  curl -sS --max-time 10 -o /dev/null -D - \
    -w 'Connected-IP: %{remote_ip}\n' \
    https://app.team1.test/api/status |
    grep -iE '^(HTTP/|x-edge:|x-backend:|Connected-IP:)'
  sleep 5
done
```

After the first original-edge answer, BOTH DNS hosts run:

```bash
cd "$CN_DNS_DIR"
sh set-edge-record.sh "$CN_B_IP"
```

Query both DNS servers directly; both must publish B's IP. Leave Bineet's loop
running without flushing. Observe old edge then standby; save successful HTTP
statuses. Keep both edges up. A direct DNS change is not an automatic failover.

Rollback on BOTH DNS hosts: `sh set-edge-record.sh "$CN_EDGE_IP"` from the DNS
folder. Check both answers, flush clients, and show edge-mac2/original IP/200.
Only then Vridhi stops standalone nginx and restores the container she paused:

```bash
sudo "$CN_NGINX" -p "$HOME/cn-standby/" -c nginx.conf -s stop
sleep 2
docker start supportdesk_nginx
```

Do not restart Supportdesk if it was not running/paused for this demo. Never
stop backup DNS or Backend B as part of standby cleanup. Live DNS overrides
reset to .env EDGE_IP on container restart.

<!-- pagebreak -->

## 12. "Show DNS, TCP and TLS in Wireshark"

Use Bineet as a remote client: its DNS and HTTPS traffic cross Wi-Fi rather
than staying inside the DNS/edge host. Open TWO repo Terminals and load the
classroom shell variables in each. In Terminal 1:

```bash
CN_PCAP="$CN_REPO/04-Evidence/Phase2/classroom-flow-$(date +%Y%m%d-%H%M%S).pcap"
sudo tcpdump -i "$CN_IFACE" -nn -s 0 -w "$CN_PCAP" \
  "(port 53 and \
  (host $CN_PRIMARY_DNS_IP or host $CN_BACKUP_DNS_IP)) or \
  (tcp port 443 and (host $CN_EDGE_IP or host $CN_B_IP))"
```

Leave it running. In Terminal 2:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
curl -v --tls-max 1.2 --http1.1 --max-time 15 \
  https://app.team1.test/api/status
```

Return to Terminal 1, press Control+C to stop ONLY that capture, then:

```bash
open -a Wireshark "$CN_PCAP"
```

| Wireshark display filter | What to explain |
|---|---|
| dns | Query, resolver IP/port, answer and TTL |
| tcp.flags.syn == 1 | SYN and SYN-ACK; point to the following ACK as well |
| tls.handshake | ClientHello, ServerHello, certificate (TLS 1.2 capture) |
| tls.record.content_type == 23 | Encrypted application data |
| tcp.stream eq NUMBER | One connection; inspect its source/destination ports |

Read sequence and acknowledgement numbers in packet details. The relative
ACK counts bytes, not packets; SYN/FIN each consume a sequence number. Do not
claim the Wireshark SYN filter alone displays the third handshake ACK.

For a comparison, capture a default curl connection and observe TLS 1.3, whose
certificate is encrypted. For backend plain HTTP, capture on the edge's actual
LAN interface with a separate `tcp port 3001 or tcp port 3002` filter while a
remote client sends traffic. Do not claim the encrypted client-side capture
reveals the JSON without decryption keys.

The original Phase 1 pcap can be opened if a live capture is not requested:

```bash
open -a Wireshark "$CN_REPO/04-Evidence/G-Packet-Capture/G0_mac4_capture_taskG-flow-tls12-164445.pcap"
```

Label it historical; its IP addresses differ from today's deployment.

<!-- pagebreak -->

## 13. "Diagnose this fault" - Extension F

Do not blindly restart everything. Work through the first failing layer and
explain what each observation rules out. These are checks, not commands that
inject a fault:

```bash
networksetup -getdnsservers Wi-Fi
scutil --dns
ls -l /etc/resolver
dig @"$CN_PRIMARY_DNS_IP" app.team1.test +time=2 +tries=1
dig @"$CN_BACKUP_DNS_IP" app.team1.test +time=2 +tries=1
dscacheutil -q host -a name app.team1.test
nc -vz -G 3 "$CN_EDGE_IP" 443
curl -v --max-time 10 https://app.team1.test/api/status
```

Anshuman checks actual upstreams/processes and logs:

```bash
sudo "$CN_NGINX" -t
cat "$CN_BREW_PREFIX/etc/nginx/servers/team1.conf"
curl --max-time 5 "http://$CN_A_IP:3001/health"
curl --max-time 5 "http://$CN_B_IP:3002/health"
sudo tail -n 25 "$CN_BREW_PREFIX/var/log/nginx/error.log"
```

On each DNS host:

```bash
cd "$CN_DNS_DIR"
docker compose ps -a
docker compose logs --tail=25 dns
docker compose exec -T dns dig @127.0.0.1 app.team1.test +short
dig @"$(ipconfig getifaddr "$CN_IFACE")" app.team1.test +tcp +short
```

| Observation | Likely layer / next step |
|---|---|
| Wrong/unreachable DNS setting | Correct client DNS to both current hosts; flush |
| Direct resolvers disagree | Restore intended app/api record on BOTH hosts |
| Both direct DNS answers correct, system stale | Check cache and per-domain resolver overrides |
| Wrong destination IP but DNS succeeds | DNS record/cutover issue; verify intended edge |
| TCP refused | Wrong port or no listener; inspect lsof/process |
| TCP timeout | Host/path/firewall/drop; compare actual port from relevant source |
| TLS certificate error | Trust chain, requested name, dates, clock; do not use -k |
| HTTP 502/504 | Check backend processes, NEW upstream IPs and edge-source PF allowance |
| Only B appears | Check A availability, failure exclusion and recent nginx logs |
| Internal DNS works, host UDP fails | Docker forwarding path; compare host TCP and remote-client tests |

To separate DNS from a known edge's TLS/application path:

```bash
curl -v --resolve "app.team1.test:443:$CN_EDGE_IP" \
  https://app.team1.test/api/status
```

Label this a DNS-bypass diagnostic, not proof DNS is fixed. If asked to show a
wrong-port failure, use `curl -v --connect-timeout 3 --max-time 5
https://app.team1.test:8443/api/status` as one command and compare to 443.
Record the actual faculty fault, diagnosis, correction and retest after it occurs.

If sir asks for the original helper, run
`bash "$CN_REPO/03-Source-Code/common/diagnose.sh"`. It was written for Phase 1:
it knows one DNS/edge, treats standby resolution as a wrong address and treats
blocked direct backend access as a failure. Explain those assumptions during
isolation/cutover instead of treating every printed FAIL as an unexpected outage.

<!-- pagebreak -->

## 14. "Repeat the Phase 1 failure cases"

Only inject a fault when requested, on the named test client. Have the restore
commands ready first. These examples intentionally interrupt the relevant path.

### Wrong DNS server - Bineet is the test client

```bash
sudo networksetup -setdnsservers Wi-Fi 10.255.255.254
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
dig +time=2 +tries=1 app.team1.test
ping -c 2 "$CN_EDGE_IP"
curl --max-time 8 https://app.team1.test/api/status
```

Expected: name resolution fails while direct IP connectivity may still work.
Restore immediately on Bineet:

```bash
sudo networksetup -setdnsservers Wi-Fi "$CN_PRIMARY_DNS_IP" "$CN_BACKUP_DNS_IP"
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### Correct DNS response, wrong destination

To isolate the experiment, Bineet temporarily lists ONLY primary DNS. On
Anshuman, in docker-dns, deliberately point app/api to Backend A's host:

```bash
cd "$CN_DNS_DIR"
sh set-edge-record.sh "$CN_A_IP"
dig @"$CN_PRIMARY_DNS_IP" app.team1.test +noall +answer
```

Bineet flushes and calls the HTTPS name. DNS succeeds but the address is not the
intended edge. Connection refusal is expected if A has no service on 443; another
service on that port could produce a TLS/HTTP error instead. Explain the actual
observation rather than assuming one specific error.

Restore on Anshuman: `sh set-edge-record.sh "$CN_EDGE_IP"`. Bineet restores both
resolver IPs and flushes with the commands above. Check both DNS answers agree.

### Both backends stopped

Bineet and Vridhi press Control+C in their Python-server Terminals. Leave DNS
and nginx running. From a client:

```bash
dig @"$CN_PRIMARY_DNS_IP" app.team1.test +short
curl -v --max-time 10 https://app.team1.test/api/status
```

Expected: DNS and TLS can succeed, then nginx returns 502 because it has no
reachable backend. Restore A on Bineet and B on Vridhi using the startup commands
in CLASSROOM-RESTART.md; repeat the load-balancing test after recovery.

### Wrong port

```bash
nc -vz -G 3 "$CN_EDGE_IP" 443
curl -v --connect-timeout 3 --max-time 5 \
  https://app.team1.test:8443/api/status
```

Our normal service uses 443, not 8443. Failure on 8443 demonstrates the port
distinction; it does not mean the normal HTTPS service is down. There is no
server-side change to roll back for this client-only request.

## 15. Final cleanup

Restore primary DNS, both backends, original app/api records and both client
resolver addresses. Clear only project PF rules and release that test's token.
Stop standby only after clients return to original edge; restore Supportdesk
if paused. If ending the whole project, restore each Mac's recorded original
DNS list; use `sudo networksetup -setdnsservers Wi-Fi Empty` only for original DHCP.
Keep evidence and private keys separate. Never commit tls.pem, .key or .p12 files.
