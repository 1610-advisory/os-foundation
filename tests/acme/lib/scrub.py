#!/usr/bin/env python3
"""Scrub token values and token-shaped strings from text or a file.

Reads secret files from a directory (one secret per line, or the whole file).
Never prints a secret. A git SHA is left alone: this does not strip bare hex.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Prefixes are split so this file does not contain a token-shaped literal.
_GHP = "gh" + "p_"
_PAT = "github" + "_pat_"
_GHO = "gh" + "o_"
_GHU = "gh" + "u_"
_GHS = "gh" + "s_"
_XOX = "xo" + "x"
PATTERNS = (
    re.compile(r"(?i)(authorization:\s*(?:token|bearer)\s+)\S+"),
    re.compile(r"(?i)(bearer\s+)\S+"),
    re.compile(_GHP + r"[A-Za-z0-9]+"),
    re.compile(_PAT + r"[A-Za-z0-9_]+"),
    re.compile(_GHO + r"[A-Za-z0-9]+"),
    re.compile(_GHU + r"[A-Za-z0-9]+"),
    re.compile(_GHS + r"[A-Za-z0-9]+"),
    re.compile(_XOX + r"[baprs]-[A-Za-z0-9-]+"),
    re.compile(r"(?i)(password=)\S+"),
    re.compile(r"(?i)(token=)\S+"),
)


def load_secrets(secrets_dir: Path | None, extra_files: list[Path]) -> list[str]:
    found: list[str] = []
    paths: list[Path] = list(extra_files)
    if secrets_dir is not None and secrets_dir.is_dir():
        paths.append(secrets_dir / "admin-token")
        paths.append(secrets_dir / "runner-secret")
        token_dir = secrets_dir / "tokens"
        if token_dir.is_dir():
            paths.extend(p for p in token_dir.iterdir() if p.is_file())
    for path in paths:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for line in text.splitlines():
            item = line.strip()
            if len(item) >= 8:
                found.append(item)
        whole = text.strip()
        if len(whole) >= 8 and whole not in found:
            found.append(whole)
    # Longer secrets first so a short prefix does not leave a tail.
    found.sort(key=len, reverse=True)
    return found


def scrub_text(text: str, secrets: list[str] | None = None) -> str:
    cleaned = text
    for secret in secrets or []:
        if secret:
            cleaned = cleaned.replace(secret, "[redacted]")
    for pattern in PATTERNS:
        cleaned = pattern.sub(r"\1[redacted]" if pattern.groups else "[redacted]", cleaned)
    return cleaned


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Scrub tokens from text.")
    parser.add_argument("infile", nargs="?", help="File to read. Omit to read stdin.")
    parser.add_argument("--out", help="Write here instead of stdout.")
    parser.add_argument("--secrets-dir", help="Directory of token files.")
    parser.add_argument("--extra", action="append", default=[], help="Extra secret file.")
    args = parser.parse_args(argv)

    secrets_dir = Path(args.secrets_dir) if args.secrets_dir else None
    secrets = load_secrets(secrets_dir, [Path(p) for p in args.extra])
    if args.infile:
        raw = Path(args.infile).read_text(encoding="utf-8", errors="replace")
    else:
        raw = sys.stdin.read()
    cleaned = scrub_text(raw, secrets)
    if args.out:
        dest = Path(args.out)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(cleaned, encoding="utf-8")
    else:
        sys.stdout.write(cleaned)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
