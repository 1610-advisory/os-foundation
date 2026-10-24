#!/usr/bin/env python3
"""Spread a nightly push window. Time is compressed. The factor is printed."""

from __future__ import annotations

import argparse
import json
import math
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from api import Client  # noqa: E402
from assign import assignments, push_users, schedule  # noqa: E402
from gitauth import failure_class, git, is_non_ff  # noqa: E402
from paths import (  # noqa: E402
    DEFAULT_CONCURRENCY,
    DEFAULT_MERGES,
    DEFAULT_PUSH_USERS,
    DEFAULT_WINDOW_MIN,
    ORG,
    SEED,
    admin_token_path,
    base_url,
    ensure_cache,
    push_path,
    read_secret,
    state_path,
    token_path,
)
from tokens import ensure_user_token  # noqa: E402

RUN_DATE = "2026-10-24"


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    rank = math.ceil(p / 100.0 * len(ordered)) - 1
    rank = max(0, min(len(ordered) - 1, rank))
    return ordered[rank]


def auto_factor(window_min: float) -> float:
    # Compress the scheduled offsets into about 90 seconds. Say the factor.
    return max(1.0, (window_min * 60.0) / 90.0)


def push_repo(user: str, repo: str, token_file: Path, url: str, secret: str) -> dict[str, object]:
    """Push one log file on sync/<person>, based on main so a pull request can merge."""
    branch = f"sync/{user}"
    remote = f"{url}/{ORG}/{repo}.git"
    with tempfile.TemporaryDirectory(prefix="osf-scale-") as tmp:
        work = Path(tmp)
        src = work / "src"
        common = dict(token_file=token_file, username=user, work=work / "auth", secrets=[secret])
        cloned = git(["git", "clone", "--depth", "1", remote, str(src)], timeout=60, **common)
        if cloned.returncode != 0:
            return {"ok": False, "seconds": 0.0, "non_ff": False, "kind": "git-failed"}
        named = git(["git", "checkout", "-b", branch], cwd=str(src), timeout=30, **common)
        if named.returncode != 0:
            return {"ok": False, "seconds": 0.0, "non_ff": False, "kind": "git-failed"}
        log = src / "memory" / "logs" / f"{RUN_DATE}-{user}.md"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(f"# {RUN_DATE} {user}\n\nnote: scale check log\n", encoding="utf-8")
        added = git(["git", "add", "memory"], cwd=str(src), timeout=30, **common)
        committed = git(
            [
                "git", "-c", "user.name=Scale Check",
                "-c", "user.email=scale-check@scale.example",
                "-c", "commit.gpgsign=false",
                "commit", "-m", f"log {user}",
            ],
            cwd=str(src),
            timeout=30,
            **common,
        )
        if added.returncode != 0 or committed.returncode != 0:
            return {"ok": False, "seconds": 0.0, "non_ff": False, "kind": "git-failed"}
        start = time.perf_counter()
        try:
            proc = git(["git", "push", remote, f"HEAD:refs/heads/{branch}"], cwd=str(src), timeout=90, **common)
        except Exception:
            return {"ok": False, "seconds": 90.0, "non_ff": False, "kind": "timeout"}
        seconds = time.perf_counter() - start
        kind = "ok" if proc.returncode == 0 else failure_class(proc.stderr or "", [secret])
        return {
            "ok": proc.returncode == 0,
            "seconds": round(seconds, 3),
            "non_ff": is_non_ff(proc.stderr or ""),
            "kind": kind,
        }


