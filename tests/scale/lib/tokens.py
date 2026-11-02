"""Make a user token through the API. The value is written to a mode-600 file and not printed."""

from __future__ import annotations

from pathlib import Path

from api import Client
from paths import write_secret


def token_works(path: Path, username: str) -> bool:
    if not path.is_file():
        return False
    client = Client(path)
    try:
        code, payload = client.request("GET", "/api/v1/user")
    except Exception:
        return False
    return code == 200 and isinstance(payload, dict) and payload.get("login") == username


def ensure_user_token(admin: Client, username: str, dest: Path) -> bool:
    if token_works(dest, username):
        return True
    for name in ("osf-scale", "osf-scale-b", "osf-scale-c", "osf-scale-d"):
        code, payload = admin.request(
            "POST",
            f"/api/v1/admin/users/{username}/tokens",
            {"name": name, "scopes": ["all"]},
        )
        if code in (200, 201) and isinstance(payload, dict):
            token = str(payload.get("sha1") or payload.get("token") or "").strip()
            if len(token) >= 20:
                write_secret(dest, token + "\n")
                if token not in admin.secrets:
                    admin.secrets.append(token)
                return token_works(dest, username)
        if code not in (409, 422):
            return False
    return False
