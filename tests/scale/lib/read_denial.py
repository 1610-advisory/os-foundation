#!/usr/bin/env python3
"""Prove allowed reads work and denied reads fail. Zero wrong answers passes."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from api import Client  # noqa: E402
from assign import assignments, denial_sample  # noqa: E402
from gitauth import git  # noqa: E402
from paths import (  # noqa: E402
    DEFAULT_CONCURRENCY,
    DEFAULT_PAIRS,
    ORG,
    SEED,
    admin_token_path,
    base_url,
    denial_path,
    ensure_cache,
    read_secret,
    state_path,
    token_path,
)
from tokens import ensure_user_token  # noqa: E402


def classify(allow: bool, api_code: int, clone_ok: bool, timed_out: bool) -> str:
    if timed_out or api_code in (0, 429, 500, 502, 503):
        return "incomplete"
    if allow:
        return "right" if api_code == 200 and clone_ok else "wrong"
    if api_code == 200 or clone_ok:
        return "wrong"
    if api_code in (403, 404) and not clone_ok:
        return "right"
    return "incomplete"


def check_one(pair: dict[str, object], url: str) -> str:
    user = str(pair["user"])
    repo = str(pair["repo"])
    allow = bool(pair["allow"])
    token_file = token_path(user)
    secret = read_secret(token_file)
    client = Client(token_file, secrets=[secret])
    try:
        api_code, _ = client.request("GET", f"/api/v1/repos/{ORG}/{repo}")
    except Exception:
        api_code = 0
    timed_out = False
    clone_ok = False
    with tempfile.TemporaryDirectory(prefix="osf-scale-") as tmp:
        work = Path(tmp)
        dest = work / "repo"
        try:
            proc = git(
                ["git", "clone", "--depth", "1", f"{url}/{ORG}/{repo}.git", str(dest)],
                token_file=token_file,
                username=user,
                work=work / "auth",
                secrets=[secret],
                timeout=40,
            )
            clone_ok = proc.returncode == 0 and (dest / ".git").is_dir()
        except Exception:
            timed_out = True
    return classify(allow, api_code, clone_ok, timed_out)


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--pairs", type=int, default=DEFAULT_PAIRS)
    parser.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY)
    parser.add_argument("--help", action="store_true")
    args = parser.parse_args()
    if args.help:
        print("usage: read-denial.sh [--pairs N]")
        return 0
    if args.pairs < DEFAULT_PAIRS or args.pairs % 2 != 0:
        print("FAIL: pairs must be even and at least 200", file=sys.stderr)
        return 1
    if not state_path().is_file():
        print("FAIL: run bootstrap.sh first", file=sys.stderr)
        return 1
    state = json.loads(state_path().read_text(encoding="utf-8"))
    rows = assignments(int(state["users"]), int(state["areas"]), int(state["seed"]))
    sample = denial_sample(rows, int(state["areas"]), args.pairs, SEED)
    ensure_cache()
    admin = Client(admin_token_path())
    users = sorted({str(item["user"]) for item in sample})
    print(f"tokens {len(users)}", flush=True)
    for index, user in enumerate(users, start=1):
        if not ensure_user_token(admin, user, token_path(user)):
            print(f"FAIL: token for {user}", file=sys.stderr)
            return 1
        if index % 25 == 0:
            print(f"tokens {index}/{len(users)}", flush=True)
    url = base_url()
    start = time.perf_counter()
    results: list[str] = []
    workers = max(1, args.concurrency)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for index, verdict in enumerate(pool.map(lambda pair: check_one(pair, url), sample), start=1):
            results.append(verdict)
            if index % 20 == 0:
                print(f"pairs {index}/{len(sample)}", flush=True)
    seconds = round(time.perf_counter() - start, 1)
    wrong = results.count("wrong")
    incomplete = results.count("incomplete")
    allowed = sum(1 for item in sample if item["allow"])
    denied = len(sample) - allowed
    payload = {
        "pairs": len(sample),
        "allowed": allowed,
        "denied": denied,
        "wrong": wrong,
        "incomplete": incomplete,
        "seconds": seconds,
        "seed": SEED,
    }
    denial_path().write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        f"read-denial pairs {len(sample)} allowed {allowed} denied {denied} "
        f"wrong {wrong} incomplete {incomplete} seconds {seconds}",
        flush=True,
    )
    if wrong or incomplete:
        print("read-denial FAIL", file=sys.stderr)
        return 1
    print("read-denial OK", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
