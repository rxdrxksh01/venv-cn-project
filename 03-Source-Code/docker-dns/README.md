# Docker replacement for Rudraksh's DNS

This runs **DNS only**. Keep the Phase 1 nginx and Python backends on the Macs.
Read [the Phase 2 guide](../PHASE2-GUIDE.md) for the whole project and remaining tasks.

## Where to run it

| Available Mac | Services |
|---|---|
| Anshuman (old Mac 2) | Existing nginx edge + primary Docker DNS |
| Bineet (old Mac 3) | Existing Backend A :3001 |
| Vridhi (old Mac 4) | Existing Backend B :3002 + backup Docker DNS + test client |

For the backup, copy **this whole folder** to Vridhi's Mac. Each Mac runs its own
Compose project. Docker Desktop must work on both. If Docker cannot be installed
on a second Mac, a native dnsmasq there can provide backup DNS with matching records.
Do not put both DNS instances on one laptop and describe that as machine failover.

Containers run inside Docker Desktop's Linux VM. Other Macs address the **host
Mac's Wi-Fi IP**, not the container's internal 172.x address. Published ports forward
both UDP 53 and TCP 53 into dnsmasq. This container does not get Rudraksh's old IP.

## Start primary DNS

From the repo root:

```bash
cd 03-Source-Code/docker-dns
cp .env.example .env
ipconfig getifaddr en0
open -a Docker
```

Edit `.env` in your editor. The example IPs are placeholders:

* `DNS_BIND_IP`: the LAN IP of **this** Mac.
* `EDGE_IP`: Anshuman's current LAN IP (the nginx edge).
* `DNS_PORT=53`: leave this at 53 for real clients.
* `DNS_TTL=30`: makes the TTL visible and the cutover test short.
* `UPSTREAM_DNS`: a reachable external resolver, preferably the Wi-Fi's original DNS.
  Get it with `scutil --dns` before changing client settings. Do not use either
  project DNS server as upstream; avoid forwarding loops.

Then:

```bash
docker version                         # must show BOTH Client and Server
docker compose config                  # check the rendered IP and port settings
docker compose up -d --build --wait
docker compose ps
docker compose logs --tail=20 dns
```

From a **different Mac**, replace the sample address with the primary host's real IP:

```bash
dig @192.168.50.10 app.team1.test +noall +answer
dig @192.168.50.10 api.team1.test +tcp +noall +answer
```

Both must return the edge IP, TTL 30. Local tests alone do not establish LAN reachability.
If it fails, check the host IP, Docker Local Network permission, macOS firewall
permission for Docker, shared Wi-Fi reachability, and whether another service owns
port 53 (`sudo lsof -nP -iUDP:53 -iTCP:53`). Allow the required app/traffic rather
than disabling the entire firewall. No host networking or privileged container is needed.

The primary host runs nginx :443 and DNS :53 simultaneously; these ports do not conflict.

## Start backup DNS

On Vridhi's Mac repeat the steps, with **her** IP as `DNS_BIND_IP` and **Anshuman's**
IP still as `EDGE_IP`. `DNS_TTL` and project records must match the primary.
Check both resolvers directly before changing any client DNS settings.

## Configure clients and prove backup failover (Extension A)

The following example assumes primary `192.168.50.10`, backup `192.168.50.12`;
replace both with real IPs. Run on client Macs (including the Docker hosts if used
as clients). Save each Mac's original DNS setting **before** changing it:

```bash
mkdir -p ../evidence/phase2
networksetup -getdnsservers Wi-Fi > ../evidence/phase2/original-dns.txt
sudo networksetup -setdnsservers Wi-Fi 192.168.50.10 192.168.50.12
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
networksetup -getdnsservers Wi-Fi
dscacheutil -q host -a name app.team1.test
curl -v --max-time 15 https://app.team1.test/api/status
```

On the primary DNS host, in this folder:

```bash
docker compose stop dns
```

On a client flush cache again and repeat `dscacheutil` and `curl`. Also show a new
query in the **backup's** `docker compose logs --since=1m dns`. This proves the
backup handled a lookup rather than the client merely reusing a cached answer.
macOS resolver selection is adaptive: a DNS list is not a guaranteed strict
primary-then-backup sequence, and failure detection may take time. Record the
observed delay. `dig @backup` proves that server answers, not automatic OS failover.

Restore on the primary:

```bash
docker compose start dns
```

