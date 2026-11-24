# Team .venv - Viva study guide
## Learn the explanation, then use the command sheet to prove it

### Our 30-second project explanation

We built a private network service. A client resolves app.team1.test through our
own DNS, connects securely to an nginx edge, and receives a response from one
of two Python backends. Phase 2 added a backup DNS, cache/TTL experiments,
backend access restrictions, backend recovery and a manual migration to a
standby edge. Packet captures, headers, logs and controlled failures explain
which layer is working. Docker replaces the missing DNS host; our application
backends and nginx remain native Mac processes.

| Role | Member / physical Mac |
|---|---|
| Primary DNS + original edge | Anshuman |
| Backend A + client | Bineet |
| Backup DNS + Backend B + temporary standby | Vridhi; hostname shows Pranshu |

### Q1. What is the full request journey?

DNS finds the edge IP. The client establishes TCP, performs TLS, then sends HTTP
inside the encrypted connection. nginx decrypts, opens a separate HTTP connection
to A/B, receives a response, and encrypts the response back to the client.

### Q2. Does DNS forward our web request?

No. It returns an address. The client makes a separate connection to that address.
That is why correct DNS can coexist with a failed website.

### Q3. Why two backends?

They demonstrate load distribution and continued service when one backend fails.
Both run the same simple code, with different A/B identifiers.

### Q4. What did YOU do? Answer for your actual role.

Anshuman: nginx/TLS/load balancing and primary Docker DNS. Bineet: Backend A and
client/failure tests. Vridhi: Backend B, backup Docker DNS and standby edge. Then
explain a component outside your own role; the viva expects whole-system knowledge.

### Q5. What proves the setup works?

DNS answers, verified TLS, HTTP 200, A/B headers, upstream/edge logs, packet
captures, and successful fault/recovery tests. A screenshot saying healthy alone
does not establish the whole network path.

<!-- pagebreak -->

## DNS and changing networks

### Q6. Why .test rather than .local?

.test is reserved for testing. .local is used by multicast DNS/Bonjour on Macs
and can conflict with ordinary private DNS resolution.

### Q7. What records do we use?

IPv4 A records for app/api pointing to the selected nginx edge. ttl-demo is a
separate experimental name. AAAA would contain IPv6, which we did not configure.

### Q8. Is dnsmasq doing internet-wide recursive resolution itself?

It serves our local records and caches/forwards other queries to an upstream
resolver. Our private app does not require a cloud-hosted DNS service.

### Q9. Why UDP 53? Can DNS use TCP?

Small DNS exchanges commonly use UDP to avoid connection setup. DNS also uses
TCP 53, for example after a truncated UDP response and for zone transfers. We
publish and test both protocols.

### Q10. What is TTL?

Time to live: how long an answer may be cached before a fresh lookup is needed.
Our advertised local TTL was 30 seconds. Client sampling showed the actual
observed transition; we do not claim an exact 30-second switch.

### Q11. Does dig prove the Mac's DNS cache is being used?

Not when asking a server directly with @IP. That shows the server answer.
dscacheutil/system application lookups and query logs help inspect host behavior.

### Q12. What did backup DNS prove?

After primary DNS stopped and the client cache was flushed, a system lookup
still succeeded and the backup logged the query. Backup DNS protects resolution;
it does not fix a failed edge or application.

### Q13. Does listing two DNS servers mean strict primary-then-backup ordering?

Do not assume that. macOS resolver selection is adaptive. Demonstrate resolution
with primary stopped and correlate the new query on backup.

### Q14. Why did the backup log show 172.x instead of Bineet's IP?

Docker forwarding can expose a Docker-side gateway address to the container.
That differs from the app's X-Forwarded-For header, which nginx sets at HTTP level.

### Q15. Will reconnecting change our IPs or certificates?

DHCP may change the IPs, so check them. Update bind IPs, records, upstreams,
client resolvers and PF templates. The existing certificate still matches the
same domain name; an IP change alone does not require a new certificate.

<!-- pagebreak -->

## TCP, IP and protocol layers

### Q16. Which protocols belong to which layers?

| Protocol | TCP/IP role |
|---|---|
| DNS, HTTP | Application |
| TLS | Security above TCP; commonly discussed as OSI presentation/session functions |
| TCP, UDP | Transport |
| IP, ICMP | Internet/network |
| Wi-Fi/Ethernet, ARP | Link and local address resolution |

TLS does not occupy its own formal TCP/IP layer. The OSI mapping is conceptual.

### Q17. Explain the TCP handshake.

Client sends SYN; server replies SYN-ACK; client sends ACK. They establish
connection state and synchronize sequence numbers before TLS/application data.

