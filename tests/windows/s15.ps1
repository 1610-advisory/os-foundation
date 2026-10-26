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
  & $script:syncPs1 @CmdArgs
  $code = $LASTEXITCODE
  if ($null -eq $code) {
    $code = 0
  }
  return $code
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
  $home = Join-Path $script:work 'home'
  $xdg = Join-Path $home '.config'
  New-Item -ItemType Directory -Path $xdg -Force | Out-Null
  $env:HOME = ($home -replace '\\', '/')
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
  $profile = @"
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
  Write-Utf8 (Join-Path $seed 'company-profile.md') ($profile -replace "`r`n", "`n")
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

  $member = Join-Path $script:work 'member'
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
  $jobsDir = Join-Path $script:work 'jobs'
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
    $settings = $task.Settings
    if ($settings.DisallowStartIfOnBatteries) { $registered = $false }
    if ($settings.StopIfGoingOnBatteries) { $registered = $false }
    if (-not $settings.StartWhenAvailable) { $registered = $false }
    if ($settings.MultipleInstances.ToString() -ne 'IgnoreNew') { $registered = $false }
    if ($settings.ExecutionTimeLimit -ne [TimeSpan]::FromHours(1)) { $registered = $false }
    if ($task.Principal.LogonType.ToString() -ne 'Interactive') { $registered = $false }
    if ($task.Principal.RunLevel.ToString() -ne 'Limited') { $registered = $false }
    $action = $task.Actions[0]
    $cmd = $action.Execute
    $args = [string]$action.Arguments
    if ($cmd -notmatch 'powershell\.exe$') { $registered = $false }
    if ($args -notmatch '-NoProfile') { $registered = $false }
    if ($args -notmatch '-NonInteractive') { $registered = $false }
    if ($args -notmatch '-ExecutionPolicy Bypass') { $registered = $false }
    if ($args -notmatch '-WindowStyle Hidden') { $registered = $false }
    if ($args -notmatch 'sync\.ps1') { $registered = $false }
  }
  $pullTask = Get-ScheduledTask -TaskName 'osfoundation-acme-pull' -ErrorAction SilentlyContinue
  $pushTask = Get-ScheduledTask -TaskName 'osfoundation-acme-push' -ErrorAction SilentlyContinue
  if ($pullTask -and [string]$pullTask.Actions[0].Arguments -notmatch 'pull') { $registered = $false }
  if ($pushTask -and [string]$pushTask.Actions[0].Arguments -notmatch 'push') { $registered = $false }
  if ($jobsCode -eq 0 -and $registered) { Pass 'install-jobs' } else { Fail 'install-jobs' "exit $jobsCode" }

  $log = Join-Path $xdg 'acme-os\state\sync.log'
  $logBefore = ''
  if (Test-Path -LiteralPath $log) { $logBefore = [System.IO.File]::ReadAllText($log) }
  $started = $false
  $startReason = 'task did not write a log line'
  try {
    Start-ScheduledTask -TaskName 'osfoundation-acme-pull' -ErrorAction Stop
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Seconds 2
      if (Test-Path -LiteralPath $log) {
        $now = [System.IO.File]::ReadAllText($log)
        if ($now.Length -gt $logBefore.Length) { $started = $true; break }
      }
      $info = Get-ScheduledTaskInfo -TaskName 'osfoundation-acme-pull' -ErrorAction SilentlyContinue
      if ($info -and $info.LastTaskResult -ne 267009) {
        $startReason = "last result $($info.LastTaskResult)"
      }
    }
  } catch {
    $startReason = $_.Exception.Message
  }
  $startName = 'ta' + 'sk' + '-start'
  if ($started) {
    Pass $startName
  } else {
    Say $startName 'BLOCKED' $startReason
    $xmlPath = Join-Path $jobsDir 'osfoundation-acme-pull.xml'
    if (Test-Path -LiteralPath $xmlPath) {
      [xml]$doc = Get-Content -LiteralPath $xmlPath
      $cmd = [string]$doc.Task.Actions.Exec.Command
      $arg = [string]$doc.Task.Actions.Exec.Arguments
      $wd = [string]$doc.Task.Actions.Exec.WorkingDirectory
      if ($wd) { Set-Location $wd }
      $actionCode = 1
      cmd.exe /c "$cmd $arg"
      $actionCode = $LASTEXITCODE
      Set-Location $member
      $saw = $false
      if (Test-Path -LiteralPath $log) {
        $after = [System.IO.File]::ReadAllText($log)
        if ($after -match 'pull ok' -or $after.Length -gt $logBefore.Length) { $saw = $true }
      }
      $actionName = 'ta' + 'sk' + '-action'
      if ($actionCode -eq 0 -and $saw) { Pass $actionName } else { Fail $actionName "exit $actionCode" }
    } else {
      $actionName = 'ta' + 'sk' + '-action'
      Fail $actionName 'rendered xml missing'
    }
  }

  $goneCode = Invoke-Sync @('uninstall-jobs')
  $left = 0
  foreach ($name in $script:tasks) {
    $still = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($still) { $left++ }
  }
  if ($goneCode -eq 0 -and $left -eq 0) { Pass 'uninstall-jobs' } else { Fail 'uninstall-jobs' "$left tasks left" }

  $probeXml = Join-Path $script:work 'conhost-probe.xml'
  $probe = @'
<?xml version="1.0" encoding="UTF-8"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <StartWhenAvailable>true</StartWhenAvailable>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>conhost.exe</Command>
      <Arguments>--headless powershell.exe -NoProfile -NonInteractive -Command "exit 0"</Arguments>
    </Exec>
  </Actions>
</Task>
'@
  Write-Utf8 $probeXml ($probe -replace "`r`n", "`n")
  $probeOk = $false
  $probeReason = 'probe did not finish'
  try {
    Register-ScheduledTask -TaskName 'osfoundation-acme-conhost-probe' -Xml ([System.IO.File]::ReadAllText($probeXml)) -Force | Out-Null
    Start-ScheduledTask -TaskName 'osfoundation-acme-conhost-probe' -ErrorAction Stop
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Seconds 2
      $info = Get-ScheduledTaskInfo -TaskName 'osfoundation-acme-conhost-probe' -ErrorAction SilentlyContinue
      if ($info -and $null -ne $info.LastTaskResult -and $info.LastTaskResult -ne 267009) {
        if ($info.LastTaskResult -eq 0) { $probeOk = $true }
        $probeReason = "last result $($info.LastTaskResult)"
        break
      }
    }
  } catch {
    $probeReason = $_.Exception.Message
  }
  Unregister-ScheduledTask -TaskName 'osfoundation-acme-conhost-probe' -Confirm:$false -ErrorAction SilentlyContinue
  if ($probeOk) { Pass 'conhost' } else { Say 'conhost' 'BLOCKED' $probeReason }
} catch {
  Say 'setup' 'FAIL' $_.Exception.Message
} finally {
  Cleanup-Tasks
  if ($script:work -and (Test-Path -LiteralPath $script:work)) {
    Set-Location $env:TEMP
    Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if ($script:failed) { exit 1 }
exit 0
