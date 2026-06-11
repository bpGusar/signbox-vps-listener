#!/usr/bin/env python3
"""
Minimal VPS test server for signbox-vps-listener.

Usage:
  export VPS_TOKEN=your-secret-token
  export PUBLIC_URL=http://YOUR_VPS_IP:8080   # URL reachable from the router
  python3 server.py

Router config (LuCI):
  vps_url   = http://YOUR_VPS_IP:8080/v1/stream
  vps_token = same as VPS_TOKEN

Trigger test deploy:
  curl -X POST http://localhost:8080/api/deploy \
    -H "Authorization: Bearer $VPS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"id":"test-001","chat_id":"","files":["sample.txt","sample.json"]}'
"""

from __future__ import annotations

import json
import os
import queue
import secrets
import sys
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

BASE_DIR = Path(__file__).resolve().parent
FILES_DIR = BASE_DIR / "files"

HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8080"))
VPS_TOKEN = os.environ.get("VPS_TOKEN", "")
PUBLIC_URL = os.environ.get("PUBLIC_URL", f"http://127.0.0.1:{PORT}").rstrip("/")
SSE_PING_INTERVAL = int(os.environ.get("SSE_PING_INTERVAL", "25"))


class SSEHub:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._clients: list[queue.Queue[str | None]] = []

    def subscribe(self) -> queue.Queue[str | None]:
        q: queue.Queue[str | None] = queue.Queue()
        with self._lock:
            self._clients.append(q)
        return q

    def unsubscribe(self, q: queue.Queue[str | None]) -> None:
        with self._lock:
            if q in self._clients:
                self._clients.remove(q)

    def publish(self, payload: dict[str, Any]) -> int:
        line = f"data: {json.dumps(payload, separators=(',', ':'))}\n\n"
        with self._lock:
            clients = list(self._clients)
        for q in clients:
            try:
                q.put_nowait(line)
            except queue.Full:
                pass
        return len(clients)

    def client_count(self) -> int:
        with self._lock:
            return len(self._clients)


HUB = SSEHub()


def ensure_token() -> str:
    global VPS_TOKEN
    if not VPS_TOKEN:
        VPS_TOKEN = secrets.token_urlsafe(24)
        print(f"[info] VPS_TOKEN not set, generated: {VPS_TOKEN}", file=sys.stderr)
    return VPS_TOKEN


def check_auth(header_value: str | None) -> bool:
    token = ensure_token()
    if not header_value:
        return False
    parts = header_value.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return False
    return secrets.compare_digest(parts[1], token)