### Q18. What is a socket pair / TCP connection identifier?

Client IP plus ephemeral source port, and server IP plus destination port,
with TCP as the transport. Ports identify services/connections within a host;
the IP identifies the network endpoint.

### Q19. Why does the client source port keep changing?

The OS chooses an ephemeral port for new connections. The server listens on
a known port such as 443. Different connections may use different source ports.

### Q20. How does TCP provide reliability?

Sequence numbers order bytes; acknowledgements report progress; missing data
is retransmitted. TCP delivers an ordered byte stream, not application messages.

### Q21. What does an ACK number mean?

The next byte expected, cumulatively acknowledging earlier bytes. SYN and FIN
each consume one sequence number even though they are not application payload.

### Q22. Flow control versus congestion control?

Flow control protects the receiver using its advertised receive window.
Congestion control adjusts sending to network conditions to avoid overloading
the path. They solve different problems.

### Q23. Why does ping work while HTTPS fails?

Ping tests ICMP reachability, not TCP 443, TLS trust or application health.
A firewall may also block ping while allowing HTTPS. Test the relevant port.

### Q24. Subnet mask, gateway, MAC and ARP?

The mask/prefix helps decide whether a destination is on-link; the gateway
handles off-link traffic. ARP maps a local IPv4 next-hop address to a link-layer
MAC address. A MAC address is not a TCP port or a DNS name.

### Q25. Does same Wi-Fi name guarantee reachability?

No. There can be client isolation, different VLANs/subnets or host restrictions.
Check actual addresses, routes and service ports. Do not assume all campus
devices share one unfiltered broadcast domain.

<!-- pagebreak -->

## TLS, HTTP and caching

### Q26. Why TLS? What does it provide?

Encryption, integrity and server authentication when the certificate is
validated. It does not automatically make the application bug-free or available.

### Q27. What does the client validate in the certificate?

Trusted issuer/chain, requested name in the subject alternative name, validity
dates and appropriate certificate usage. Our client explicitly trusts a local CA.

### Q28. CA certificate versus server certificate versus private key?

The public CA certificate anchors trust. The server certificate identifies the
website. The server private key proves possession during TLS; the CA private
key can issue certificates. Public certificates can be shared; keys stay protected.

### Q29. Where does TLS end in our design?

At nginx. Client-to-edge is encrypted; edge-to-backend is plain HTTP. The backend
sees nginx as its TCP peer and gets the original client via X-Forwarded-For.

### Q30. Why force TLS 1.2 in the packet demonstration?

Its server certificate is visible in the handshake without decryption. In TLS
1.3 the certificate is encrypted after ServerHello. TLS 1.3 compatibility
ChangeCipherSpec records are not the core key-establishment mechanism.

### Q31. Why is curl -k unacceptable as proof?

It disables certificate verification. An encrypted connection with verification
bypassed does not demonstrate trusted server identity. --cacert still verifies.

### Q32. What does --resolve do?

It supplies a chosen IP for a domain/port while preserving the name and TLS
checks. It is useful for testing standby before cutover, but bypasses DNS and
therefore cannot prove DNS-based migration by itself.

### Q33. HTTP/1.1 versus HTTP/2 versus HTTP/3?

HTTP/2 multiplexes streams and compresses headers over one TCP connection;
HTTP/3 uses QUIC over UDP. Our nginx accepts HTTP/1.1 and HTTP/2; HTTP/3 is
explanation-only. The nginx-to-Python hop is separate from the client protocol.

### Q34. Cache-Control, ETag and 304?

max-age controls freshness. ETag identifies a representation; If-None-Match
asks whether it changed. A 304 has no representation body, so the client reuses
its copy. A fresh cache hit can avoid a request entirely. curl does not cache
responses automatically; our script sends the conditional header explicitly.

### Q35. Why identical cached content on A/B, and no-store on status?

Identical bytes give the same ETag, so validation works whichever backend is
selected. no-store makes each status request reach the service so load balancing
is observable. DNS TTL and HTTP freshness cache different things.

<!-- pagebreak -->

## Resilience, firewall and Docker

### Q36. Reverse proxy versus load balancer?

A reverse proxy receives client traffic on behalf of servers. A load balancer
selects among servers. Our nginx performs both roles and terminates TLS.

### Q37. Which balancing strategy and health detection do we use?

Default round robin with passive failure detection. max_fails=1 and
fail_timeout=10s temporarily exclude a failed target; proxy_next_upstream retries
eligible failures. nginx is not actively polling our /health endpoint.

