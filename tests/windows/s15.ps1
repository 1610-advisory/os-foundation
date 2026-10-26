# S15. Windows PowerShell 5.1 and PowerShell 7. Generic data only.
$ErrorActionPreference = 'Continue'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$script:failed = $false
$script:work = $null
$script:tasks = @('osfoundation-acme-pull', 'osfoundation-acme-push', 'osfoundation-acme-helper')

function Say([string]$Name, [string]$Result, [string]$Detail) {
  if ($Detail) {
    Write-Output ("S15 {0} {1} {2}" -f $Name, $Result, $Detail)
  } else {
    Write-Output ("S15 {0} {1}" -f $Name, $Result)
  }
  if ($Result -eq 'FAIL') {
    $script:failed = $true
  }
}

function Fail([string]$Name, [string]$Detail) {
  Say $Name 'FAIL' $Detail
}

function Pass([string]$Name) {
  Say $Name 'PASS' ''
}

function Write-Utf8([string]$Path, [string]$Text) {
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Invoke-Git {
  param([string]$Dir, [string[]]$GitArgs)
  & git -C $Dir @GitArgs
  if ($LASTEXITCODE -ne 0) {
    throw ("git {0} failed in {1}" -f ($GitArgs -join ' '), $Dir)
  }
}

function Find-GitBash {
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git -and $git.Source) {
    $dir = Split-Path -Parent $git.Source
    $leaf = Split-Path -Leaf $dir
    if ($leaf -eq 'cmd' -or $leaf -eq 'bin') {
      $candidate = Join-Path (Split-Path -Parent $dir) 'bin\bash.exe'
      if (Test-Path -LiteralPath $candidate) {
        return $candidate
      }
    }
  }
  $fallback = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
  if (Test-Path -LiteralPath $fallback) {
    return $fallback
  }
  return $null
}

function Set-LinkIndex {
  param([string]$Repo, [string]$Blob)
  Invoke-Git $Repo @('update-index', '--add', '--cacheinfo', "120000,$Blob,.agents/skills")
  Invoke-Git $Repo @('update-index', '--add', '--cacheinfo', "120000,$Blob,.claude/skills")
}

function Remove-LinkPath {
  param([string]$Repo, [string]$Rel)
  $path = Join-Path $Repo ($Rel -replace '/', '\')
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force -Recurse
  }
}

function New-Bare {
  param([string]$Path)
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
  Invoke-Git $Path @('init', '-q', '--bare', '-b', 'main')
}

function Copy-Tree {
  param([string]$From, [string]$To)
  New-Item -ItemType Directory -Path $To -Force | Out-Null
  & robocopy $From $To /E /NFL /NDL /NJH /NJS /NC /NS /NP /SL | Out-Null
  if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed: $From"
  }
}

function Invoke-Sync {
  param([string[]]$CmdArgs)
  $out = Join-Path $script:work 'sync-out.txt'
  $err = Join-Path $script:work 'sync-err.txt'
  & $script:syncPs1 @CmdArgs > $out 2> $err
  $code = $LASTEXITCODE
  if ($null -eq $code) { $code = 0 }
  if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out | Out-Host }
  if (Test-Path -LiteralPath $err) { Get-Content -LiteralPath $err | Out-Host }
  return $code
}

$script:userEnvNames = @('OS_HOST_SH', 'OS_PROFILE_SH', 'OS_COMPANY_ROOT', 'XDG_CONFIG_HOME', 'OS_TEST_MODE', 'OS_SECRET_SCAN', 'HOME')

function Set-TaskUserEnv {
  foreach ($name in $script:userEnvNames) {
    $val = [Environment]::GetEnvironmentVariable($name, 'Process')
    if ($val) {
      [Environment]::SetEnvironmentVariable($name, $val, 'User')
    }
  }
}

function Clear-TaskUserEnv {
  foreach ($name in $script:userEnvNames) {
    [Environment]::SetEnvironmentVariable($name, $null, 'User')
  }
}

function Wait-PullOk {
  param([hashtable]$Before, [int]$Seconds)
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    foreach ($path in @($Before.Keys)) {
      if (-not (Test-Path -LiteralPath $path)) { continue }
      $now = [System.IO.File]::ReadAllText($path)
      $old = [string]$Before[$path]
      if ($now.Length -le $old.Length) { continue }
      $fresh = $now.Substring($old.Length)
      if ($fresh -match 'pull ok') { return $true }
    }
  }
  return $false
}

