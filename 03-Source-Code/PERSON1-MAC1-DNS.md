# Person 1 — Mac 1: Primary DNS server + test client + coordinator

**Your job:** run the team's private DNS server (dnsmasq). It answers `app.team1.test` and
`api.team1.test` with Mac 2's IP. You are also a test client, and you hand the folder to everyone.

> **Your own internet is not affected.** We don't change your Mac's DNS setting. The only change is
> one file, `/etc/resolver/team1.test`, which sends **only** `*.team1.test` names to dnsmasq.
> Every other website uses your normal DNS. Other names that Macs 2/3/4 ask you about are forwarded
> to your Wi-Fi's normal DNS, so their internet keeps working while your Mac and dnsmasq are on.

## 0. Coordinator: collect IPs and send the folder

1. Join the shared Wi-Fi and get your IP: `ipconfig getifaddr en0`
2. Collect the other 3 IPs from the group, then edit `team.env` (in TextEdit, or `nano team.env`) and replace each `CHANGE_ME`.
3. Zip it and send it to everyone (AirDrop / WhatsApp / Drive):
   ```bash
   cd ~/Desktop/ready
   zip -r cn-project.zip cn-project -x "*.DS_Store" "cn-project/evidence/*"
   ```

## 1. Task A: network info + ping

```bash
cd ~/Desktop/ready/cn-project
./common/netinfo.sh       # your IP, mask, gateway, interface, MAC → evidence/
./common/ping-all.sh      # ping Mac 2, 3, 4 → evidence/
```

## 2. Task B: start the DNS server

```bash
./dns/setup-dns.sh
```
What it does (be ready to explain):
- `brew install dnsmasq`
- writes `/opt/homebrew/etc/dnsmasq.conf`. Open it and read it; it's short. Key lines:
  - `host-record=app.team1.test,<Mac2 IP>` and `host-record=api.team1.test,<Mac2 IP>`: our A records
  - `local=/team1.test/`: we are the authority for this zone, never forward it
  - `resolv-file=/etc/resolv.conf` + `server=8.8.8.8`: everything else is forwarded to your Wi-Fi's normal DNS (or 8.8.8.8)
  - `local-ttl=30`: clients may cache our answers for 30 s
  - `log-queries`: every lookup is logged
- `sudo brew services restart dnsmasq`: runs it as root, because port 53 is a privileged port
- creates `/etc/resolver/team1.test` (only on Mac 1)

Check it:
```bash
dig @127.0.0.1 app.team1.test          # ANSWER SECTION → Mac 2's IP, TTL 30
dig @<your Mac1 IP> api.team1.test     # same, over your LAN address
scutil --dns | grep -B1 -A3 team1      # shows macOS routes *.team1.test to 127.0.0.1
tail -f /opt/homebrew/var/log/dnsmasq.log   # watch queries arrive from Mac 2/3/4 (Ctrl+C to stop)
```
> On Mac 1, plain `dig app.team1.test` (without `@`) asks your normal DNS, not dnsmasq, because dig
> ignores `/etc/resolver`. Use `dig @127.0.0.1`, or run the dig demo from **Mac 4**.
> Browsers and curl on your Mac do use `/etc/resolver`, so `https://app.team1.test` works.

Commands you'll use later:
```bash
sudo brew services list                # is dnsmasq running?
sudo brew services restart dnsmasq     # after editing dnsmasq.conf by hand
./dns/point-record.sh app <MAC3_IP>    # failure demo 2: record points to the wrong IP
./dns/point-record.sh app <MAC2_IP>    # ...and put it back
```

## 3. Task E: trust the team certificate (client role)

When Person 2 says "share-ca is running":
```bash
./common/trust-ca.sh
```
Compare the SHA-256 fingerprint it prints with the one on Mac 2's screen.

## 4. Test as a client

Once Mac 2 nginx and both backends are up:
```bash
curl -i https://app.team1.test/api/status     # no -k! Look for X-Backend
./common/lb-test.sh                           # A, B, A, B ...
./common/cache-test.sh                        # Cache-Control + 304
open https://app.team1.test                   # browser: big "A" or "B", no warning
```

## 5. Your part in the failure demos
- **Failure 2 (wrong IP):** you run `./dns/point-record.sh app <MAC3_IP>`, then put it back. See [DEMO-AND-FAILURES.md](DEMO-AND-FAILURES.md).
- **If DNS is broken during the review:** check `sudo brew services list`, then `dig @127.0.0.1 app.team1.test`,
  then the records in `/opt/homebrew/etc/dnsmasq.conf`.
