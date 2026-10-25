#!/usr/bin/env python3
"""Store a traces POST on the local Forgejo. The token stays in its file."""

from __future__ import annotations

import base64
import json
import re
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PATH_RE = re.compile(r"^/acme2-[A-Za-z0-9-]+/acme2-[A-Za-z0-9-]+/traces/[A-Za-z0-9._-]+\.jsonl$")


def store(token: str, base: str, owner: str, repo: str, path: str, body: bytes) -> int:
    payload = json.dumps(
        {
            "content": base64.b64encode(body).decode("ascii"),
            "message": "trace",
            "branch": "main",
        }
    ).encode("utf-8")
    url = f"{base}/api/v1/repos/{owner}/{repo}/contents/{path}"
    req = urllib.request.Request(
        url,
        data=payload,
        method="PUT",
        headers={
            "Authorization": f"token {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: traces-host.py <token-file> <forgejo-url> <port-file>", file=sys.stderr)
        return 2
    token_file = Path(sys.argv[1])
    base = sys.argv[2].rstrip("/")
    port_file = Path(sys.argv[3])

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self) -> None:  # noqa: N802
            if PATH_RE.match(self.path) is None:
                self.send_response(404)
                self.end_headers()
                return
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            owner, repo, rel = self.path.strip("/").split("/", 2)
            token = token_file.read_text(encoding="utf-8").strip()
            code = store(token, base, owner, repo, rel, body)
            self.send_response(201 if code in (200, 201) else 502)
            self.end_headers()

        def log_message(self, fmt: str, *args: object) -> None:
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port_file.write_text(str(server.server_address[1]), encoding="utf-8")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
