#!/usr/bin/env python3
"""A stand-in for the Home Assistant Supervisor API, for testing only.

bashio reaches the Supervisor over plain HTTP at http://supervisor/ with a
bearer token, and the app's scripts use it for three things: the ingress
entry point, the mapped port, and the app options. Serving those three
answers is enough to boot the app outside Home Assistant.

Configured through the environment:
  INGRESS_ENTRY   ingress path prefix to hand out
  ADDON_OPTIONS   app options, as a JSON object
  PORT_8000       host port 8000 maps to, or "null" for an unmapped port
"""

from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INGRESS_ENTRY = os.getenv("INGRESS_ENTRY", "/api/hassio_ingress/testtoken")
OPTIONS = json.loads(os.getenv("ADDON_OPTIONS", "{}"))
PORT_8000 = json.loads(os.getenv("PORT_8000", "8000"))

ADDON_INFO = {
    "slug": "healthchecks",
    "name": "Healthchecks",
    "hostname": "local-healthchecks",
    "state": "started",
    "ingress": True,
    "ingress_entry": INGRESS_ENTRY,
    "ingress_port": 1337,
    "network": {"8000/tcp": PORT_8000},
    "network_description": {"8000/tcp": "Web interface and ping endpoint"},
    "options": OPTIONS,
}

SYSTEM_INFO = {
    "hostname": "homeassistant",
    "supervisor": "2026.08.0",
    "homeassistant": "2026.8.0",
    "arch": "amd64",
    "machine": "qemux86-64",
}

ROUTES = {
    "/supervisor/ping": {},
    "/info": SYSTEM_INFO,
    "/addons/self/info": ADDON_INFO,
    "/addons/self/options/config": OPTIONS,
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - name fixed by BaseHTTPRequestHandler
        path = self.path.split("?", 1)[0]
        if path in ROUTES:
            self._send(200, {"result": "ok", "data": ROUTES[path]})
        else:
            self._send(404, {"result": "error", "message": f"unknown {path}"})

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", 0))
        if length:
            self.rfile.read(length)
        self._send(200, {"result": "ok", "data": {}})

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("mock-supervisor: " + fmt % args + "\n")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 80), Handler).serve_forever()