## TTL demo (Extension B)

`dig @server` directly asks that server; it does **not** show the macOS host cache.
Keep a terminal open with DNS logs to distinguish fresh queries from cached answers.

1. Both resolvers initially answer `ttl-demo.team1.test` with the edge IP and TTL 30.
2. On a client flush cache, then run `dscacheutil -q host -a name ttl-demo.team1.test`.
3. On **both DNS hosts**, run `sh set-ttl-record.sh NEW_IP` with another available
   Mac's IP. This reloads a hosts file with SIGHUP without restarting the container.
   It requires the updated image built with `docker compose up -d --build --wait`.
   Do not flush the client during this part of the experiment.
4. Direct `dig @primary ttl-demo.team1.test +noall +answer` and `dig @backup ...`
   should show the new answer. Repeated client `dscacheutil` lookups may still show
   the old cached answer until expiry, then the new one. Timestamp observations.
   The TTL counts from the client's original lookup, not the configuration change.
5. For a separate manual-flush experiment, prime the client cache again, change the
   record on both servers, then flush with the two sudo commands above. The next
   client lookup should get the changed value immediately.
6. Run `sh set-ttl-record.sh ORIGINAL_IP` on both hosts to restore. These runtime
   changes last until restart; `.env` sets the record's startup value. If a test
   client temporarily uses only the primary to isolate caching, make the change
   there only, then restore the client's two DNS addresses after the test.

For real edge cutover (Extension E), after rebuilding the updated DNS image on
both Macs, run `sh set-edge-record.sh STANDBY_IP` on **both DNS hosts**. This
updates app/api together without restarting DNS. Use the original edge IP to
roll back. The override lasts until restart, when `.env` EDGE_IP is restored.
The stable infrastructure name edge.team1.test is used by the healthcheck and
is not changed by this helper. Build and verify UDP/TCP reachability before the
timed cutover. If Docker's host UDP forwarding becomes stale after recreation,
investigate that separately before collecting timed evidence; restarting Docker
Desktop affects all containers on that Mac and may restart other applications.

Use `app.team1.test` for the real edge cutover (Extension E) in the Phase 2 guide.
Do not claim this DNS-only test demonstrates HTTPS migration. Client caching is
OS/application dependent; if the cache does not retain the answer, show the logs
and investigate instead of inventing a successful TTL delay.

## Changes, stop, rollback, and offline preparation

After **any `.env` change**, use `docker compose up -d --force-recreate --wait`.
`docker compose restart` alone does not apply changed environment variables.

```bash
docker compose logs -f dns             # Ctrl+C stops viewing, not the server
docker compose down                    # removes this DNS container and network
```

Restore client DNS to exactly what `original-dns.txt` recorded. If it said there
were no manually configured DNS servers, restore DHCP DNS using:

```bash
sudo networksetup -setdnsservers Wi-Fi Empty
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

If it listed static addresses, use `networksetup -setdnsservers Wi-Fi` followed by
those original addresses instead. Remove a project-specific `/etc/resolver/team1.test`
only if you created it for this demo (back up any pre-existing file first).

Build on both Macs tonight so tomorrow's startup needs no download. Or transfer
the image to another Apple Silicon Mac:

```bash
docker save cn-team1-dns:local -o /tmp/cn-team1-dns.tar
# Transfer this tar and the folder, then on the destination:
docker load -i /path/to/cn-team1-dns.tar
docker compose up -d --no-build --wait
```

An arm64 image cannot be assumed to work natively on an Intel Mac; build there
ahead of time. Keep laptops awake and connected to power throughout evaluation.

## Local validation performed on 24 November 2026

Built the image on this Apple Silicon Mac and started Compose bound to loopback
port 15353 with test addresses. Verified UDP app lookup, TCP api lookup, TTL 30,
NXDOMAIN for an unknown project name, healthy container state, a recreated
configuration changing only ttl-demo's address, and rejection of invalid IP/TTL
inputs. Removed the test container/network afterward; the built image remains.

These checks do not validate another Mac's LAN access, actual macOS dual-resolver
failover, client TTL expiry, firewall isolation or standby-edge migration. Those
need the team's real deployment and fresh evaluation evidence.

Official references: [Docker Desktop networking](https://docs.docker.com/desktop/features/networking/),
[port publishing](https://docs.docker.com/engine/network/port-publishing/),
[dnsmasq manual](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html).
