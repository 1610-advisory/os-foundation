# S15 Windows jobs

Runs on a GitHub `windows-latest` runner, in Windows PowerShell 5.1 and in PowerShell 7.

The script builds a member folder from `template/`, clones it with `core.symlinks=false` and `core.autocrlf=true`, and drives `sync.ps1`. Data is generic. No secret value is written into this repo. A test pattern is built at run time.

```
tests/windows/s15.ps1
```

Each check prints one line: `S15 <check> PASS`, `FAIL`, or `BLOCKED`. The script exits non-zero on any FAIL. BLOCKED is not a failure.

The workflow is `.github/workflows/windows.yml`. It runs on pull requests that touch the Windows files, and on `workflow_dispatch`.
