#!/usr/bin/env python3
"""A stand-in for the Home Assistant Supervisor, for testing only.

Two jobs, both on port 80:

  * The API. bashio reaches the Supervisor over plain HTTP at
    http://supervisor/ with a bearer token, and the app's scripts use it for
    three things: the ingress entry point, the mapped port, and the app
    options. Serving those three answers is enough to boot the app outside
    Home Assistant.

  * The ingress proxy. Requests under the ingress entry point are forwarded
    to the app with that prefix removed, which is what the real Supervisor
    does (supervisor/api/ingress.py rebuilds every request as
    http://<app>:<ingress_port>/<path>). Getting this wrong in the harness
    hides the one bug that breaks the sidebar panel, so it is modelled here
    rather than worked around in the test script.

Configured through the environment:
  INGRESS_ENTRY   ingress path prefix to hand out and to proxy
  ADDON_OPTIONS   app options, as a JSON object
  PORT_8000       host port 8000 maps to, or "null" for an unmapped port
  ADDON_HOST      host name of the app container
"""

from __future__ import annotations

import http.client
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INGRESS_ENTRY = os.getenv("INGRESS_ENTRY", "/api/hassio_ingress/testtoken")
OPTIONS = json.loads(os.getenv("ADDON_OPTIONS", "{}"))
PORT_8000 = json.loads(os.getenv("PORT_8000", "8000"))
ADDON_HOST = os.getenv("ADDON_HOST", "addon")
INGRESS_PORT = 1337

ADDON_INFO = {
    "slug": "healthchecks",
    "name": "Healthchecks",
    "hostname": "local-healthchecks",
    "state": "started",
    "ingress": True,
    "ingress_entry": INGRESS_ENTRY,
    "ingress_port": INGRESS_PORT,
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

# Hop-by-hop headers, plus the ones whose value depends on the body we rebuild.
SKIP_REQUEST_HEADERS = {"content-length", "transfer-encoding", "accept-encoding"}
SKIP_RESPONSE_HEADERS = {"content-length", "transfer-encoding", "connection"}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length else b""

    def _proxy(self, body: bytes) -> None:
        """Forward to the app with the ingress prefix stripped off the path."""
        path = self.path[len(INGRESS_ENTRY) :] or "/"

        headers = {
            name: value
            for name, value in self.headers.items()
            if name.lower() not in SKIP_REQUEST_HEADERS
        }
        if body:
            headers["Content-Length"] = str(len(body))

        conn = http.client.HTTPConnection(ADDON_HOST, INGRESS_PORT, timeout=60)
        try:
            conn.request(self.command, path, body=body or None, headers=headers)
            upstream = conn.getresponse()
            payload = upstream.read()

            self.send_response(upstream.status)
            for name, value in upstream.getheaders():
                if name.lower() not in SKIP_RESPONSE_HEADERS:
                    self.send_header(name, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        finally:
            conn.close()

    def _handle(self, body: bytes = b"") -> None:
        if self.path.startswith(INGRESS_ENTRY):
            self._proxy(body)
            return

        path = self.path.split("?", 1)[0]
        if self.command == "POST":
            self._send(200, {"result": "ok", "data": {}})
        elif path in ROUTES:
            self._send(200, {"result": "ok", "data": ROUTES[path]})
        else:
            self._send(404, {"result": "error", "message": f"unknown {path}"})

    def do_GET(self) -> None:  # noqa: N802 - name fixed by BaseHTTPRequestHandler
        self._handle()

    def do_POST(self) -> None:  # noqa: N802
        self._handle(self._read_body())

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("mock-supervisor: " + fmt % args + "\n")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 80), Handler).serve_forever()