def merge_one(user: str, repo: str) -> dict[str, int]:
    client = Client(token_path(user))
    codes: dict[str, int] = {}
    code, payload = client.request(
        "POST",
        f"/api/v1/repos/{ORG}/{repo}/pulls",
        {"title": f"sync: {user}", "head": f"sync/{user}", "base": "main"},
    )
    codes[str(code)] = codes.get(str(code), 0) + 1
    number = payload.get("number") if isinstance(payload, dict) else None
    if code == 409:
        opened = client.list_all(f"/api/v1/repos/{ORG}/{repo}/pulls?state=open")
        for item in opened:
            if item.get("head", {}).get("ref") == f"sync/{user}" or item.get("title") == f"sync: {user}":
                number = item.get("number")
                break
    if not number:
        return codes
    mcode, _ = client.request(
        "POST",
        f"/api/v1/repos/{ORG}/{repo}/pulls/{number}/merge",
        {"Do": "merge", "MergeMessageField": f"sync: {user}"},
    )
    codes[str(mcode)] = codes.get(str(mcode), 0) + 1
    return codes


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--users", type=int, default=DEFAULT_PUSH_USERS)
    parser.add_argument("--window-min", type=float, default=DEFAULT_WINDOW_MIN)
    parser.add_argument("--factor", type=float, default=0)
    parser.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY)
    parser.add_argument("--merges", type=int, default=DEFAULT_MERGES)
    parser.add_argument("--help", action="store_true")
    args = parser.parse_args()
    if args.help:
        print("usage: push-window.sh [--users N] [--window-min M]")
        return 0
    if args.users < 1 or args.window_min <= 0:
        print("FAIL: bad size", file=sys.stderr)
        return 1
    if not state_path().is_file():
        print("FAIL: run bootstrap.sh first", file=sys.stderr)
        return 1
    state = json.loads(state_path().read_text(encoding="utf-8"))
    rows = assignments(int(state["users"]), int(state["areas"]), int(state["seed"]))
    if args.users > len(rows):
        print("FAIL: more push users than bootstrap created", file=sys.stderr)
        return 1
    factor = args.factor if args.factor > 0 else auto_factor(args.window_min)
    names = push_users(rows, args.users, SEED)
    jobs = schedule(names, rows, args.window_min, factor, SEED)
    ensure_cache()
    admin = Client(admin_token_path())
    print(f"tokens {len(names)}", flush=True)
    for index, user in enumerate(names, start=1):
        if not ensure_user_token(admin, user, token_path(user)):
            print(f"FAIL: token for {user}", file=sys.stderr)
            return 1
        if index % 50 == 0:
            print(f"tokens {index}/{len(names)}", flush=True)
    url = base_url()
    workers = max(1, args.concurrency)
    print(
        f"window-min {args.window_min:g} factor {factor:g} users {len(names)} concurrency {workers}",
        flush=True,
    )
    results: list[dict[str, object]] = []
    lock = threading.Lock()
    start = time.perf_counter()

    def do_job(job: dict[str, object]) -> None:
        user = str(job["user"])
        secret = read_secret(token_path(user))
        for repo in job["repos"]:
            item = push_repo(user, str(repo), token_path(user), url, secret)
            with lock:
                results.append(item)
                if len(results) % 25 == 0:
                    print(f"pushes {len(results)}", flush=True)
                if len(results) % 200 == 0:
                    partial = push_path().with_name("push-partial.json")
                    partial.write_text(
                        json.dumps({"pushes": len(results), "ok": sum(1 for row in results if row["ok"])}) + "\n",
                        encoding="utf-8",
                    )

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = []
        for job in jobs:
            delay = float(job["wall_s"]) - (time.perf_counter() - start)
            if delay > 0:
                time.sleep(delay)
            futures.append(pool.submit(do_job, job))
        for future in futures:
            future.result()
    wall = time.perf_counter() - start
    ok = [item for item in results if item["ok"]]
    fail = [item for item in results if not item["ok"]]
    times = [float(item["seconds"]) for item in ok]
    non_ff = sum(1 for item in results if item["non_ff"])
    merge_codes: dict[str, int] = {}
    merges_ok = 0
    merge_jobs = jobs[: min(args.merges, len(jobs))]
    for job in merge_jobs:
        user = str(job["user"])
        repos = list(job["repos"])
        if not repos:
            continue
        codes = merge_one(user, str(repos[0]))
        for key, count in codes.items():
            merge_codes[key] = merge_codes.get(key, 0) + count
        # 201 is create. A merge that worked is 200 or 204.
        if codes.get("200") or codes.get("204"):
            merges_ok += 1
    errors = {key: count for key, count in sorted(merge_codes.items()) if not key.startswith("2")}
    ppm_wall = (len(ok) / (wall / 60.0)) if wall else 0
    ppm_window = len(ok) / args.window_min
    payload = {
        "users": len(names),
        "pushes_ok": len(ok),
        "pushes_fail": len(fail),
        "window_min": args.window_min,
        "factor": round(factor, 2),
        "wall_seconds": round(wall, 1),
        "pushes_per_min_wall": round(ppm_wall, 2),
        "pushes_per_min_window": round(ppm_window, 2),
        "p50_s": None if percentile(times, 50) is None else round(percentile(times, 50), 3),
        "p95_s": None if percentile(times, 95) is None else round(percentile(times, 95), 3),
        "non_ff": non_ff,
        "api_status": merge_codes,
        "api_errors": errors,
        "merges_tried": len(merge_jobs),
        "merges_ok": merges_ok,
        "concurrency": workers,
        "kinds": {},
    }
    kinds: dict[str, int] = {}
    for item in fail:
        kind = str(item["kind"])
        kinds[kind] = kinds.get(kind, 0) + 1
    payload["kinds"] = kinds
    push_path().write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        f"push-window pushes {len(ok)} fail {len(fail)} non-ff {non_ff} "
        f"p50 {payload['p50_s']} p95 {payload['p95_s']} factor {factor:.1f} seconds {wall:.1f}",
        flush=True,
    )
    if not ok:
        print("push-window FAIL", file=sys.stderr)
        return 1
    print("push-window OK", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
