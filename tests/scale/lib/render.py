#!/usr/bin/env python3
"""Write tests/scale/RESULTS.md from the cache files. No secrets. No home paths."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from paths import bootstrap_path, denial_path, machine_path, push_path  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "RESULTS.md"


def load(path: Path) -> dict:
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def gib(num: object) -> str:
    try:
        return f"{int(num) / (1024 ** 3):.2f} GiB"
    except (TypeError, ValueError):
        return "not recorded"


def table(headers: list[str], rows: list[list[object]]) -> str:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(cell) for cell in row) + " |")
    return "\n".join(lines)


def render(machine: dict, boot: dict, denial: dict, push: dict, limit: str) -> str:
    mem = gib(machine.get("docker_memory_bytes"))
    cap = gib(machine.get("container_memory_bytes"))
    phases = boot.get("phases") or []
    phase_rows = [[item.get("name"), item.get("count"), item.get("seconds")] for item in phases]
    one = int(boot.get("one") or 0)
    two = int(boot.get("two") or 0)
    three = int(boot.get("three") or 0)
    users = int(boot.get("users") or 0)
    parts = []
    parts.append("# Scale check results")
    parts.append("")
    parts.append("Forgejo is not GitHub. These numbers are from one local Forgejo. They do not prove a GitHub limit. At 5,000 staff the first limits are GitHub's own API rate and push rate.")
    parts.append("")
    parts.append("This is not a live run with 5,000 people. Most staff at that size are connector readers. They do not clone. This check is the git-user load.")
    parts.append("")
    parts.append("## Machine")
    parts.append("")
    parts.append(table(
        ["Item", "Value"],
        [
            ["CPU", machine.get("cpu") or "not recorded"],
            ["Docker CPUs", machine.get("docker_cpus") or "not recorded"],
            ["Memory given to Docker", mem],
            ["Cap on this container", f"{machine.get('container_cpus', 2)} CPUs, {cap}"],
            ["Forgejo image", machine.get("forgejo_image") or "not recorded"],
            ["Forgejo version", machine.get("forgejo_version") or "not recorded"],
            ["Port", machine.get("port") or 3400],
        ],
    ))
    parts.append("")
    parts.append("The container cap is there so the Acme stack on the same Docker keeps running. It is not a Forgejo limit.")
    parts.append("")
    parts.append("## Bootstrap")
    parts.append("")
    parts.append(table(
        ["Piece", "Size"],
        [
            ["Users", boot.get("users", "not run")],
            ["Area repos", boot.get("areas", "not run")],
            ["Company repo", boot.get("company_repos", "not run")],
            ["Teams", boot.get("teams", "not run")],
            ["Memberships", boot.get("memberships", "not run")],
            ["Seed", boot.get("seed", "not run")],
            ["Users in one area", one if users else "not run"],
            ["Users in two areas", two if users else "not run"],
            ["Users in three areas", three if users else "not run"],
        ],
    ))
    parts.append("")
    parts.append("Most users are in one area. Some are in two. Some are in three. The seed is fixed, so a later run repeats the same spread.")
    if boot.get("cut"):
        parts.append("")
        parts.append(f"Cut: {boot['cut']}")
    parts.append("")
    parts.append("### Phase times")
    parts.append("")
    if phase_rows:
        parts.append(table(["Phase", "Count", "Seconds"], phase_rows))
    else:
        parts.append("Not run.")
    parts.append("")
    parts.append("## Read denial")
    parts.append("")
    if denial:
        parts.append(table(
            ["Check", "Result"],
            [
                ["Pairs", denial.get("pairs")],
                ["Allowed", denial.get("allowed")],
                ["Denied", denial.get("denied")],
                ["Wrong answers", denial.get("wrong")],
                ["Incomplete", denial.get("incomplete")],
                ["Seconds", denial.get("seconds")],
                ["Seed", denial.get("seed")],
            ],
        ))
        parts.append("")
        parts.append("Pass rule: zero wrong answers. Allowed means the user's team can write that area repo. Denied means the user is not on that team. The company repo is owner-only and is not in this sample.")
    else:
        parts.append("Not run.")
    parts.append("")
    parts.append("## Push window")
    parts.append("")
    if push:
        status = push.get("api_status") or {}
        errors = push.get("api_errors") or {}
        kinds = push.get("kinds") or {}
        parts.append(table(
            ["Item", "Value"],
            [
                ["Users", push.get("users")],
                ["Pushes that worked", push.get("pushes_ok")],
                ["Pushes that failed", push.get("pushes_fail")],
                ["Simulated window (minutes)", push.get("window_min")],
                ["Compression factor", push.get("factor")],
                ["Wall time (seconds)", push.get("wall_seconds")],
                ["Pushes per minute, wall clock", push.get("pushes_per_min_wall")],
                ["Pushes per minute, if spread over the real window", push.get("pushes_per_min_window")],
                ["p50 push time (seconds)", push.get("p50_s")],
                ["p95 push time (seconds)", push.get("p95_s")],
                ["Non-fast-forward conflicts", push.get("non_ff")],
                ["Standing PRs merged", f"{push.get('merges_ok')} of {push.get('merges_tried')}"],
                ["Git concurrency", push.get("concurrency")],
            ],
        ))
        parts.append("")
        parts.append("Each person pushes one small log file on branch `sync/<person>` in each area they belong to. The start time is a random offset inside the window. Time is compressed by the factor above. The wall-clock rate is what this Forgejo handled. The window rate is what the same pushes would be if they were spread over the real hours.")
        parts.append("")
        parts.append("Percentiles use nearest rank on pushes that worked.")
        parts.append("")
        parts.append("### API status codes (pull request create and merge)")
        parts.append("")
        if status:
            parts.append(table(["Status", "Count"], [[key, status[key]] for key in sorted(status)]))
        else:
            parts.append("None.")
        parts.append("")
        parts.append("### API errors")
        parts.append("")
        if errors:
            parts.append(table(["Status", "Count"], [[key, errors[key]] for key in sorted(errors)]))
        else:
            parts.append("None.")
        if kinds:
            parts.append("")
            parts.append("### Push failures")
            parts.append("")
            parts.append(table(["Kind", "Count"], [[key, kinds[key]] for key in sorted(kinds)]))
    else:
        parts.append("Not run.")
    parts.append("")
    parts.append("## First limit")
    parts.append("")
    parts.append(limit.strip() or "No extra limit note was recorded.")
    parts.append("")
    parts.append("## What this does not prove")
    parts.append("")
    parts.append("- Forgejo is not GitHub. A number here is not a GitHub number.")
    parts.append("- GitHub's API rate (about 5,000 requests an hour per user, about 15,000 for an Enterprise Cloud app) and GitHub's push rate are the first limits at this size. This run did not measure those. Check the current GitHub numbers before you rely on them.")
    parts.append("- One SQLite container is not GitHub Enterprise Cloud, and it is not a multi-node Forgejo.")
    parts.append("- The check did not create a year of log files (about 1.25 million small files). It created one small file per push.")
    parts.append("- Connector readers, SSO, SCIM, and audit streaming were not running. Those are switches, not this load.")
    parts.append("- Ask GitHub, in writing, whether a connector reader is an End User before a 5,000-staff rollout. The terms do not say.")
    parts.append("")
    return "\n".join(parts)


def main() -> int:
    require = "--require-all" in sys.argv
    machine = load(machine_path())
    boot = load(bootstrap_path())
    denial = load(denial_path())
    push = load(push_path())
    if require and not (machine and boot and denial and push):
        print("FAIL: results are incomplete", file=sys.stderr)
        return 1
    note = machine_path().parent / "limit.txt"
    limit = note.read_text(encoding="utf-8") if note.is_file() else ""
    text = render(machine, boot, denial, push, limit)
    if "/Users/" in text or "/home/" in text:
        print("FAIL: results contain a home path", file=sys.stderr)
        return 1
    OUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUT.name}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
