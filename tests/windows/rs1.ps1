# RS1. remote-setup set-settings.ps1 in Windows PowerShell 5.1 and PowerShell 7. Generic data only.
$ErrorActionPreference = 'Continue'
$script:failed = $false
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$set = Join-Path $repo 'template\skills\remote-setup\set-settings.ps1'
$defaults = Join-Path $repo 'template\skills\remote-setup\defaults.txt'
$want = [int](((Get-Content $defaults) | Where-Object { $_ -match '^autoCompactWindow=' }) -replace '^autoCompactWindow=', '')
$exe = (Get-Process -Id $PID).Path

function Say([string]$Name, [bool]$Ok, [string]$Detail) {
  if ($Ok) { Write-Output "RS1 $Name PASS" } else { Write-Output "RS1 $Name FAIL $Detail"; $script:failed = $true }
}
function Run-Set([string]$File) {
  $out = & $exe -NoProfile -ExecutionPolicy Bypass -File $set -Settings $File 2>&1 | Out-String
  return @{ Code = $LASTEXITCODE; Out = $out }
}
function Write-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("rs1-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
  # Missing file and missing folder.
  $f = Join-Path $work 'a\.claude\settings.json'
  $r = Run-Set $f
  $j = if (Test-Path $f) { [IO.File]::ReadAllText($f) | ConvertFrom-Json } else { $null }
  Say 'missing-file' ($r.Code -eq 0 -and $j -and $j.autoCompactWindow -eq $want -and $r.Out -match 'was not set') $r.Out

  # Other keys kept, arrays stay arrays.
  $f = Join-Path $work 'b.json'
  Write-Text $f '{"remoteControlAtStartup": true, "permissions": {"allow": ["Bash(ls)"], "deny": []}, "env": {"A": "b"}, "model": "x"}'
  $r = Run-Set $f
  $t = [IO.File]::ReadAllText($f); $j = $t | ConvertFrom-Json
  $ok = $r.Code -eq 0 -and $j.autoCompactWindow -eq $want -and $j.remoteControlAtStartup -eq $true -and $j.model -eq 'x' -and $j.env.A -eq 'b' -and ($t -match '"allow":\s*\[\s*"Bash\(ls\)"\s*\]') -and ($t -match '"deny":\s*\[\s*\]') -and ($t -notmatch '"Count"')
  Say 'other-keys' $ok ($r.Out + $t)

  # Already set: file not touched.
  $f = Join-Path $work 'c.json'
  $orig = '{ "autoCompactWindow": ' + $want + ', "model": "x" }'
  Write-Text $f $orig
  $r = Run-Set $f
  Say 'already-set' ($r.Code -eq 0 -and $r.Out -match "already $want" -and [IO.File]::ReadAllText($f) -eq $orig) $r.Out

  # Other value: replaced, old and new shown.
  $f = Join-Path $work 'd.json'
  Write-Text $f '{"autoCompactWindow": 123, "model": "x"}'
  $r = Run-Set $f
  $j = [IO.File]::ReadAllText($f) | ConvertFrom-Json
  Say 'other-value' ($r.Code -eq 0 -and $r.Out -match "set to $want \(was 123\)" -and $j.autoCompactWindow -eq $want -and $j.model -eq 'x') $r.Out

  # Bad JSON: nothing changed.
  $f = Join-Path $work 'e.json'
  Write-Text $f '{"model": "x",'
  $r = Run-Set $f
  Say 'bad-json' ($r.Code -eq 1 -and [IO.File]::ReadAllText($f) -eq '{"model": "x",') $r.Out
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
if ($script:failed) { exit 1 }
exit 0