function Snapshot-Logs {
  param([string[]]$Paths)
  $snap = @{}
  foreach ($path in $Paths) {
    if (Test-Path -LiteralPath $path) {
      $snap[$path] = [System.IO.File]::ReadAllText($path)
    } else {
      $snap[$path] = ''
    }
  }
  return $snap
}

function Cleanup-Tasks {
  foreach ($name in $script:tasks) {
    try {
      Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    } catch {
    }
  }
  try {
    Unregister-ScheduledTask -TaskName 'osfoundation-acme-conhost-probe' -Confirm:$false -ErrorAction SilentlyContinue
  } catch {
  }
}

try {
  $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $base = $env:RUNNER_TEMP
  if (-not $base) { $base = $env:TEMP }
  $script:work = Join-Path $base ('osf-s15-' + [guid]::NewGuid().ToString('n').Substring(0, 12))
  New-Item -ItemType Directory -Path $script:work -Force | Out-Null
  $mark = [char]0x00E9
  $script:spaced = Join-Path $script:work ('acme co' + $mark)
  $sandbox = Join-Path $script:work 'home'
  $xdg = Join-Path $sandbox '.config'
  New-Item -ItemType Directory -Path $xdg -Force | Out-Null
  $env:HOME = ($sandbox -replace '\\', '/')
  $env:XDG_CONFIG_HOME = ($xdg -replace '\\', '/')
  $env:OS_TEST_MODE = '1'
  $env:OS_SECRET_SCAN = 'bundled'
  $env:OS_ENGINE_TIMEOUT = '20'
  $env:GIT_AUTHOR_NAME = 'Mia Member'
  $env:GIT_AUTHOR_EMAIL = 'mia.member@acme.test'
  $env:GIT_COMMITTER_NAME = 'Mia Member'
  $env:GIT_COMMITTER_EMAIL = 'mia.member@acme.test'
  $env:GIT_TERMINAL_PROMPT = '0'

  $bash = Find-GitBash
  if (-not $bash) {
    Say 'setup' 'FAIL' 'Git for Windows bash was not found'
    exit 1
  }

  $seed = Join-Path $script:work 'seed'
  Copy-Tree (Join-Path $repo 'template') $seed
  Remove-LinkPath $seed '.agents/skills'
  Remove-LinkPath $seed '.claude/skills'
  $profileText = @"
---
type: company-profile
summary: "Acme Co test"
updated: 2026-10-25
company_slug: acme
level: team
switches: []
os_version: 0.0.0-test
host: github
host_url: ""
org: acme
sync_engine: ""
runner: ubuntu-latest
---

# Acme Co
"@
  Write-Utf8 (Join-Path $seed 'company-profile.md') ($profileText -replace "`r`n", "`n")
  $person = @"
---
type: person
slug: mia
github: mia-member
email: mia.member@acme.test
role: writer
---

# Mia Member
"@
  Write-Utf8 (Join-Path $seed 'people\Mia.md') ($person -replace "`r`n", "`n")
  Write-Utf8 (Join-Path $seed 'notes\seed.md') "seed`n"

  $linkFile = Join-Path $script:work 'link-target'
  [System.IO.File]::WriteAllBytes($linkFile, [Text.Encoding]::ASCII.GetBytes('../skills'))
  Invoke-Git $seed @('init', '-q', '-b', 'main')
  Invoke-Git $seed @('config', 'user.email', 'mia.member@acme.test')
  Invoke-Git $seed @('config', 'user.name', 'Mia Member')
  Invoke-Git $seed @('add', '-A')
  $blob = (& git -C $seed hash-object -w -- $linkFile).Trim()
  if (-not $blob) { throw 'link blob missing' }
  Set-LinkIndex $seed $blob
  Invoke-Git $seed @('commit', '-q', '-m', 'seed')

  $bare = Join-Path $script:work 'origin.git'
  New-Bare $bare
  Invoke-Git $seed @('remote', 'add', 'origin', $bare)
  Invoke-Git $seed @('push', '-q', 'origin', 'main')

  $areaSeed = Join-Path $script:work 'area-seed'
  Copy-Tree (Join-Path $repo 'template\skills\add-area\templates\_area') $areaSeed
  Remove-LinkPath $areaSeed '.agents/skills'
  Remove-LinkPath $areaSeed '.claude/skills'
  Write-Utf8 (Join-Path $areaSeed 'skills\lint\SKILL.md') "area skill`n"
  Invoke-Git $areaSeed @('init', '-q', '-b', 'main')
  Invoke-Git $areaSeed @('config', 'user.email', 'mia.member@acme.test')
  Invoke-Git $areaSeed @('config', 'user.name', 'Mia Member')
  Invoke-Git $areaSeed @('add', '-A')
  $areaBlob = (& git -C $areaSeed hash-object -w -- $linkFile).Trim()
  Set-LinkIndex $areaSeed $areaBlob
  Invoke-Git $areaSeed @('commit', '-q', '-m', 'area seed')
  $areaBare = Join-Path $script:work 'area.git'
  New-Bare $areaBare
  Invoke-Git $areaSeed @('remote', 'add', 'origin', $areaBare)
  Invoke-Git $areaSeed @('push', '-q', 'origin', 'main')

  New-Item -ItemType Directory -Path $script:spaced -Force | Out-Null
  $member = Join-Path $script:spaced 'acme-os'
  & git -c core.symlinks=false -c core.autocrlf=true clone -q -- $bare $member
  if ($LASTEXITCODE -ne 0) { throw 'member clone failed' }
  $areaDest = Join-Path $member 'areas\marketing'
  New-Item -ItemType Directory -Path (Split-Path -Parent $areaDest) -Force | Out-Null
  & git -c core.symlinks=false -c core.autocrlf=true clone -q -- $areaBare $areaDest
  if ($LASTEXITCODE -ne 0) { throw 'area clone failed' }

  Write-Utf8 (Join-Path $seed 'notes\from-origin.md') "from origin`n"
  Invoke-Git $seed @('add', 'notes/from-origin.md')
  Invoke-Git $seed @('commit', '-q', '-m', 'origin note')
  Invoke-Git $seed @('push', '-q', 'origin', 'main')

  $script:syncPs1 = Join-Path $member 'skills\sync\sync.ps1'
  $engine = Join-Path $repo 'tests\fakes\engine.sh'
  $hostDir = Join-Path $script:work 'host'
  New-Item -ItemType Directory -Path $hostDir -Force | Out-Null
  $hostSh = Join-Path $hostDir 'host.sh'
  $hostBody = @'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
  whoami) printf '%s\n' '{"login":"mia-member"}' ;;
  get-token) printf '%s\n' 'local-token' ;;
  open-pr) printf '%s\n' '{"number":1,"url":"http://example.test/1"}' ;;
  auto-merge) printf '%s\n' '{"ok":true}' ;;
  repo-access) printf '%s\n' '{"access":"ok"}'; exit 0 ;;
  *) exit 1 ;;
