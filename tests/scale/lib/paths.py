"""Paths and sizes for the scale check. No secrets."""

from __future__ import annotations

import os
from pathlib import Path

ORG = "scale"
COMPANY_REPO = "company"
ADMIN_USER = "scale-admin"
SEED = 1610
DEFAULT_USERS = 5000
DEFAULT_AREAS = 200
DEFAULT_PAIRS = 200
DEFAULT_WINDOW_MIN = 180
DEFAULT_PUSH_USERS = 1000
DEFAULT_MERGES = 50
DEFAULT_CONCURRENCY = 4
PAGE_LIMIT = 50
CONTAINER = "osf-scale-forgejo"
IMAGE = "data.forgejo.org/forgejo/forgejo:17.0.0"


def cache_dir() -> Path:
    raw = os.environ.get("OSF_SCALE_CACHE")
    if raw:
        return Path(raw)
    return Path.home() / ".cache" / "os-foundation" / "forgejo-scale"


def base_url() -> str:
    return os.environ.get("OSF_SCALE_URL", "http://localhost:3400").rstrip("/")


def admin_token_path() -> Path:
    return cache_dir() / "admin-token"


def token_path(username: str) -> Path:
    return cache_dir() / "tokens" / username


def state_path() -> Path:
    return cache_dir() / "state.json"


def machine_path() -> Path:
    return cache_dir() / "machine.json"


def bootstrap_path() -> Path:
    return cache_dir() / "bootstrap.json"


def denial_path() -> Path:
    return cache_dir() / "denial.json"


def push_path() -> Path:
    return cache_dir() / "push.json"


def ensure_cache() -> Path:
    path = cache_dir()
    path.mkdir(parents=True, mode=0o700, exist_ok=True)
    os.chmod(path, 0o700)
    token_dir = path / "tokens"
    token_dir.mkdir(mode=0o700, exist_ok=True)
    os.chmod(token_dir, 0o700)
    return path


def write_secret(path: Path, text: str) -> None:
    """Write a secret file mode 0600. The value is not logged."""
    ensure_cache()
    path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    os.chmod(path.parent, 0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, text.encode("utf-8"))
    finally:
        os.close(fd)
    os.chmod(path, 0o600)


def read_secret(path: Path) -> str:
    if not path.is_file():
        raise OSError("secret file missing")
    return path.read_text(encoding="utf-8").strip()


def user_name(index: int) -> str:
    return f"user-{index:04d}"


def area_name(index: int) -> str:
    return f"area-{index:03d}"
