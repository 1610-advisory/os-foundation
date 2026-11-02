"""Run a child process. Refuse a secret in argv.

ps shows every argument. A token, password, key, or other secret must not
be one of them. A mode-600 file, stdin, or an env var read by the child is fine.
"""

from __future__ import annotations

import subprocess
from collections.abc import Mapping, Sequence


class SecretInArgv(RuntimeError):
    pass


def assert_clean_argv(argv: Sequence[str], secrets: Sequence[str]) -> None:
    blob = "\n".join(argv)
    for secret in secrets:
        if secret and len(secret) >= 8 and secret in blob:
            raise SecretInArgv("refusing to run a command with a secret in argv")


def run(
    argv: Sequence[str],
    *,
    secrets: Sequence[str] = (),
    env: Mapping[str, str] | None = None,
    stdin: str | None = None,
    timeout: float | None = None,
    cwd: str | None = None,
) -> subprocess.CompletedProcess[str]:
    assert_clean_argv(argv, secrets)
    return subprocess.run(
        list(argv),
        input=stdin,
        capture_output=True,
        text=True,
        env=None if env is None else dict(env),
        timeout=timeout,
        cwd=cwd,
        check=False,
    )


def scrub(text: str, secrets: Sequence[str]) -> str:
    out = text
    for secret in secrets:
        if secret and len(secret) >= 8:
            out = out.replace(secret, "[redacted]")
    return out