esac
'@
  Write-Utf8 $hostSh ($hostBody -replace "`r`n", "`n")
  & $bash -lc "chmod +x '$($hostSh -replace '\\', '/')'"

  $cfg = Join-Path $xdg 'acme-os'
  New-Item -ItemType Directory -Path $cfg -Force | Out-Null
  Write-Utf8 (Join-Path $cfg 'me') "mia`n"
  $jobsDir = Join-Path $script:spaced 'jobs'
  $env:OS_COMPANY_ROOT = ($member -replace '\\', '/')
  $env:OS_PROFILE = ((Join-Path $member 'company-profile.md') -replace '\\', '/')
  $env:OS_HOST_SH = ($hostSh -replace '\\', '/')
  $env:OS_PROFILE_SH = ((Join-Path $member 'skills\_host\profile.sh') -replace '\\', '/')
  $env:OS_SYNC_ENGINE = ($engine -replace '\\', '/')
  $env:OS_JOBS_DIR = ($jobsDir -replace '\\', '/')
  Set-Location $member

  $cr = 0
  Get-ChildItem -LiteralPath $member -Recurse -Filter *.sh -File | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes -contains 13) { $cr++ }
  }
  if ($cr -eq 0) { Pass 'line-ends' } else { Fail 'line-ends' "$cr scripts have CR" }

  $pullCode = Invoke-Sync @('pull')
  $pulled = Join-Path $member 'notes\from-origin.md'
  if ($pullCode -eq 0 -and (Test-Path -LiteralPath $pulled)) {
    Pass 'pull'
  } else {
    Fail 'pull' "exit $pullCode"
  }

  $agents = Join-Path $member '.agents\skills'
  $claude = Join-Path $member '.claude\skills'
  $skills = Join-Path $member 'skills'
  $areaCopy = Join-Path $areaDest '.agents\skills'
  $copiesOk = (Test-Path -LiteralPath $agents -PathType Container) -and -not ((Get-Item -LiteralPath $agents).Attributes -band [IO.FileAttributes]::ReparsePoint)
  $copiesOk = $copiesOk -and (Test-Path -LiteralPath $claude -PathType Container)
  $copiesOk = $copiesOk -and (Test-Path -LiteralPath $areaCopy -PathType Container)
  if ($copiesOk) { Pass 'links-copy' } else { Fail 'links-copy' 'a link path is not a folder' }

  $status = & git -C $member status --porcelain
  $areaStatus = & git -C $areaDest status --porcelain
  if (-not $status -and -not $areaStatus) { Pass 'links-status' } else { Fail 'links-status' 'git status is not empty' }

  $newArea = Join-Path $script:work 'new-area'
  Copy-Tree (Join-Path $repo 'template\skills\add-area\templates\_area') $newArea
  $areaScript = Join-Path $script:work 'new-area.sh'
  $areaBody = @'
