"""Git calls that keep the token out of argv.

The token stays in a mode-600 file. Git asks a helper. The helper reads the file.
"""

from __future__ import annotations

import os
import stat
from pathlib import Path

from proc import run, scrub


HELPER = """#!/bin/sh
# Read the token from a mode-600 file. The token is not a command argument.
while IFS= read -r line; do
  [ -z "$line" ] && break
done
printf 'username=%s\\n' "$OSF_GIT_USER"
printf 'password=%s\\n' "$(tr -d '[:space:]' < "$OSF_TOKEN_FILE")"
"""


def git_env(token_file: Path, username: str, work: Path, base: dict[str, str] | None = None) -> dict[str, str]:
    work.mkdir(parents=True, exist_ok=True)
    helper = work / "git-credential-osf"
    helper.write_text(HELPER, encoding="utf-8")
    helper.chmod(0o700)
    gitconfig = work / "gitconfig"
    host = os.environ.get("OSF_SCALE_URL", "http://localhost:3400").rstrip("/")
    gitconfig.write_text(
        "[credential]\n"
        f"\thelper = !{helper}\n"
        "\tuseHttpPath = true\n"
        f"[credential \"{host}\"]\n"
        f"\thelper = !{helper}\n"
        "\tuseHttpPath = true\n",
        encoding="utf-8",
    )
    gitconfig.chmod(0o600)
    env = dict(base or os.environ)
    env["HOME"] = str(work)
    env["XDG_CONFIG_HOME"] = str(work / "xdg")
    env["GIT_CONFIG_GLOBAL"] = str(gitconfig)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GCM_INTERACTIVE"] = "never"
    env["OSF_GIT_USER"] = username
    env["OSF_TOKEN_FILE"] = str(token_file)
    # Do not copy the token into the environment.
    env.pop("OSF_FORGEJO_TOKEN", None)
    return env


def git(
    argv: list[str],
    *,
    token_file: Path,
    username: str,
    work: Path,
    secrets: list[str],
    timeout: float = 60,
    cwd: str | None = None,
    env_base: dict[str, str] | None = None,
):
    env = git_env(token_file, username, work, env_base)
    # The helper path is not a secret. The token file path is not a secret.
    return run(argv, secrets=secrets, env=env, timeout=timeout, cwd=cwd)


def failure_class(stderr: str, secrets: list[str]) -> str:
    low = scrub(stderr, secrets).lower()
    if "non-fast-forward" in low or ("rejected" in low and "fast-forward" in low):
        return "non-fast-forward"
    if "authentication failed" in low or "401" in low:
        return "auth"
    if "not found" in low or "404" in low:
        return "not-found"
    if "timed out" in low or "timeout" in low:
        return "timeout"
    return "git-failed"


def is_non_ff(stderr: str) -> bool:
    return failure_class(stderr, []) == "non-fast-forward"


def mode_is_private(path: Path) -> bool:
    return stat.S_IMODE(path.stat().st_mode) == 0o600
