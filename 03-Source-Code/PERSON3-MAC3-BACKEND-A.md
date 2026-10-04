# Person 3 — Mac 3: Backend A (port 3001)

**Your job:** run Backend A, a tiny Python REST API (`backend/server.py`, standard library only,
nothing to install). nginx on Mac 2 forwards about half the requests to you.

```bash
cd ~/Downloads/cn-project        # wherever you unzipped it
chmod +x lib.sh */*.sh
cat team.env                     # IPs filled in?
python3 --version                # if macOS offers to install developer tools, accept
```

## 1. Task A

```bash
./common/netinfo.sh
./common/ping-all.sh
```

## 2. Task C: start Backend A

```bash
./backend/start-backend.sh       # = python3 backend/server.py A 3001
```
- If macOS asks **"Allow python3 to accept incoming network connections?"**, click **Allow**.
- Leave this Terminal window open. Each request is printed here, and you'll see they come from **Mac 2's IP**, not the client's.
- Stop = **Ctrl+C** (this is the "one backend stopped" failure demo). Start again = same command.

Check it from a **second Terminal** on your Mac, and ask someone to try from their Mac:
```bash
curl -i http://localhost:3001/api/status
curl -i http://<MAC3_IP>:3001/api/status     # from another Mac: must work (it's on 0.0.0.0, not 127.0.0.1)
lsof -nP -iTCP:3001 -sTCP:LISTEN             # shows *:3001, meaning listening on all interfaces
```

What the backend returns (be ready to explain):
| Endpoint | Response |
|---|---|
| `GET /` | HTML page with a big **A** (no-store, so every refresh hits the load balancer) |
| `GET /api/status` | `{"backend":"A","status":"ok", "tcp_peer": <Mac 2>, "x_forwarded_for": <real client>}` |
| `GET /api/cached` | `Cache-Control: public, max-age=60` + `ETag`. Answers **304** to `If-None-Match` |
| every response | header `X-Backend: A` |

Why `tcp_peer` is Mac 2 and not the client: nginx opens a **new** TCP connection to you. The
original client's IP only reaches you inside the `X-Forwarded-For` HTTP header.

## 3. Point your DNS at Mac 1 + trust the CA

```bash
./common/use-team-dns.sh primary
./common/trust-ca.sh              # while Person 2 runs share-ca.sh
curl -i https://app.team1.test/api/status
```

## 4. Your part in the failure demos
- **Failure 3:** press Ctrl+C on Backend A. Person 4 shows that requests still succeed via B. Then restart it.
- **Failure 4:** Ctrl+C at the same time as Person 4 → clients get **502 Bad Gateway**. Then restart.
