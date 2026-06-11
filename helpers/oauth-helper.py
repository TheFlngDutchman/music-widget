#!/usr/bin/env python3
"""One-shot helper for the Spotify PKCE flow.

QML has no SHA-256, no secure RNG, and no TCP listener, so this helper:
  1. preflights the redirect port,
  2. generates the PKCE verifier/challenge pair,
  3. listens for exactly one request to /login and captures ?code=.

Protocol: one JSON object per stdout line.
  {"event": "ready", "verifier": ..., "challenge": ...}   listener is up
  {"event": "code", "code": ...}                          auth code captured
  {"event": "error", "kind": ..., "message": ...}         terminal failure
Exits 0 after "code", non-zero after "error". The QML side builds the
authorize URL (it owns the client id and scopes) and opens the browser.
"""

import base64
import hashlib
import json
import secrets
import socket
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

TIMEOUT_SECS = 300

LANDING = b"""<!doctype html>
<html><head><meta charset="utf-8"><title>Music Widget</title></head>
<body style="background:#111;color:#eee;font-family:monospace;text-align:center;padding-top:18vh">
<h2>%s</h2><p>You can close this tab and return to the widget.</p>
</body></html>"""


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main():
    port = 19872
    for i, arg in enumerate(sys.argv):
        if arg == "--port" and i + 1 < len(sys.argv):
            port = int(sys.argv[i + 1])

    # Preflight: a stale listener here is the classic silent-hang cause.
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(("127.0.0.1", port))
        probe.close()
    except OSError as e:
        emit({"event": "error", "kind": "port-busy",
              "message": f"Port {port} is already in use ({e}). "
                         f"Close the program using it or change spotify.redirectPort in config.json."})
        return 1

    verifier = base64.urlsafe_b64encode(secrets.token_bytes(64)).rstrip(b"=").decode()
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()

    result = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            url = urlparse(self.path)
            if url.path != "/login":
                self.send_response(404)
                self.end_headers()
                return
            qs = parse_qs(url.query)
            if "code" in qs:
                result["code"] = qs["code"][0]
                msg = b"Connected"
            else:
                result["error"] = qs.get("error", ["unknown"])[0]
                msg = b"Authorization failed"
            body = LANDING % msg
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    server = HTTPServer(("127.0.0.1", port), Handler)
    server.timeout = TIMEOUT_SECS
    emit({"event": "ready", "verifier": verifier, "challenge": challenge})

    while "code" not in result and "error" not in result:
        # handle_request honors server.timeout (returns on each request)
        before = dict(result)
        server.handle_request()
        if before == result and "code" not in result and "error" not in result:
            emit({"event": "error", "kind": "timeout",
                  "message": "No browser redirect arrived within 5 minutes."})
            return 1

    server.server_close()
    if "code" in result:
        emit({"event": "code", "code": result["code"]})
        return 0
    emit({"event": "error", "kind": "denied",
          "message": f"Spotify returned: {result['error']}"})
    return 1


if __name__ == "__main__":
    sys.exit(main())