### Q38. What happens if one or both backends stop?

With one stopped, nginx retries/uses the survivor. With both stopped, DNS and
TLS may still work while nginx returns 502. This separates edge and backend health.

### Q39. When does A return after restart?

After the failure exclusion interval, later traffic can try it again. It returns
to rotation if it answers. Recovery is driven by traffic, not just a timer probe.

### Q40. What remains a single point of failure?

The normal nginx edge on Anshuman's Mac. A whole-host failure also removes its
primary DNS. A backup resolver alone does not remove the edge dependency.

### Q41. Was our edge migration automatic failover?

No. We manually changed app/api on both resolvers and kept both edges up.
Automatic failover would also need failure detection and a supported steering
mechanism; our demo does not claim to implement that.

### Q42. What did PF isolation enforce?

Only the original edge's IPv4 source could reach each backend port remotely.
A client was denied directly but succeeded through nginx. Each backend was
tested separately and then rolled back. A standby requires a policy exception
or rollback before it can reach the same backend pool.

### Q43. Why use an anchor and PF enable token?

The anchor scopes our rules instead of replacing the main ruleset. -E acquires
an enable reference; -X releases that test's token. We clear only our anchor,
not all rules or every other component's PF enablement.

### Q44. Container, image and Compose?

An image is the packaged filesystem/software. A container is a running instance.
Compose describes its ports, environment and healthcheck. On our Macs Docker
Desktop runs Linux containers through a Linux VM; it is not a new physical laptop.

### Q45. EXPOSE versus published ports? Why both UDP/TCP 53?

EXPOSE documents container ports; it does not publish them to the LAN. Compose
ports bind the host LAN address and forward into the container. UDP and TCP are
separate protocols and both are needed for our DNS demonstration.

<!-- pagebreak -->

## Questions tied to OUR code and observed problems

### Q46. Does a healthy DNS container prove clients can resolve?

No. The healthcheck queries inside the container. Host forwarding, firewall and
LAN access can still fail. We saw internal/TCP DNS work while host UDP failed.
Test from a different Mac and compare both transports.

### Q47. Why did Vridhi's host fail DNS while its DNS container worked?

Hosting the service did not configure the Mac's resolver. Setting both team DNS
addresses and flushing the host cache fixed curl's name-resolution error.

### Q48. Why does changing .env need recreation?

It supplies environment and port bindings at container creation. restart alone
does not replace that configuration. Our live helpers reload hosts files without
restarting DNS; their overrides disappear on restart, restoring .env baseline.

### Q49. What do the response headers and JSON prove?

X-Edge identifies nginx; X-Backend identifies A/B; X-Upstream-Addr shows targets
attempted. tcp_peer is the actual connected peer; X-Forwarded-For carries client
information at HTTP level. That header is not cryptographic identity by itself.

### Q50. Is our nginx a working content cache/CDN?

It is an edge/reverse proxy, but our config does not enable proxy_cache. We
demonstrated client cache headers and conditional 304. A real CDN distributes
edge services geographically; our local setup illustrates selected concepts.

### Q51. Which versions/ports does the Python app use?

A listens on 0.0.0.0:3001 and B on 0.0.0.0:3002. nginx sends HTTP/1.1 upstream
requests, while the standard BaseHTTPRequestHandler defaults to HTTP/1.0 response
status lines unless overridden. Client-side HTTP/2 is provided by nginx, not Python.

### Q52. Why 0.0.0.0 rather than 127.0.0.1? Is that a firewall?

0.0.0.0 listens on available IPv4 interfaces; 127.0.0.1 is local-only. Listening
on the LAN does not restrict callers. PF supplies the source-IP restriction.

### Q53. How do these roles relate to cloud/email concepts?

Private DNS resembles a private hosted zone; nginx resembles an HTTPS load
balancer; backends resemble application instances. No cloud hosts the running
project. SMTP sends mail, IMAP/POP retrieve it, and MX records identify mail
servers; email implementation is not part of this project.

### If sir injects a fault: say your reasoning out loud

I will compare the configured resolvers and their answers, then the resolved
IP's TCP port, then TLS verification, then HTTP/upstream behavior. I will fix
or isolate the first failing layer and retest. Correct DNS does not prove TCP;
correct TCP does not prove TLS; correct TLS does not prove backend availability.

### Be precise about what we demonstrated

Do not claim automatic edge failover, active /health polling, permanent PF rules,
an nginx response cache, exact 30-second observed expiry, or a completed faculty
challenge before it occurs. We have evidence for A-E and a read-only rehearsal;
the actual faculty fault and individual viva still happen during evaluation.
