#!/usr/bin/env python3
"""
Tiny REST backend for the CN project (Task C). Standard library only, nothing to install.

  Mac 3:  python3 backend/server.py A 3001
  Mac 4:  python3 backend/server.py B 3002

Endpoints
  GET /             small HTML page saying which backend answered
  GET /api/status   JSON {"backend": "A", "status": "ok", ...}
  GET /api/cached   cacheable JSON: Cache-Control max-age=60 + ETag, answers 304 to If-None-Match
  GET /health       "ok" (for quick checks)
Every response carries the header  X-Backend: A  (or B).
"""
import hashlib
import json
import socket
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BACKEND = sys.argv[1] if len(sys.argv) > 1 else "A"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3001
LISTEN = "0.0.0.0"  # every interface — NOT 127.0.0.1, or other Macs can't reach us

# /api/cached returns the same bytes on A and B, so both compute the same ETag.
# That way a 304 works no matter which backend the load balancer picks.
CACHED_BODY = json.dumps({"message": "This response is cacheable", "version": 1}, indent=2).encode()
CACHED_ETAG = '"' + hashlib.sha1(CACHED_BODY).hexdigest()[:16] + '"'

COLOR = {"A": "#2563eb", "B": "#16a34a"}.get(BACKEND, "#9333ea")


class Handler(BaseHTTPRequestHandler):
    server_version = f"CN-Backend-{BACKEND}/1.0"

    def respond(self, code, body=b"", ctype="application/json", headers=None):
        self.send_response(code)
        self.send_header("X-Backend", BACKEND)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if code != 304:
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD" and code != 304:
            self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        no_store = {"Cache-Control": "no-store"}  # so load balancing is visible on every refresh

        if path == "/":
            html = f"""<!doctype html><html><head><meta charset="utf-8"><title>Backend {BACKEND}</title></head>
<body style="font-family:-apple-system,sans-serif;display:grid;place-items:center;height:90vh;margin:0">
<div style="text-align:center"><div style="font-size:120px;font-weight:700;color:{COLOR}">{BACKEND}</div>
<p>Served by <b>Backend {BACKEND}</b> on {socket.gethostname()} port {PORT}</p>
<p>TCP peer (who connected to me): {self.client_address[0]}<br>
Original client (X-Forwarded-For): {self.headers.get("X-Forwarded-For", "-")}</p>
<p style="color:#666">{datetime.now():%H:%M:%S} — refresh to see load balancing</p></div></body></html>"""
            self.respond(200, html.encode(), "text/html; charset=utf-8", no_store)

        elif path == "/api/status":
            body = {
                "backend": BACKEND,
                "status": "ok",
                "host": socket.gethostname(),
                "port": PORT,
                "tcp_peer": f"{self.client_address[0]}:{self.client_address[1]}",
                "x_forwarded_for": self.headers.get("X-Forwarded-For"),
                "host_header": self.headers.get("Host"),
                "time": datetime.now().isoformat(timespec="seconds"),
            }
            self.respond(200, json.dumps(body, indent=2).encode(), headers=no_store)

        elif path == "/api/cached":
            cache = {"Cache-Control": "public, max-age=60", "ETag": CACHED_ETAG}
            if self.headers.get("If-None-Match") == CACHED_ETAG:
                self.respond(304, headers=cache)  # "you already have it" — no body sent
            else:
                self.respond(200, CACHED_BODY, headers=cache)

        elif path == "/health":
            self.respond(200, b"ok\n", "text/plain", no_store)

        else:
            self.respond(404, json.dumps({"error": "not found", "backend": BACKEND}).encode())

    do_HEAD = do_GET

    def log_message(self, fmt, *args):
        print(f"[{datetime.now():%H:%M:%S}] backend {BACKEND} <- {self.client_address[0]}  {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"Backend {BACKEND} listening on http://{LISTEN}:{PORT}  (Ctrl+C to stop)", flush=True)
    ThreadingHTTPServer((LISTEN, PORT), Handler).serve_forever()
