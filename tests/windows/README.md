# S15 Windows jobs

Runs on a GitHub `windows-latest` runner, in Windows PowerShell 5.1 and in PowerShell 7.

The script builds a member folder from `template/`, clones it with `core.symlinks=false` and `core.autocrlf=true`, and drives `sync.ps1`. Data is generic. No secret value is written into this repo. A test pattern is built at run time.

```
tests/windows/s15.ps1
```

Each check prints one line: `S15 <check> PASS`, `FAIL`, or `BLOCKED`. The script exits non-zero on any FAIL. BLOCKED is not a failure.

The workflow is `.github/workflows/windows.yml`. It runs on pull requests that touch the Windows files, and on `workflow_dispatch`.

It first runs `tests/team/test_join_old.sh` in Git Bash (check `join-crlf`): join reads an old folder cloned with the runner's own `core.autocrlf=true`, and the base it sets aside differs from the person's copy only by the one edit.

Then, in Git Bash, `tests/windows/b74.sh` checks the `gh api` paths (B74), and `tests/windows/b82.sh` checks git's home folder (B82). b82 denies writes on a temp folder (`icacls`), sets `HOME` to it, and asserts the one `home:` line and exit 2, from `os_home_check` and from `join.sh`. A writable home on the system drive prints nothing. One on another drive prints one warning and goes on. Each check prints `B82 PASS`, `FAIL` or `SKIP`.
