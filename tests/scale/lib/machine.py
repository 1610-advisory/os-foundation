"""Record the machine and the Forgejo version. No host name. No secrets."""

from __future__ import annotations

import json
import shutil
import subprocess

from paths import IMAGE, ensure_cache, machine_path, write_secret


def _docker_info() -> tuple[int, int]:
    proc = subprocess.run(
        ["docker", "info", "--format", "{{.NCPU}} {{.MemTotal}}"],
        capture_output=True,
        text=True,
        check=False,
    )
    parts = (proc.stdout or "").split()
    cpus = int(parts[0]) if parts else 0
    mem = int(parts[1]) if len(parts) > 1 else 0
    return cpus, mem


def _cpu_brand() -> str:
    if not shutil.which("sysctl"):
        return "not recorded"
    proc = subprocess.run(
        ["sysctl", "-n", "machdep.cpu.brand_string"],
        capture_output=True,
        text=True,
        check=False,
    )
    text = (proc.stdout or "").strip()
    return text or "not recorded"


def _forgejo_version() -> str:
    proc = subprocess.run(
        [
            "docker", "exec", "-u", "git",
            "-e", "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "osf-scale-forgejo", "forgejo", "--version",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    line = (proc.stdout or "").strip().splitlines()
    return line[0] if line else "not recorded"


def main() -> int:
    cpus, mem = _docker_info()
    payload = {
        "cpu": _cpu_brand(),
        "docker_cpus": cpus,
        "docker_memory_bytes": mem,
        "container_cpus": 2,
        "container_memory_bytes": 2 * 1024 * 1024 * 1024,
        "forgejo_image": IMAGE,
        "forgejo_version": _forgejo_version(),
        "port": 3400,
    }
    ensure_cache()
    # Machine facts are not secret, but the cache folder is mode 0700.
    write_secret(machine_path(), json.dumps(payload, indent=2) + "\n")
    # The file is not a token. Relax the mode so a later reader in this user can open it.
    machine_path().chmod(0o600)
    gib = mem / (1024 ** 3) if mem else 0
    print(f"machine CPUs {cpus} docker-memory-GiB {gib:.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