set -euo pipefail
cd "$AREA"
git init -q -b main
git config user.email mia.member@acme.test
git config user.name "Mia Member"
git config core.symlinks false
for P in .claude/skills .agents/skills; do
  rm -rf "$P"
  mkdir -p "$(dirname "$P")"
  printf '%s' '../skills' > "$P"
done
git add -A
for P in .claude/skills .agents/skills; do
  git update-index --add --cacheinfo 120000,$(printf '%s' ../skills | git hash-object -w --stdin),$P
done
git commit -q -m "New area: start"
listed=$(git ls-files -s -- .claude/skills .agents/skills)
printf '%s\n' "$listed"
count=$(printf '%s\n' "$listed" | grep -c '^120000 ')
[ "$count" -eq 2 ]
extra=$(git ls-files -- .claude/skills .agents/skills | grep -v -x -e '.claude/skills' -e '.agents/skills' || true)
[ -z "$extra" ]
git checkout -q -- .claude/skills .agents/skills
# shellcheck disable=SC1091
. "$LINKS"
SYNC_LOG="$LOG" sync_materialize_repo "$AREA" 1
status=$(git status --porcelain)
[ -z "$status" ]
[ -d .claude/skills ] && [ ! -L .claude/skills ]
[ -d .agents/skills ] && [ ! -L .agents/skills ]
'@
  Write-Utf8 $areaScript ($areaBody -replace "`r`n", "`n")
  $areaLog = Join-Path $script:work 'new-area.log'
  $env:AREA = ($newArea -replace '\\', '/')
  $env:LINKS = (($repo + '\template\skills\sync\links.sh') -replace '\\', '/')
  $env:LOG = ($areaLog -replace '\\', '/')
  & $bash $areaScript
  if ($LASTEXITCODE -eq 0) { Pass 'area-links' } else { Fail 'area-links' "exit $LASTEXITCODE" }

  Write-Utf8 (Join-Path $member 'notes\clean.md') "a clean note`n"
  $pushCode = Invoke-Sync @('push')
  $tree = & git --git-dir=$bare ls-tree -r --name-only refs/heads/sync/mia
  $mode = & git --git-dir=$bare ls-tree refs/heads/sync/mia .agents/skills
  $staged = & git -C $member diff --cached --name-only
  $linkStaged = $false
  foreach ($line in @($staged)) {
    if ($line -like '.agents/skills*' -or $line -like '.claude/skills*') { $linkStaged = $true }
  }
  if ($pushCode -eq 0 -and ($tree -contains 'notes/clean.md') -and ($mode -like '120000*') -and -not $linkStaged) {
    Pass 'push'
    Pass 'links-push'
  } else {
    Fail 'push' "exit $pushCode"
    Fail 'links-push' 'link path was staged or the commit missed the note'
  }
  Remove-Item -LiteralPath (Join-Path $member 'notes\clean.md') -Force -ErrorAction SilentlyContinue

  $beforeHold = & git --git-dir=$bare rev-parse refs/heads/sync/mia
  Write-Utf8 (Join-Path $member 'notes\hold.md') "HOLD-ME`n"
  Invoke-Sync @('push') | Out-Null
  $afterHold = & git --git-dir=$bare rev-parse refs/heads/sync/mia
  $holdTree = & git --git-dir=$bare ls-tree -r --name-only refs/heads/sync/mia
  Remove-Item -LiteralPath (Join-Path $member 'notes\hold.md') -Force
  if ($beforeHold -eq $afterHold -and $holdTree -notcontains 'notes/hold.md') { Pass 'hold-engine' } else { Fail 'hold-engine' 'a commit was pushed' }

  $env:OS_SYNC_ENGINE = 'osf-missing-engine'
  $beforeMiss = & git --git-dir=$bare rev-parse refs/heads/sync/mia
  Write-Utf8 (Join-Path $member 'notes\missing.md') "missing engine`n"
  $missCode = Invoke-Sync @('push')
  $afterMiss = & git --git-dir=$bare rev-parse refs/heads/sync/mia
  Remove-Item -LiteralPath (Join-Path $member 'notes\missing.md') -Force
  $env:OS_SYNC_ENGINE = $engine
  if ($missCode -ne 0 -and $beforeMiss -eq $afterMiss) { Pass 'missing-engine' } else { Fail 'missing-engine' "exit $missCode" }

  $secret = 'gh' + 'p_' + ('a' * 36)
  $beforeSecret = & git --git-dir=$bare rev-parse refs/heads/sync/mia
  Write-Utf8 (Join-Path $member 'notes\secret.md') ("token = " + $secret + "`n")
  $secretCode = Invoke-Sync @('push')
  $afterSecret = & git --git-dir=$bare rev-parse refs/heads/sync/mia
  $shown = & git --git-dir=$bare grep -l -F $secret refs/heads/sync/mia
  Remove-Item -LiteralPath (Join-Path $member 'notes\secret.md') -Force
  if ($beforeSecret -eq $afterSecret -and -not $shown) {
    Pass 'secret-hold'
  } else {
    Fail 'secret-hold' "exit $secretCode"
  }

  Write-Utf8 (Join-Path $seed 'skills\lint\REFRESH.txt') "refreshed`n"
  Invoke-Git $seed @('add', 'skills/lint/REFRESH.txt')
  Invoke-Git $seed @('commit', '-q', '-m', 'refresh skill')
  Invoke-Git $seed @('push', '-q', 'origin', 'main')
  $refreshCode = Invoke-Sync @('pull')
  $refreshed = Join-Path $member '.agents\skills\lint\REFRESH.txt'
  if ($refreshCode -eq 0 -and (Test-Path -LiteralPath $refreshed)) {
    Pass 'links-refresh'
  } else {
    Fail 'links-refresh' "exit $refreshCode"
  }

  $copySkill = Join-Path $member '.claude\skills\lint\SKILL.md'
  $skillsSkill = Join-Path $member 'skills\lint\SKILL.md'
  if (-not (Test-Path -LiteralPath $copySkill)) { Fail 'links-fold' 'copy skill missing' }
  else {
    Add-Content -LiteralPath $copySkill -Value 'LOCAL-FOLD' -Encoding Ascii
    $freshDir = Join-Path $member '.claude\skills\freshfold'
    New-Item -ItemType Directory -Path $freshDir -Force | Out-Null
    Write-Utf8 (Join-Path $freshDir 'NOTE.md') "new skill`n"
    Write-Utf8 (Join-Path $seed 'skills\lint\FROM-UPSTREAM.txt') "from upstream`n"
    Invoke-Git $seed @('add', 'skills/lint/FROM-UPSTREAM.txt')
    Invoke-Git $seed @('commit', '-q', '-m', 'upstream skill')
    Invoke-Git $seed @('push', '-q', 'origin', 'main')
    $foldCode = Invoke-Sync @('pull')
    $folded = (Test-Path -LiteralPath (Join-Path $member 'skills\lint\SKILL.md')) -and (Select-String -LiteralPath $skillsSkill -Pattern 'LOCAL-FOLD' -Quiet)
    $fresh = Test-Path -LiteralPath (Join-Path $member 'skills\freshfold\NOTE.md')
    $up = Test-Path -LiteralPath (Join-Path $member '.claude\skills\lint\FROM-UPSTREAM.txt')
    if ($foldCode -eq 0 -and $folded -and $fresh -and $up) { Pass 'links-fold' } else { Fail 'links-fold' "exit $foldCode" }
    Add-Content -LiteralPath $copySkill -Value 'LOCAL-BOTH' -Encoding Ascii
    Write-Utf8 (Join-Path $seed 'skills\lint\SKILL.md') "UPSTREAM-BOTH`n"
    Invoke-Git $seed @('add', 'skills/lint/SKILL.md')
    Invoke-Git $seed @('commit', '-q', '-m', 'upstream both')
    Invoke-Git $seed @('push', '-q', 'origin', 'main')
    $bothCode = Invoke-Sync @('pull')
    $copyText = ''
    if (Test-Path -LiteralPath $copySkill) { $copyText = [System.IO.File]::ReadAllText($copySkill) }
    $skillText = ''
    if (Test-Path -LiteralPath $skillsSkill) { $skillText = [System.IO.File]::ReadAllText($skillsSkill) }
    $log = Join-Path $xdg 'acme-os\state\sync.log'
    $logged = $false
    if (Test-Path -LiteralPath $log) { $logged = (Select-String -LiteralPath $log -Pattern 'skills copy conflict' -Quiet) }
    $lintBoth = Join-Path $member 'skills\lint\lint.sh'
    $lintBothOut = & $bash $lintBoth --ci --root $member
    $lintBothCode = $LASTEXITCODE
    $drift = ($lintBothOut -join "`n") -match 'skills copy drift:'
    if ($bothCode -eq 0 -and $copyText.Contains('LOCAL-BOTH') -and $skillText.Contains('UPSTREAM-BOTH') -and $logged -and $lintBothCode -eq 1 -and $drift) {
      Pass 'links-conflict'
    } else {
      Fail 'links-conflict' "exit $bothCode"
    }
  }

  Write-Utf8 (Join-Path $member '.agents\skills\lint\DRIFT.md') "drift`n"
  $lint = Join-Path $member 'skills\lint\lint.sh'
  $lintOut = & $bash $lint --ci --root $member
  $lintCode = $LASTEXITCODE
  if ($lintCode -eq 1 -and ($lintOut -join "`n") -match 'skills copy drift:') {
    Pass 'lint-drift'
  } else {
    Fail 'lint-drift' "exit $lintCode"
  }

  $jobsCode = Invoke-Sync @('install-jobs')
  $registered = $true
  foreach ($name in $script:tasks) {
    $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if (-not $task) { $registered = $false; continue }
    $action = $task.Actions[0]
    $taskArgs = [string]$action.Arguments
    if ($taskArgs.IndexOf('sync.ps1') -lt 0) { $registered = $false }
  }
  $pullTask = Get-ScheduledTask -TaskName 'osfoundation-acme-pull' -ErrorAction SilentlyContinue
  $pushTask = Get-ScheduledTask -TaskName 'osfoundation-acme-push' -ErrorAction SilentlyContinue
  if ($pullTask -and [string]$pullTask.Actions[0].Arguments -notmatch 'pull') { $registered = $false }
  if ($pushTask -and [string]$pushTask.Actions[0].Arguments -notmatch 'push') { $registered = $false }
  $pullExport = ''
  if ($pullTask) { $pullExport = Export-ScheduledTask -TaskName 'osfoundation-acme-pull' }
  $pullText = (($pullExport | ForEach-Object { "$_" }) -join "`n")
  $need = @('PT15M', 'conhost.exe', 'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy Bypass', '-WindowStyle Hidden', 'sync.ps1', 'acme co', 'InteractiveToken', 'DisallowStartIfOnBatteries>false', 'StopIfGoingOnBatteries>false', 'StartWhenAvailable>true', 'IgnoreNew', 'ExecutionTimeLimit>PT1H')
  $miss = @()
  foreach ($bit in $need) {
    if ($pullText.IndexOf($bit) -lt 0) { $miss += $bit }
  }
  $realSync = (Resolve-Path -LiteralPath $script:syncPs1).Path
  $q1 = '"' + $realSync + '"'
  $q2 = '&quot;' + $realSync + '&quot;'
  if ($pullText.IndexOf($q1) -lt 0 -and $pullText.IndexOf($q2) -lt 0) { $miss += 'quoted-path' }
  $pushExport = ''
  if ($pushTask) { $pushExport = Export-ScheduledTask -TaskName 'osfoundation-acme-push' }
  $pushText = (($pushExport | ForEach-Object { "$_" }) -join "`n")
  if ($pushText.IndexOf('T02:00') -lt 0) { $miss += 'T02:00' }
  if ($miss.Count -gt 0) { $registered = $false }
  if ($jobsCode -eq 0 -and $registered) {
    Pass 'install-jobs'
  } else {
    Fail 'install-jobs' ("exit {0} missing {1}" -f $jobsCode, ($miss -join ','))
  }

  $logPaths = @(
    (Join-Path $xdg 'acme-os\state\sync.log'),
    (Join-Path $env:USERPROFILE '.config\acme-os\state\sync.log')
  )
  $startName = 'start-task'
  $started = $false
  $startReason = 'task did not write a log line'
  Set-TaskUserEnv
  Write-Utf8 (Join-Path $seed 'notes\start-task.md') "start task`n"
  Invoke-Git $seed @('add', 'notes/start-task.md')
  Invoke-Git $seed @('commit', '-q', '-m', 'task start note')
  Invoke-Git $seed @('push', '-q', 'origin', 'main')
  $beforeStart = Snapshot-Logs $logPaths
  try {
    Start-ScheduledTask -TaskName 'osfoundation-acme-pull' -ErrorAction Stop
    if (Wait-PullOk $beforeStart 60) {
      $started = $true
    } else {
      $info = Get-ScheduledTaskInfo -TaskName 'osfoundation-acme-pull' -ErrorAction SilentlyContinue
      if ($info) { $startReason = "last result $($info.LastTaskResult)" }
    }
  } catch {
    $startReason = $_.Exception.Message
  }
  if ($started) {
    Pass $startName
    $pullNow = Get-ScheduledTask -TaskName 'osfoundation-acme-pull'
    $inner = $pullNow.Actions[0]
    if ([string]$inner.Execute -match 'conhost\.exe$') {
      Pass 'conhost'
    } else {
      $probeOk = $false
      $probeReason = 'probe did not write a log line'
      try {
        Write-Utf8 (Join-Path $seed 'notes\conhost.md') "conhost`n"
        Invoke-Git $seed @('add', 'notes/conhost.md')
        Invoke-Git $seed @('commit', '-q', '-m', 'conhost note')
        Invoke-Git $seed @('push', '-q', 'origin', 'main')
        $wrap = '--headless ' + $inner.Execute + ' ' + $inner.Arguments
        $probeAction = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument $wrap -WorkingDirectory $inner.WorkingDirectory
        Register-ScheduledTask -TaskName 'osfoundation-acme-conhost-probe' -Action $probeAction -Trigger $pullNow.Triggers -Settings $pullNow.Settings -Principal $pullNow.Principal -Force | Out-Null
        $beforeProbe = Snapshot-Logs $logPaths
        Start-ScheduledTask -TaskName 'osfoundation-acme-conhost-probe' -ErrorAction Stop
        if (Wait-PullOk $beforeProbe 60) { $probeOk = $true }
        else {
          $info = Get-ScheduledTaskInfo -TaskName 'osfoundation-acme-conhost-probe' -ErrorAction SilentlyContinue
          if ($info) { $probeReason = "last result $($info.LastTaskResult)" }
        }
      } catch {
        $probeReason = $_.Exception.Message
      }
      Unregister-ScheduledTask -TaskName 'osfoundation-acme-conhost-probe' -Confirm:$false -ErrorAction SilentlyContinue
      if ($probeOk) { Pass 'conhost' } else { Fail 'conhost' $probeReason }
    }
  } else {
    Fail $startName $startReason
    Fail 'conhost' 'start-task did not write a log line'
  }

  Unregister-ScheduledTask -TaskName 'osfoundation-acme-conhost-probe' -Confirm:$false -ErrorAction SilentlyContinue
  $goneCode = Invoke-Sync @('uninstall-jobs')
  $left = @()
  foreach ($name in $script:tasks) {
    $still = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($still) { $left += $name }
  }
  if ($goneCode -eq 0 -and $left.Count -eq 0) { Pass 'uninstall-jobs' } else { Fail 'uninstall-jobs' ("exit {0} left {1}" -f $goneCode, ($left -join ',')) }
} catch {
  Say 'setup' 'FAIL' $_.Exception.Message
} finally {
  Clear-TaskUserEnv
  Cleanup-Tasks
  if ($script:work -and (Test-Path -LiteralPath $script:work)) {
    Set-Location $env:TEMP
    Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if ($script:failed) { exit 1 }
exit 0
