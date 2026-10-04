# Backend Launch Instructions (Task C)

Both backends run the same tiny REST API, `backend/server.py` (Python standard library only, nothing to install).
It takes two arguments: the backend identifier and the TCP port.

| Backend | Machine | IP | Command | Listens on |
|---|---|---|---|---|
| A | Mac 3 | 10.7.20.243 | `/usr/bin/python3 backend/server.py A 3001` | `0.0.0.0:3001` |
| B | Mac 4 | 10.7.8.144 | `./backend/start-backend.sh` (= `python3 backend/server.py B 3002`) | `0.0.0.0:3002` |

Run from inside the `cn-project` folder. Stop with **Ctrl+C**.

The backends bind to `0.0.0.0` (all interfaces), **not** `127.0.0.1`, so nginx on Mac 2 can reach them over the LAN.
Check with `lsof -nP -iTCP:3001 -sTCP:LISTEN` → `*:3001 (LISTEN)`.

## Endpoints

| Request | Response |
|---|---|
| `GET /` | Small HTML page showing which backend answered, the TCP peer (Mac 2) and `X-Forwarded-For` (the real client). `Cache-Control: no-store` |
| `GET /api/status` | JSON `{"backend": "A", "status": "ok", "host", "port", "tcp_peer", "x_forwarded_for", "host_header", "time"}`. `Cache-Control: no-store` |
| `GET /api/cached` | Cacheable JSON with `Cache-Control: public, max-age=60` and `ETag: "25c29d02c99e446f"`; answers `304 Not Modified` when the request carries `If-None-Match` with that ETag |
| `GET /health` | `ok` |
| every response | `X-Backend: A` or `X-Backend: B` |

`/api/cached` returns identical bytes on A and B, so both compute the same ETag — a conditional
request gets a 304 whichever backend the load balancer picks.

Direct test (from Mac 2):

```bash
curl -i http://10.7.20.243:3001/api/status     # → X-Backend: A
curl -i http://10.7.8.144:3002/api/status      # → X-Backend: B
```

## Note: managed Mac (Mac 3)

Mac 3 is an organisation-managed (MDM) laptop. Its security policy accepted TCP connections to the
Homebrew Python binary and then immediately tore them down (`OSError: [Errno 57] Socket is not connected`),
and the firewall could not be changed (`Firewall settings cannot be modified from command line on managed Mac computers`).
`nc -l 3001` (an Apple-signed tool) received connections normally, so the block was specific to the unsigned
interpreter. Running the same code with Apple's signed `/usr/bin/python3` (3.9.6) worked. `start-backend.sh`
now prefers `/usr/bin/python3` automatically.