def json_response(handler: BaseHTTPRequestHandler, status: int, body: dict[str, Any]) -> None:
    data = json.dumps(body, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


def text_response(handler: BaseHTTPRequestHandler, status: int, body: str, content_type: str = "text/plain") -> None:
    data = body.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", f"{content_type}; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


def read_body(handler: BaseHTTPRequestHandler) -> bytes:
    length = int(handler.headers.get("Content-Length", "0") or "0")
    if length <= 0:
        return b""
    return handler.rfile.read(length)


INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>signbox-vps-listener test server</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 720px; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
    h1 { font-size: 1.4rem; }
    label { display: block; margin-top: 1rem; font-weight: 600; }
    input, textarea, button { width: 100%; box-sizing: border-box; margin-top: 0.25rem; font: inherit; }
    textarea { min-height: 5rem; font-family: ui-monospace, monospace; }
    button { width: auto; margin-top: 1rem; padding: 0.5rem 1rem; cursor: pointer; }
    .status { padding: 0.75rem 1rem; border-radius: 6px; background: #f4f4f5; margin: 1rem 0; }
    .ok { color: #166534; }
    .err { color: #b91c1c; }
    code { background: #f4f4f5; padding: 0.1rem 0.35rem; border-radius: 4px; }
    ul { padding-left: 1.25rem; }
  </style>
</head>
<body>
  <h1>signbox-vps-listener — test VPS</h1>
  <div class="status" id="status">Loading…</div>

  <p>Connected SSE clients (routers): <strong id="clients">0</strong></p>
  <p>Stream URL for router: <code id="stream-url"></code></p>

  <form id="deploy-form">
    <label>Deploy ID
      <input name="id" id="deploy-id" required>
    </label>
    <label>Telegram chat_id (optional)
      <input name="chat_id" id="chat-id" placeholder="">
    </label>
    <label>Files (one filename per line, from <code>files/</code>)
      <textarea name="files" id="files">sample.txt
sample.json</textarea>
    </label>
    <label>Auth token
      <input name="token" id="token" type="password" required>
    </label>
    <button type="submit">Send deploy command</button>
  </form>
  <pre id="result"></pre>

  <h2>Quick checks</h2>
  <ul>
    <li><code>GET /health</code> — server status</li>
    <li><code>GET /v1/stream</code> — SSE (Bearer token)</li>
    <li><code>GET /files/sample.txt</code> — test file download</li>
    <li><code>POST /api/deploy</code> — push deploy to connected routers</li>
  </ul>

  <script>
    const statusEl = document.getElementById('status');
    const clientsEl = document.getElementById('clients');
    const streamUrlEl = document.getElementById('stream-url');
    const tokenEl = document.getElementById('token');
    const deployIdEl = document.getElementById('deploy-id');
    const resultEl = document.getElementById('result');

    const savedToken = localStorage.getItem('vps_token');
    if (savedToken) tokenEl.value = savedToken;

    deployIdEl.value = 'test-' + Date.now();

    async function refreshStatus() {
      try {
        const res = await fetch('/health');
        const data = await res.json();
        clientsEl.textContent = data.sse_clients;
        streamUrlEl.textContent = data.stream_url;
        statusEl.innerHTML = '<span class="ok">Server running</span> — public base: <code>' +
          data.public_url + '</code>';
      } catch (e) {
        statusEl.innerHTML = '<span class="err">Cannot reach server</span>';
      }
    }

    document.getElementById('deploy-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const token = tokenEl.value.trim();
      localStorage.setItem('vps_token', token);
      const files = document.getElementById('files').value
        .split('\\n').map(s => s.trim()).filter(Boolean);
      const body = {
        id: deployIdEl.value.trim(),
        chat_id: document.getElementById('chat-id').value.trim(),
        files: files
      };
      resultEl.textContent = 'Sending…';
      try {
        const res = await fetch('/api/deploy', {
          method: 'POST',
          headers: {
            'Authorization': 'Bearer ' + token,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(body)
        });
        const data = await res.json();
        resultEl.textContent = JSON.stringify(data, null, 2);
        refreshStatus();
      } catch (err) {
        resultEl.textContent = String(err);
      }
    });

    refreshStatus();
    setInterval(refreshStatus, 5000);
  </script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "signbox-vps-test/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[{self.log_date_time_string()}] {self.address_string()} {fmt % args}")

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path in ("/", "/index.html"):
            text_response(self, HTTPStatus.OK, INDEX_HTML, "text/html")
            return

        if path == "/health":
            json_response(
                self,
                HTTPStatus.OK,
                {
                    "ok": True,
                    "sse_clients": HUB.client_count(),
                    "public_url": PUBLIC_URL,
                    "stream_url": f"{PUBLIC_URL}/v1/stream",
                    "files_dir": str(FILES_DIR),
                },
            )
            return

        if path == "/v1/stream":
            if not check_auth(self.headers.get("Authorization")):
                text_response(self, HTTPStatus.UNAUTHORIZED, "Unauthorized\n")
                return

            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("X-Accel-Buffering", "no")
            self.end_headers()

            client_q = HUB.subscribe()
            try:
                self.wfile.write(b": connected\n\n")
                self.wfile.flush()

                while True:
                    try:
                        item = client_q.get(timeout=SSE_PING_INTERVAL)
                    except queue.Empty:
                        item = ": ping\n\n"

                    if item is None:
                        break

                    if isinstance(item, str):
                        self.wfile.write(item.encode("utf-8"))
                    else:
                        self.wfile.write(item)
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass
            finally:
                HUB.unsubscribe(client_q)
            return

        if path.startswith("/files/"):
            name = path[len("/files/") :]
            if not name or "/" in name or ".." in name:
                text_response(self, HTTPStatus.BAD_REQUEST, "Invalid filename\n")
                return
            file_path = FILES_DIR / name
            if not file_path.is_file():
                text_response(self, HTTPStatus.NOT_FOUND, "Not found\n")
                return
            data = file_path.read_bytes()
            content_type = "application/octet-stream"
            if name.endswith(".json"):
                content_type = "application/json"
            elif name.endswith(".txt"):
                content_type = "text/plain"
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        text_response(self, HTTPStatus.NOT_FOUND, "Not found\n")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path != "/api/deploy":
            text_response(self, HTTPStatus.NOT_FOUND, "Not found\n")
            return

        if not check_auth(self.headers.get("Authorization")):
            json_response(self, HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
            return

        try:
            body = json.loads(read_body(self).decode("utf-8") or "{}")
        except json.JSONDecodeError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"error": f"invalid json: {exc}"})
            return

        deploy_id = str(body.get("id") or f"deploy-{int(time.time())}")
        chat_id = str(body.get("chat_id") or "")
        raw_files = body.get("files") or []

        file_urls: list[dict[str, str]] = []
        for entry in raw_files:
            if isinstance(entry, str):
                name = entry.strip()
                if not name:
                    continue
                file_urls.append({"url": f"{PUBLIC_URL}/files/{name}"})
            elif isinstance(entry, dict) and entry.get("url"):
                file_urls.append({"url": str(entry["url"])})

        if not file_urls:
            json_response(self, HTTPStatus.BAD_REQUEST, {"error": "files list is empty"})
            return

        payload = {
            "action": "deploy",
            "id": deploy_id,
            "chat_id": chat_id,
            "files": file_urls,
        }

        delivered = HUB.publish(payload)
        json_response(
            self,
            HTTPStatus.OK,
            {
                "ok": True,
                "delivered_to": delivered,
                "command": payload,
            },
        )


def main() -> None:
    FILES_DIR.mkdir(parents=True, exist_ok=True)
    token = ensure_token()

    print("signbox-vps-listener test server")
    print(f"  listen:     http://{HOST}:{PORT}")
    print(f"  public_url: {PUBLIC_URL}")
    print(f"  stream:     {PUBLIC_URL}/v1/stream")
    print(f"  token:      {token}")
    print(f"  files:      {FILES_DIR}")
    print()
    print("Router LuCI settings:")
    print(f"  vps_url   = {PUBLIC_URL}/v1/stream")
    print(f"  vps_token = {token}")
    print()

    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[info] stopped")
        httpd.shutdown()


if __name__ == "__main__":
    main()
