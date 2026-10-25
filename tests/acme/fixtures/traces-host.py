#!/usr/bin/env python3
"""Store a traces POST on the local Forgejo. The token stays in its file."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PATH_RE = re.compile(r"^/acme2-[A-Za-z0-9-]+/acme2-[A-Za-z0-9-]+/traces/[A-Za-z0-9._-]+\.jsonl$")
HELPER = Path(__file__).resolve().parents[1] / "lib" / "git-credential-seat.sh"
WORKDIR = Path(tempfile.mkdtemp(prefix="osf-traces-"))


def git(repo: Path, token: str, *args: str) -> int:
    cfg = WORKDIR / "gitconfig"
    cfg.write_text(
        "[credential]\n"
        f"\thelper = !{HELPER}\n"
        "\tuseHttpPath = true\n",
        encoding="utf-8",
    )
    cfg.chmod(0o600)
    env = os.environ.copy()
    env.update(
        {
            "GIT_CONFIG_GLOBAL": str(cfg),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "OSF_FORGEJO_TOKEN": token,
            "OSF_GIT_USER": "acme-admin",
        }
    )
    proc = subprocess.run(["git", "-C", str(repo), *args], env=env, capture_output=True, check=False)
    return proc.returncode


def store(token: str, base: str, owner: str, repo: str, path: str, body: bytes) -> int:
    dest = WORKDIR / f"{owner}-{repo}"
    url = f"{base}/{owner}/{repo}.git"
    if not (dest / ".git").is_dir():
        parent = dest.parent
        parent.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        env.update(
            {
                "GIT_TERMINAL_PROMPT": "0",
                "OSF_FORGEJO_TOKEN": token,
                "OSF_GIT_USER": "acme-admin",
            }
        )
        cfg = WORKDIR / "gitconfig"
        cfg.write_text(
            "[credential]\n"
            f"\thelper = !{HELPER}\n"
            "\tuseHttpPath = true\n",
            encoding="utf-8",
        )
        cfg.chmod(0o600)
        env["GIT_CONFIG_GLOBAL"] = str(cfg)
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        cloned = subprocess.run(
            ["git", "clone", url, str(dest)],
            env=env,
            capture_output=True,
            check=False,
        )
        if cloned.returncode != 0:
            return 1
    target = dest / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(body)
    if git(dest, token, "add", path) != 0:
        return 1
    if git(dest, token, "diff", "--cached", "--quiet") == 0:
        return 0
    if git(
        dest,
        token,
        "-c",
        "user.name=Ada Admin",
        "-c",
        "user.email=ada.admin@acme.test",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "-m",
        "trace",
    ) != 0:
        return 1
    if git(dest, token, "push", "origin", "HEAD:main") != 0:
        return 1
    return 0


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
            self.send_response(201 if code == 0 else 502)
            self.end_headers()

        def log_message(self, fmt: str, *args: object) -> None:
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port_file.write_text(str(server.server_address[1]), encoding="utf-8")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
