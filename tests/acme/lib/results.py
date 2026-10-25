#!/usr/bin/env python3
"""Read Acme results from git and the Forgejo API. Never from agent chat.

Stdout is JSON. Exit 0 when the check holds, 2 when it does not, 1 on usage,
3 when the host call failed. Token values are not printed.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scrub import load_secrets, scrub_text  # noqa: E402

TRAILER_RE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9-]*)[ \t]*:[ \t]+(.*)$")


def cache_dir() -> Path:
    return Path(os.environ.get("OSF_ACME_CACHE", Path.home() / ".cache" / "os-foundation" / "forgejo"))


def base_url() -> str:
    return os.environ.get("OSF_ACME_URL", "http://localhost:3300").rstrip("/")


def token_path(who: str) -> Path:
    if who in ("admin", "site"):
        return cache_dir() / "admin-token"
    return cache_dir() / "tokens" / who


def read_token(who: str) -> str:
    path = token_path(who)
    if not path.is_file():
        raise OSError("token file missing")
    return path.read_text(encoding="utf-8").strip()


def api(method: str, path: str, who: str = "admin", body: dict | None = None) -> tuple[int, object]:
    token = read_token(who)
    url = base_url() + path
    data = None
    headers = {"Authorization": "token " + token, "Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            code = resp.status
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        code = exc.code
    except urllib.error.URLError as exc:
        raise OSError("host unreachable") from exc
    if not raw:
        return code, None
    text = raw.decode("utf-8", errors="replace")
    try:
        return code, json.loads(text)
    except json.JSONDecodeError:
        return code, {"raw": scrub_text(text, load_secrets(cache_dir(), []))}


def emit(payload: object, code: int) -> int:
    json.dump(payload, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return code


def fail_host(message: str) -> int:
    secrets = load_secrets(cache_dir(), [])
    print(scrub_text(message, secrets), file=sys.stderr)
    return 3


def permission_name(item: dict) -> str:
    if isinstance(item.get("permission"), str) and item["permission"]:
        return item["permission"]
    perms = item.get("permissions") or {}
    if perms.get("admin"):
        return "admin"
    if perms.get("push") or perms.get("write"):
        return "write"
    if perms.get("pull") or perms.get("read"):
        return "read"
    return ""


def parse_trailers(message: str) -> dict[str, str]:
    lines = message.replace("\r\n", "\n").split("\n")
    block: list[str] = []
    # Git trailers are the last paragraph.
    saw_blank = False
    current: list[str] = []
    for line in lines:
        if line.strip() == "":
            if current:
                block = current
                current = []
            saw_blank = True
            continue
        current.append(line)
    if current and saw_blank:
        block = current
    elif not block:
        block = current
    trailers: dict[str, str] = {}
    for line in block:
        match = TRAILER_RE.match(line)
        if not match:
            continue
        trailers[match.group(1)] = match.group(2).strip()
    return trailers


def normalize_protection(rules: object, branch: str) -> dict:
    items = rules if isinstance(rules, list) else []
    chosen = None
    for rule in items:
        if not isinstance(rule, dict):
            continue
        name = rule.get("branch_name") or rule.get("rule_name") or ""
        if name == branch or chosen is None:
            chosen = rule
            if name == branch:
                break
    if not isinstance(chosen, dict):
        return {"branch": branch, "protected": False, "rules": []}
    return {
        "branch": chosen.get("branch_name") or branch,
        "protected": True,
        "push_blocked": chosen.get("enable_push") is False,
        "required_approvals": chosen.get("required_approvals", 0),
        "status_checks": chosen.get("status_check_contexts") or [],
        "status_check_enabled": bool(chosen.get("enable_status_check")),
        "apply_to_admins": bool(chosen.get("apply_to_admins")),
        "raw": chosen,
    }


def normalize_pr(pull: dict, status: dict | None, runs: list, reviews: list) -> dict:
    checks = []
    if isinstance(status, dict):
        for item in status.get("statuses") or []:
            if not isinstance(item, dict):
                continue
            checks.append({
                "name": item.get("context") or item.get("name") or "",
                "state": item.get("state") or item.get("status") or "",
            })
    for run in runs:
        if not isinstance(run, dict):
            continue
        checks.append({
            "name": run.get("name") or run.get("title") or "actions",
            "state": run.get("status") or run.get("conclusion") or "",
            "event": run.get("event") or "",
            "head_sha": run.get("head_sha") or "",
        })
    approved = False
    for review in reviews:
        if isinstance(review, dict) and str(review.get("state", "")).upper() == "APPROVED":
            approved = True
            break
    head = pull.get("head") if isinstance(pull.get("head"), dict) else {}
    return {
        "state": pull.get("state") or "",
        "merged": bool(pull.get("merged")),
        "approved": approved,
        "number": pull.get("number"),
        "head_sha": head.get("sha") or "",
        "checks": checks,
    }


def runs_for(payload: object) -> list:
    if isinstance(payload, dict):
        runs = payload.get("workflow_runs") or payload.get("runs") or []
        return runs if isinstance(runs, list) else []
    if isinstance(payload, list):
        return payload
    return []


def runner_rows(payload: object) -> list:
    if isinstance(payload, dict):
        rows = payload.get("runners") or payload.get("entries") or []
        return rows if isinstance(rows, list) else []
    if isinstance(payload, list):
        return payload
    return []


def runner_is_online(row: dict) -> bool:
    if row.get("online") is True:
        return True
    status = str(row.get("status") or "").lower()
    return status in ("online", "idle", "active")


def cmd_repo_exists(owner: str, repo: str) -> int:
    code, payload = api("GET", f"/api/v1/repos/{quote(owner)}/{quote(repo)}")
    if code == 200:
        return emit({"exists": True, "full_name": f"{owner}/{repo}", "private": bool((payload or {}).get("private"))}, 0)
    if code == 404:
        return emit({"exists": False, "full_name": f"{owner}/{repo}"}, 2)
    return fail_host(f"repo-exists HTTP {code}")


def cmd_org_exists(org: str) -> int:
    code, _payload = api("GET", f"/api/v1/orgs/{quote(org)}")
    if code == 200:
        return emit({"exists": True, "org": org}, 0)
    if code == 404:
        return emit({"exists": False, "org": org}, 2)
    return fail_host(f"org-exists HTTP {code}")


def cmd_user_exists(user: str) -> int:
    code, _payload = api("GET", f"/api/v1/users/{quote(user)}")
    if code == 200:
        return emit({"exists": True, "user": user}, 0)
    if code == 404:
        return emit({"exists": False, "user": user}, 2)
    return fail_host(f"user-exists HTTP {code}")


def cmd_protection(owner: str, repo: str, branch: str) -> int:
    code, payload = api("GET", f"/api/v1/repos/{quote(owner)}/{quote(repo)}/branch_protections")
    if code == 404:
        return emit({"protected": False, "branch": branch, "rules": []}, 2)
    if code != 200:
        return fail_host(f"protection HTTP {code}")
    summary = normalize_protection(payload, branch)
    return emit(summary, 0 if summary.get("protected") else 2)


def cmd_access(owner: str, repo: str) -> int:
    code, collab = api("GET", f"/api/v1/repos/{quote(owner)}/{quote(repo)}/collaborators")
    if code == 404:
        return emit({"collaborators": [], "teams": []}, 2)
    if code not in (200, 204):
        return fail_host(f"collaborators HTTP {code}")
    tcode, teams = api("GET", f"/api/v1/repos/{quote(owner)}/{quote(repo)}/teams")
    if tcode not in (200, 404):
        return fail_host(f"teams HTTP {tcode}")
    people = []
    for item in collab or []:
        if not isinstance(item, dict):
            continue
        people.append({
            "login": item.get("login") or "",
            "permission": permission_name(item),
        })
    team_rows = []
    for item in teams or []:
        if not isinstance(item, dict):
            continue
        team_rows.append({
            "name": item.get("name") or "",
            "permission": item.get("permission") or permission_name(item),
        })
    return emit({"collaborators": people, "teams": team_rows}, 0)


def cmd_pr(owner: str, repo: str, number: str) -> int:
    path = f"/api/v1/repos/{quote(owner)}/{quote(repo)}/pulls/{quote(number)}"
    code, pull = api("GET", path)
    if code == 404:
        return emit({"state": "missing", "merged": False, "checks": [], "approved": False}, 2)
    if code != 200 or not isinstance(pull, dict):
        return fail_host(f"pr HTTP {code}")
    head = pull.get("head") if isinstance(pull.get("head"), dict) else {}
    sha = head.get("sha") or ""
    status = None
    runs: list = []
    reviews: list = []
    if sha:
        scode, status_payload = api("GET", f"/api/v1/repos/{quote(owner)}/{quote(repo)}/commits/{quote(sha)}/status")
        if scode == 200 and isinstance(status_payload, dict):
            status = status_payload
        rcode, runs_payload = api("GET", f"/api/v1/repos/{quote(owner)}/{quote(repo)}/actions/runs?limit=20")
        if rcode == 200:
            runs = [row for row in runs_for(runs_payload) if not sha or row.get("head_sha") in (None, "", sha)]
    vcode, review_payload = api("GET", path + "/reviews")
    if vcode == 200 and isinstance(review_payload, list):
        reviews = review_payload
    return emit(normalize_pr(pull, status, runs, reviews), 0)


def cmd_file(owner: str, repo: str, path: str, ref: str) -> int:
    quoted = urllib.parse.quote(path, safe="/")
    code, payload = api(
        "GET",
        f"/api/v1/repos/{quote(owner)}/{quote(repo)}/contents/{quoted}?ref={quote(ref)}",
    )
    if code == 404:
        return emit({"found": False, "path": path, "ref": ref}, 2)
    if code != 200 or not isinstance(payload, dict):
        return fail_host(f"file HTTP {code}")
    encoded = payload.get("content") or ""
    try:
        text = base64.b64decode(encoded).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        text = ""
    return emit({"found": True, "path": path, "ref": ref, "content": text}, 0)


def cmd_commit(owner: str, repo: str, sha: str) -> int:
    code, payload = api("GET", f"/api/v1/repos/{quote(owner)}/{quote(repo)}/git/commits/{quote(sha)}")
    if code == 404:
        return emit({"found": False, "sha": sha}, 2)
    if code != 200 or not isinstance(payload, dict):
        return fail_host(f"commit HTTP {code}")
    commit = payload.get("commit") if isinstance(payload.get("commit"), dict) else payload
    message = ""
    author_name = ""
    author_email = ""
    if isinstance(commit, dict):
        message = commit.get("message") or ""
        author = commit.get("author") if isinstance(commit.get("author"), dict) else {}
        author_name = author.get("name") or ""
        author_email = author.get("email") or ""
    return emit({
        "found": True,
        "sha": payload.get("sha") or sha,
        "author_name": author_name,
        "author_email": author_email,
        "message": message,
        "trailers": parse_trailers(message),
    }, 0)


def cmd_trailers(owner: str, repo: str, sha: str) -> int:
    return cmd_commit(owner, repo, sha)


def cmd_runner_online() -> int:
    code, payload = api("GET", "/api/v1/admin/actions/runners")
    rows = runner_rows(payload) if code == 200 else []
    if code not in (200, 404):
        ocode, opayload = api("GET", "/api/v1/orgs/acme/actions/runners")
        if ocode != 200:
            return fail_host(f"runners HTTP {code}")
        rows = runner_rows(opayload)
    elif not rows:
        ocode, opayload = api("GET", "/api/v1/orgs/acme/actions/runners")
        if ocode == 200:
            rows = runner_rows(opayload)
    online = [row for row in rows if isinstance(row, dict) and runner_is_online(row)]
    names = [row.get("name") or "" for row in rows if isinstance(row, dict)]
    if online:
        return emit({"online": True, "names": names}, 0)
    return emit({"online": False, "names": names}, 2)


def cmd_clone_denied(user: str, owner: str, repo: str) -> int:
    try:
        token = read_token(user)
    except OSError:
        return fail_host("token file missing")
    url = f"{base_url()}/{quote(owner)}/{quote(repo)}.git"
    with tempfile.TemporaryDirectory(prefix="osf-acme-") as tmp:
        helper = Path(tmp) / "git-credential-osf"
        gitconfig = Path(tmp) / "gitconfig"
        helper.write_text(
            "#!/bin/sh\n"
            "while IFS= read -r line; do\n"
            "  [ -z \"$line\" ] && break\n"
            "done\n"
            "printf 'username=%s\\n' \"$OSF_GIT_USER\"\n"
            "printf 'password=%s\\n' \"$OSF_FORGEJO_TOKEN\"\n",
            encoding="utf-8",
        )
        helper.chmod(0o700)
        gitconfig.write_text(
            "[credential]\n"
            f"\thelper = !{helper}\n"
            "\tuseHttpPath = true\n",
            encoding="utf-8",
        )
        gitconfig.chmod(0o600)
        env = os.environ.copy()
        env["OSF_FORGEJO_TOKEN"] = token
        env["OSF_GIT_USER"] = user
        env["GIT_CONFIG_GLOBAL"] = str(gitconfig)
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GCM_INTERACTIVE"] = "never"
        try:
            proc = subprocess.run(
                ["git", "ls-remote", url],
                env=env,
                capture_output=True,
                text=True,
                timeout=40,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return fail_host("clone probe timed out")
    denied = proc.returncode != 0
    return emit({"denied": denied, "user": user, "repo": f"{owner}/{repo}"}, 0 if denied else 2)


def api_list(path: str, who: str = "admin", limit: int = 50) -> tuple[int, list]:
    page = 1
    items: list = []
    while page <= 40:
        sep = "&" if "?" in path else "?"
        code, payload = api("GET", f"{path}{sep}limit={limit}&page={page}", who)
        if code != 200 or not isinstance(payload, list):
            return code, items
        items.extend(payload)
        if len(payload) < limit:
            break
        page += 1
    return 200, items


def cmd_commits(owner: str, repo: str, ref: str, limit: int) -> int:
    code, rows = api_list(
        f"/api/v1/repos/{quote(owner)}/{quote(repo)}/commits?sha={quote(ref)}",
        limit=limit,
    )
    if code == 404:
        return emit({"commits": []}, 2)
    if code != 200:
        return fail_host(f"commits HTTP {code}")
    commits = []
    for row in rows[:limit]:
        if not isinstance(row, dict):
            continue
        commit = row.get("commit") if isinstance(row.get("commit"), dict) else {}
        message = commit.get("message") or ""
        commits.append({
            "sha": row.get("sha") or "",
            "message": message,
            "trailers": parse_trailers(message),
        })
    return emit({"commits": commits}, 0 if commits else 2)


def cmd_branches(owner: str, repo: str) -> int:
    code, rows = api_list(f"/api/v1/repos/{quote(owner)}/{quote(repo)}/branches")
    if code == 404:
        return emit({"branches": []}, 2)
    if code != 200:
        return fail_host(f"branches HTTP {code}")
    names = [row.get("name") or "" for row in rows if isinstance(row, dict)]
    return emit({"branches": names}, 0 if names else 2)


def cmd_tags(owner: str, repo: str) -> int:
    code, rows = api_list(f"/api/v1/repos/{quote(owner)}/{quote(repo)}/tags")
    if code == 404:
        return emit({"tags": []}, 2)
    if code != 200:
        return fail_host(f"tags HTTP {code}")
    names = [row.get("name") or "" for row in rows if isinstance(row, dict)]
    return emit({"tags": names}, 0)


def cmd_wait_check(owner: str, repo: str, sha: str, timeout: int) -> int:
    import time
    deadline = time.time() + timeout
    last = {"state": "waiting", "sha": sha}
    while time.time() < deadline:
        code, status = api("GET", f"/api/v1/repos/{quote(owner)}/{quote(repo)}/commits/{quote(sha)}/status")
        states = []
        if code == 200 and isinstance(status, dict):
            states = [item.get("state") for item in status.get("statuses") or [] if isinstance(item, dict)]
            if "success" in states or status.get("state") == "success":
                return emit({"state": "success", "sha": sha, "checks": states}, 0)
            if any(item in ("failure", "error") for item in states):
                return emit({"state": "failure", "sha": sha, "checks": states}, 2)
        rcode, runs_payload = api("GET", f"/api/v1/repos/{quote(owner)}/{quote(repo)}/actions/runs?limit=20")
        if rcode == 200:
            for row in runs_for(runs_payload):
                if row.get("head_sha") not in (None, "", sha):
                    continue
                state = str(row.get("status") or "")
                last = {"state": state, "sha": sha, "name": row.get("name") or ""}
                if state == "success":
                    return emit(last, 0)
                if state in ("failure", "cancelled", "error"):
                    return emit(last, 2)
        time.sleep(5)
    return emit(last, 2)


def quote(part: str) -> str:
    return urllib.parse.quote(part, safe="")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read Acme results from Forgejo and git.")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("repo-exists")
    p.add_argument("owner")
    p.add_argument("repo")
    p = sub.add_parser("org-exists")
    p.add_argument("org")
    p = sub.add_parser("user-exists")
    p.add_argument("user")
    p = sub.add_parser("protection")
    p.add_argument("owner")
    p.add_argument("repo")
    p.add_argument("--branch", default="main")
    p = sub.add_parser("access")
    p.add_argument("owner")
    p.add_argument("repo")
    p = sub.add_parser("pr")
    p.add_argument("owner")
    p.add_argument("repo")
    p.add_argument("number")
    p = sub.add_parser("file")
    p.add_argument("owner")
    p.add_argument("repo")
    p.add_argument("path")
    p.add_argument("--ref", default="main")
    p = sub.add_parser("trailers")
    p.add_argument("owner")
    p.add_argument("repo")
    p.add_argument("sha")
    p = sub.add_parser("commit")
    p.add_argument("owner")
    p.add_argument("repo")
    p.add_argument("sha")
    p = sub.add_parser("clone-denied")
    p.add_argument("user")
    p.add_argument("owner")
    p.add_argument("repo")
    p = sub.add_parser("runner-online")
    p = sub.add_parser("wait-check")
    p.add_argument("owner")
    p.add_argument("repo")
    p.add_argument("sha")
    p.add_argument("--timeout", type=int, default=180)
    p = sub.add_parser("commits")
    p.add_argument("owner")
    p.add_argument("repo")
    p.add_argument("--ref", default="main")
    p.add_argument("--limit", type=int, default=20)
    p = sub.add_parser("branches")
    p.add_argument("owner")
    p.add_argument("repo")
    p = sub.add_parser("tags")
    p.add_argument("owner")
    p.add_argument("repo")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.cmd == "repo-exists":
            return cmd_repo_exists(args.owner, args.repo)
        if args.cmd == "org-exists":
            return cmd_org_exists(args.org)
        if args.cmd == "user-exists":
            return cmd_user_exists(args.user)
        if args.cmd == "protection":
            return cmd_protection(args.owner, args.repo, args.branch)
        if args.cmd == "access":
            return cmd_access(args.owner, args.repo)
        if args.cmd == "pr":
            return cmd_pr(args.owner, args.repo, args.number)
        if args.cmd == "file":
            return cmd_file(args.owner, args.repo, args.path, args.ref)
        if args.cmd in ("trailers", "commit"):
            return cmd_commit(args.owner, args.repo, args.sha)
        if args.cmd == "clone-denied":
            return cmd_clone_denied(args.user, args.owner, args.repo)
        if args.cmd == "runner-online":
            return cmd_runner_online()
        if args.cmd == "wait-check":
            return cmd_wait_check(args.owner, args.repo, args.sha, args.timeout)
        if args.cmd == "commits":
            return cmd_commits(args.owner, args.repo, args.ref, args.limit)
        if args.cmd == "branches":
            return cmd_branches(args.owner, args.repo)
        if args.cmd == "tags":
            return cmd_tags(args.owner, args.repo)
    except OSError as exc:
        return fail_host(str(exc))
    parser.error("unknown command")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
