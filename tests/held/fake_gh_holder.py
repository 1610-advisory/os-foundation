"""A fake gh for held-mode tests. Not shipped.

One state file holds many orgs, with their repos, teams, members and secrets. Each repo
that create-repo makes is a bare git repo under FAKE_GIT_ROOT/<org>/<name>.git, and its
clone_url is file://..., the same URL the product builds from host_url (file://<root>).

Held orgs (state["held_orgs"]) belong to the holder: any PATCH of the org, any org
secret call and any `gh secret set --org` fails with HTTP 403 and goes into
forbidden.log. The tests read that log: it must stay empty.

FAKE_GH_DIR holds state.json, gh.log and forbidden.log. Never prints a real token.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

D = Path(os.environ["FAKE_GH_DIR"])
GIT = Path(os.environ["FAKE_GIT_ROOT"])
STATE = D / "state.json"


def load() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text())
    return {"login": "", "scopes": "repo, admin:org, workflow", "held_orgs": [], "orgs": {}}


def save(s: dict) -> None:
    STATE.write_text(json.dumps(s, indent=1, sort_keys=True))


def out(obj) -> None:
    print(json.dumps(obj))
    sys.exit(0)


def refuse(code: int, text: str) -> None:
    print(f"gh: {text} (HTTP {code})", file=sys.stderr)
    sys.exit(1)


def forbidden(what: str) -> None:
    with (D / "forbidden.log").open("a") as fh:
        fh.write(what + "\n")
    refuse(403, f"held mode test: forbidden call: {what}")


def org(s: dict, name: str) -> dict:
    o = s["orgs"].get(name)
    if o is None:
        refuse(404, "Not Found")
    return o


def repo(s: dict, o: str, r: str) -> dict:
    rr = org(s, o)["repos"].get(r)
    if rr is None:
        refuse(404, "Not Found")
    return rr


def repo_json(o: str, r: str, rr: dict) -> dict:
    return {"name": r, "full_name": f"{o}/{r}", "private": True, "archived": rr.get("archived", False),
            "clone_url": f"file://{GIT}/{o}/{r}.git"}


def main(argv: list[str]) -> None:
    D.mkdir(parents=True, exist_ok=True)
    with (D / "gh.log").open("a") as fh:
        fh.write(" ".join(argv) + "\n")
    s = load()

    if argv[:2] == ["auth", "token"]:
        print("fake-token")
        sys.exit(0)

    if argv[:2] == ["secret", "set"]:
        name = argv[2]
        args = argv[3:]
        value = sys.stdin.read()
        if not value:
            refuse(422, "empty secret")
        if "--org" in args:
            o = args[args.index("--org") + 1]
            if o in s["held_orgs"]:
                forbidden(f"secret set {name} --org {o}")
            org(s, o).setdefault("secrets", []).append(name)
            save(s)
            sys.exit(0)
        if "--repo" in args:
            o, r = args[args.index("--repo") + 1].split("/", 1)
            rr = repo(s, o, r)
            if name not in rr.setdefault("secrets", []):
                rr["secrets"].append(name)
            save(s)
            sys.exit(0)
        refuse(400, "secret set needs --org or --repo")

    if not argv or argv[0] != "api":
        refuse(400, "unexpected gh command")

    method = "GET"
    path = ""
    include = False
    body = None
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--method":
            method = argv[i + 1]
            i += 2
        elif a == "--input":
            raw = sys.stdin.read()
            body = json.loads(raw) if raw.strip() else {}
            i += 2
        elif a in ("--hostname", "-H"):
            i += 2
        elif a == "-i":
            include = True
            i += 1
        else:
            path = a
            i += 1
    path = "/" + path.lstrip("/")
    base, _, query = path.partition("?")
    page = 1
    m = re.search(r"(?:^|&)page=(\d+)", query)
    if m:
        page = int(m.group(1))

    def listing(items):
        out(items if page == 1 else [])

    if base == "/user" and include:
        sys.stdout.write("HTTP/2.0 200 OK\r\n")
        sys.stdout.write(f"X-Oauth-Scopes: {s['scopes']}\r\n")
        sys.stdout.write("Content-Type: application/json\r\n\r\n")
        print(json.dumps({"login": s["login"]}))
        sys.exit(0)

    # Org-wide calls on a held org are the bug these tests look for.
    m = re.fullmatch(r"/orgs/([^/]+)(/.*)?", base)
    if m and m.group(1) in s["held_orgs"]:
        rest = m.group(2) or ""
        if method == "PATCH" and rest == "":
            forbidden(f"PATCH /orgs/{m.group(1)}")
        if rest.startswith("/actions/secrets"):
            forbidden(f"{method} /orgs/{m.group(1)}{rest}")

    if m and m.group(2) is None:
        o = org(s, m.group(1))
        if method == "GET":
            out({"login": m.group(1), "plan": {"name": o.get("plan", "team")},
                 "default_repository_permission": "read", "members_can_create_repositories": True,
                 "public_repos": 0, "total_private_repos": len(o["repos"])})
        if method == "PATCH":
            o["patched"] = body
            save(s)
            out({"login": m.group(1)})

    m = re.fullmatch(r"/user/memberships/orgs/([^/]+)", base)
    if m:
        role = org(s, m.group(1)).get("members", {}).get(s["login"])
        if not role:
            refuse(404, "Not Found")
        out({"state": "active", "role": role})

    m = re.fullmatch(r"/orgs/([^/]+)/memberships/([^/]+)", base)
    if m and method == "GET":
        role = org(s, m.group(1)).get("members", {}).get(m.group(2))
        if not role:
            refuse(404, "Not Found")
        out({"state": "active", "role": role})

    m = re.fullmatch(r"/orgs/([^/]+)/actions/secrets/([^/]+)", base)
    if m:
        if m.group(2) in org(s, m.group(1)).get("secrets", []):
            out({"name": m.group(2)})
        refuse(404, "Not Found")

    m = re.fullmatch(r"/orgs/([^/]+)/repos", base)
    if m:
        o = org(s, m.group(1))
        if method == "POST":
            name = body["name"]
            if name in o["repos"]:
                refuse(422, "Repository creation failed.")
            o["repos"][name] = {"archived": False, "secrets": [], "rulesets": [], "collaborators": {}}
            bare = GIT / m.group(1) / f"{name}.git"
            bare.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], check=True)
            save(s)
            out(repo_json(m.group(1), name, o["repos"][name]))
        listing([{"name": n} for n in sorted(o["repos"])])

    m = re.fullmatch(r"/orgs/([^/]+)/invitations", base)
    if m:
        listing([])

    m = re.fullmatch(r"/orgs/([^/]+)/teams", base)
    if m and method == "POST":
        o = org(s, m.group(1))
        name = body["name"]
        slug = re.sub(r"[^a-z0-9.-]", "", name.lower().replace(" ", "-").replace("_", "-"))
        teams = o.setdefault("teams", {})
        if slug in teams:
            refuse(422, "Validation Failed")
        teams[slug] = {"name": name, "repos": [], "members": []}
        save(s)
        out({"name": name, "slug": slug, "id": len(teams)})

    m = re.fullmatch(r"/orgs/([^/]+)/teams/([^/]+)", base)
    if m:
        t = org(s, m.group(1)).get("teams", {}).get(m.group(2))
        if t is None:
            refuse(404, "Not Found")
        out({"name": t["name"], "slug": m.group(2)})

    m = re.fullmatch(r"/orgs/([^/]+)/teams/([^/]+)/repos", base)
    if m:
        t = org(s, m.group(1)).get("teams", {}).get(m.group(2))
        if t is None:
            refuse(404, "Not Found")
        listing([{"name": r, "full_name": f"{m.group(1)}/{r}"} for r in t["repos"]])

    m = re.fullmatch(r"/orgs/([^/]+)/teams/([^/]+)/repos/([^/]+)/([^/]+)", base)
    if m and method == "PUT":
        t = org(s, m.group(1)).get("teams", {}).get(m.group(2))
        if t is None:
            refuse(404, "Not Found")
        repo(s, m.group(3), m.group(4))
        if m.group(4) not in t["repos"]:
            t["repos"].append(m.group(4))
        save(s)
        sys.exit(0)

    m = re.fullmatch(r"/orgs/([^/]+)/teams/([^/]+)/memberships/([^/]+)", base)
    if m and method == "PUT":
        t = org(s, m.group(1)).get("teams", {}).get(m.group(2))
        if t is None:
            refuse(404, "Not Found")
        if m.group(3) not in t["members"]:
            t["members"].append(m.group(3))
        save(s)
        out({"state": "active", "role": "member"})

    m = re.fullmatch(r"/repos/([^/]+)/([^/]+)(/.*)?", base)
    if m:
        o, r, rest = m.group(1), m.group(2), m.group(3) or ""
        rr = repo(s, o, r)
        if rest == "":
            if method == "GET":
                out(repo_json(o, r, rr))
            if method == "PATCH":
                if rr.get("archived"):
                    refuse(403, "Repository was archived so is read-only.")
                rr.update(body or {})
                save(s)
                out(repo_json(o, r, rr))
        if rest == "/rulesets":
            if method == "POST":
                rid = len(rr["rulesets"]) + 1
                rr["rulesets"].append(dict(body, id=rid))
                save(s)
                out({"id": rid})
            listing([{"id": x["id"], "name": x.get("name")} for x in rr["rulesets"]])
        m2 = re.fullmatch(r"/rulesets/(\d+)", rest)
        if m2:
            rid = int(m2.group(1))
            if method == "PUT":
                rr["rulesets"] = [dict(body, id=rid) if x["id"] == rid else x for x in rr["rulesets"]]
                save(s)
                out({"id": rid})
            for x in rr["rulesets"]:
                if x["id"] == rid:
                    out(x)
            refuse(404, "Not Found")
        if rest == "/branches/main/protection" and method == "DELETE":
            refuse(404, "Branch not protected")
        m2 = re.fullmatch(r"/collaborators/([^/]+)", rest)
        if m2 and method == "PUT":
            rr["collaborators"][m2.group(1)] = (body or {}).get("permission", "push")
            save(s)
            sys.exit(0)
        if rest == "/invitations":
            listing([])
        if rest == "/pulls":
            listing(rr.get("open_prs", []))
        m2 = re.fullmatch(r"/actions/secrets/([^/]+)", rest)
        if m2:
            if m2.group(1) in rr.get("secrets", []):
                out({"name": m2.group(1)})
            refuse(404, "Not Found")

    print(f"unexpected gh call: {method} {path}", file=sys.stderr)
    with (D / "unexpected.log").open("a") as fh:
        fh.write(f"{method} {path}\n")
    sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
