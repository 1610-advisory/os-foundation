#!/usr/bin/env python3
"""Create the scale org, users, repos, teams, and grants. Safe to run again."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from api import ApiError, Client  # noqa: E402
from assign import area_counts, assignments  # noqa: E402
from paths import (  # noqa: E402
    ADMIN_USER,
    COMPANY_REPO,
    CONTAINER,
    DEFAULT_AREAS,
    DEFAULT_USERS,
    ORG,
    SEED,
    admin_token_path,
    area_name,
    bootstrap_path,
    ensure_cache,
    state_path,
    user_name,
    write_secret,
)
from proc import run  # noqa: E402

PATH_ENV = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
HERE = Path(__file__).resolve().parent


class Phase:
    def __init__(self) -> None:
        self.rows: list[dict[str, object]] = []

    def run(self, name: str, count: int, fn):
        start = time.perf_counter()
        fn()
        seconds = time.perf_counter() - start
        self.rows.append({"name": name, "count": count, "seconds": round(seconds, 1)})
        print(f"phase {name} count {count} seconds {seconds:.1f}", flush=True)


def docker_exec(args: list[str], stdin: str | None = None, env_extra: dict[str, str] | None = None, timeout: float | None = 120):
    cmd = [
        "docker", "exec", "-i", "-u", "git",
        "-e", f"PATH={PATH_ENV}",
    ]
    for key, value in (env_extra or {}).items():
        cmd.extend(["-e", f"{key}={value}"])
    cmd.append(CONTAINER)
    cmd.extend(args)
    return run(cmd, stdin=stdin, timeout=timeout)


def install_create_script() -> None:
    src = str(HERE / "create-users.sh")
    copy = run(["docker", "cp", src, f"{CONTAINER}:/tmp/osf-scale-create-users.sh"])
    if copy.returncode != 0:
        raise SystemExit("FAIL: could not copy the user script")
    mode = run(["docker", "exec", "-u", "0", CONTAINER, "chmod", "755", "/tmp/osf-scale-create-users.sh"])
    if mode.returncode != 0:
        raise SystemExit("FAIL: could not prepare the user script")


def create_users(names: list[str], admin: bool = False) -> None:
    if not names:
        return
    install_create_script()
    args = ["sh", "/tmp/osf-scale-create-users.sh"]
    if admin:
        args.append("--admin")
    cmd = [
        "docker", "exec", "-i", "-u", "git",
        "-e", f"PATH={PATH_ENV}",
        "-e", "OSF_MUST_CHANGE=0",
        CONTAINER,
        *args,
    ]
    proc = __import__("subprocess").Popen(
        cmd,
        stdin=__import__("subprocess").PIPE,
        stdout=__import__("subprocess").PIPE,
        stderr=__import__("subprocess").PIPE,
        text=True,
    )
    assert proc.stdin is not None and proc.stdout is not None and proc.stderr is not None
    proc.stdin.write("\n".join(names) + "\n")
    proc.stdin.close()
    done = 0
    for line in proc.stdout:
        text = line.strip()
        if text.startswith("created ") or text.startswith("exists "):
            done += 1
            if done % 100 == 0 or done == len(names):
                print(f"users {done}/{len(names)}", flush=True)
        elif text.startswith("FAIL"):
            print("FAIL: user create", file=sys.stderr)
    rc = proc.wait()
    proc.stderr.read()
    if rc != 0:
        raise SystemExit("FAIL: user create")


def capture_admin_token() -> None:
    dest = admin_token_path()
    if dest.is_file():
        client = Client(dest)
        try:
            code, payload = client.request("GET", "/api/v1/user")
        except ApiError:
            code, payload = 0, None
        if code == 200 and isinstance(payload, dict) and payload.get("login") == ADMIN_USER:
            return
    for name in ("osf-scale-admin", "osf-scale-admin-b", "osf-scale-admin-c"):
        proc = docker_exec(
            [
                "forgejo", "admin", "user", "generate-access-token",
                "--username", ADMIN_USER,
                "--token-name", name,
                "--scopes", "all",
                "--raw",
            ]
        )
        token = (proc.stdout or "").strip()
        if proc.returncode == 0 and len(token) >= 20:
            write_secret(dest, token + "\n")
            return
    raise SystemExit("FAIL: could not make the admin token")


def write_call(client: Client, method: str, path: str, body: dict | None = None, ok: tuple[int, ...] = (200, 201, 204)) -> int:
    last = 0
    payload = None
    for delay in (0, 0.3, 0.8, 1.5, 3):
        if delay:
            time.sleep(delay)
        try:
            last, payload = client.request(method, path, body)
        except ApiError as exc:
            last = exc.code
            if last == 0:
                continue
            break
        if last in ok or last in (409, 422):
            return last
        if last not in (429, 500, 502, 503):
            break
    detail = client.message(payload)
    if detail:
        print(f"FAIL: {method} {path} HTTP {last}", file=sys.stderr)
    else:
        print(f"FAIL: {method} HTTP {last}", file=sys.stderr)
    raise SystemExit(1)


def existing_logins(client: Client) -> set[str]:
    names = set()
    for item in client.list_all("/api/v1/admin/users"):
        login = item.get("login") or item.get("username")
        if login:
            names.add(str(login))
    return names


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--users", type=int, default=DEFAULT_USERS)
    parser.add_argument("--areas", type=int, default=DEFAULT_AREAS)
    parser.add_argument("--help", action="store_true")
    args = parser.parse_args()
    if args.help:
        print("usage: bootstrap.sh [--users N] [--areas N]")
        return 0
    if args.users < 1 or args.areas < 3 or args.users > 20000 or args.areas > 2000:
        print("FAIL: users must be 1 to 20000 and areas must be 3 to 2000", file=sys.stderr)
        return 1

    ensure_cache()
    rows = assignments(args.users, args.areas, SEED)
    counts = area_counts(rows)
    phases = Phase()

    def admin_phase() -> None:
        create_users([ADMIN_USER], admin=True)
        capture_admin_token()

    phases.run("admin", 1, admin_phase)
    client = Client(admin_token_path())

    missing: list[str] = []

    def users_phase() -> None:
        have = existing_logins(client)
        missing.extend(user_name(i) for i in range(1, args.users + 1) if user_name(i) not in have)
        create_users(missing)

    phases.run("users", args.users, users_phase)

    def org_phase() -> None:
        code, _ = client.request("GET", f"/api/v1/orgs/{ORG}")
        if code == 200:
            return
        write_call(
            client,
            "POST",
            "/api/v1/orgs",
            {
                "username": ORG,
                "visibility": "private",
                "full_name": "Scale",
                "description": "Scale check org",
            },
        )

    phases.run("org", 1, org_phase)

    repo_names = [area_name(i) for i in range(1, args.areas + 1)] + [COMPANY_REPO]

    def repos_phase() -> None:
        have = {str(item.get("name")) for item in client.list_all(f"/api/v1/orgs/{ORG}/repos")}
        made = 0
        for name in repo_names:
            if name in have:
                continue
            write_call(
                client,
                "POST",
                f"/api/v1/orgs/{ORG}/repos",
                {
                    "name": name,
                    "private": True,
                    "auto_init": True,
                    "default_branch": "main",
                    "description": f"Scale check {name}",
                },
            )
            made += 1
            if made % 25 == 0:
                print(f"repos {made}", flush=True)

    phases.run("repos", len(repo_names), repos_phase)

    team_ids: dict[str, int] = {}

    def teams_phase() -> None:
        have = {str(item.get("name")): int(item["id"]) for item in client.list_all(f"/api/v1/orgs/{ORG}/teams")}
        for index in range(1, args.areas + 1):
            name = area_name(index)
            if name in have:
                team_ids[name] = have[name]
                continue
            code, payload = client.request(
                "POST",
                f"/api/v1/orgs/{ORG}/teams",
                {
                    "name": name,
                    "description": f"Write on {name}",
                    "permission": "write",
                    "includes_all_repositories": False,
                    "can_create_org_repo": False,
                    "units": ["repo.code", "repo.issues", "repo.pulls"],
                    "units_map": {
                        "repo.code": "write",
                        "repo.issues": "read",
                        "repo.pulls": "write",
                    },
                },
            )
            if code not in (200, 201) or not isinstance(payload, dict) or not payload.get("id"):
                print(f"FAIL: team {name} HTTP {code}", file=sys.stderr)
                raise SystemExit(1)
            team_ids[name] = int(payload["id"])

    phases.run("teams", args.areas, teams_phase)

    def grants_phase() -> None:
        for index in range(1, args.areas + 1):
            name = area_name(index)
            write_call(client, "PUT", f"/api/v1/teams/{team_ids[name]}/repos/{ORG}/{name}")

    phases.run("grants", args.areas, grants_phase)

    memberships = sum(len(repos) for repos in rows.values())

    def members_phase() -> None:
        by_area: dict[str, list[str]] = {}
        for user, repos in rows.items():
            for repo in repos:
                by_area.setdefault(repo, []).append(user)
        done = 0
        for area, users in by_area.items():
            tid = team_ids[area]
            have = set()
            for item in client.list_all(f"/api/v1/teams/{tid}/members"):
                login = item.get("login") or item.get("username")
                if login:
                    have.add(str(login))
            for user in users:
                done += 1
                if user in have:
                    if done % 250 == 0:
                        print(f"members {done}/{memberships}", flush=True)
                    continue
                write_call(client, "PUT", f"/api/v1/teams/{tid}/members/{user}")
                if done % 250 == 0:
                    print(f"members {done}/{memberships}", flush=True)

    phases.run("members", memberships, members_phase)

    # Spot-check grants. Read denial is a separate script.
    sample_user = user_name(1)
    sample_repo = rows[sample_user][0]
    code, _ = client.request("GET", f"/api/v1/teams/{team_ids[sample_repo]}/members/{sample_user}")
    if code not in (200, 204):
        print("FAIL: grant spot-check", file=sys.stderr)
        return 1

    state = {
        "users": args.users,
        "areas": args.areas,
        "seed": SEED,
        "org": ORG,
        "memberships": memberships,
        "one": counts.get(1, 0),
        "two": counts.get(2, 0),
        "three": counts.get(3, 0),
    }
    state_path().write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    payload = {
        "users": args.users,
        "areas": args.areas,
        "company_repos": 1,
        "teams": args.areas,
        "memberships": memberships,
        "seed": SEED,
        "one": counts.get(1, 0),
        "two": counts.get(2, 0),
        "three": counts.get(3, 0),
        "phases": phases.rows,
        "cut": "" if args.users >= DEFAULT_USERS else "smaller probe",
    }
    bootstrap_path().write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print("bootstrap OK", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
