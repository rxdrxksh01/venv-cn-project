# Phase 2 configuration bundle

Recorded after the 24-25 November 2026 demonstration. IPs are session-specific.

| Machine | IP | Normal services |
|---|---|---|
| Anshuman | 10.7.31.231 | Docker primary DNS :53 UDP/TCP; native nginx HTTPS :443 |
| Bineet | 10.7.1.112 | Python Backend A :3001 |
| Vridhi (hostname Pranshus-MacBook-Pro) | 10.7.2.240 | Docker backup DNS :53 UDP/TCP; Python Backend B :3002 |

Vridhi also hosted native standby nginx :443 temporarily. Its PID/log/certificate paths were under ~/cn-standby, isolated from the Homebrew default config. supportdesk_nginx was paused for the port conflict, then restored after standby stopped (user-confirmed).

- `nginx-primary.conf`: local installed edge config snapshot with current upstreams.
- `nginx-standby.conf`: equivalent standalone config from the demonstrated setup. Use -p ~/cn-standby/ -c nginx.conf. tls.pem is provisioned locally and is not included.
- `backend-a.pf` / `backend-b.pf`: equivalent scoped filter templates; labels added for readability. Demonstrated rules used the same addresses/ports without labels. Load only into the project anchor on the relevant backend Mac. Tests were followed by rollback; rules are not currently enabled by this bundle.
- `primary.env.example` / `backup.env.example`: sanitized DNS settings. Copy the appropriate file to .env, never overwrite another Mac's bind IP.
- Dockerfile, compose.yaml, entrypoint.sh and live-record helpers: a self-contained DNS recipe. Primary app/api normally resolve to 10.7.31.231; migration used 10.7.2.240 on both resolvers, then restored.
- team.env: the current native-script settings. MAC1_IP equals MAC2_IP because Anshuman combines DNS and edge roles.

Private keys, decrypted TLS PEM files and encrypted PKCS#12 transfers are intentionally excluded. Reuse the working trusted TLS identity through the documented encrypted transfer workflow. Do not serve private keys over the public-CA sharing HTTP server.

For executable steps, tests and rollback, use ../../03-Source-Code/docker-dns/README.md and ../../03-Source-Code/PHASE2-GUIDE.md. This folder is a submission snapshot; make live changes from the source-code folder.
