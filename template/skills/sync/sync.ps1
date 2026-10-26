# Launch sync.sh through Git for Windows bash. ASCII only. PowerShell 5.1 and 7.
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

$ErrorActionPreference = 'Continue'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}

function Show-Usage {
  Write-Output "Usage: sync.ps1 <command> [flags]"
  Write-Output "Runs sync.sh through Git for Windows bash. Never uses System32 bash (that is WSL)."
  Write-Output "Commands match sync.sh: pull, push, propose, status, install-jobs, uninstall-jobs, helper, collect, admin-run."
  Write-Output "Set OS_GIT_BASH to the bash.exe path when Git is not on PATH."
}

function Test-HelpSwitch {
  if ($null -eq $Rest) {
    return $false
  }
  foreach ($arg in $Rest) {
    if ($arg -eq '-h' -or $arg -eq '--help') {
      return $true
    }
  }
  return $false
}

if (Test-HelpSwitch) {
  Show-Usage
  exit 0
}


function Test-System32Bash {
  param([string]$Path)
  if (-not $Path) {
    return $false
  }
  $full = [System.IO.Path]::GetFullPath($Path)
  $bad = [System.IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\bash.exe'))
  return ($full.ToLower() -eq $bad.ToLower())
}

function Add-BashCandidate {
  param([System.Collections.Generic.List[string]]$List, [string]$Path)
  if (-not $Path) {
    return
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }
  if (Test-System32Bash $Path) {
    return
  }
  $full = [System.IO.Path]::GetFullPath($Path)
  if (-not $List.Contains($full)) {
    [void]$List.Add($full)
  }
}


function Test-BarePull {
  if ($null -eq $Rest) { return $false }
  if ($Rest.Count -ne 1) { return $false }
  return ($Rest[0] -eq 'pull')
}

function Normalize-Root([string]$Path) {
  if (-not $Path) { return $null }
  $Path = $Path -replace '/', '\'
  return $Path.TrimEnd('\')
}

function Find-CompanyRoot {
  if ($env:OS_COMPANY_ROOT) {
    $cand = Normalize-Root $env:OS_COMPANY_ROOT
    if (-not $cand) { return $null }
    $profile = Join-Path $cand 'company-profile.md'
    if (Test-Path -LiteralPath $profile) { return $cand }
    return $null
  }
  $dir = (Get-Location).Path
  while ($dir) {
    $profile = Join-Path $dir 'company-profile.md'
    if (Test-Path -LiteralPath $profile) { return $dir }
    $parent = Split-Path -Parent $dir
    if (-not $parent -or $parent -eq $dir) { return $null }
    $dir = $parent
  }
  return $null
}

function Get-SyncClock {
  $now = [int64]0
  $mid = [int64]0
  if ($env:OS_SYNC_CLOCK) {
    $raw = $env:OS_SYNC_CLOCK.Trim()
    $parts = $raw -split ' '
    if ($parts.Length -ne 2) { return $null }
    if ($parts[0] -notmatch '^\d+$') { return $null }
    if ($parts[1] -notmatch '^\d+$') { return $null }
    $now = [int64]$parts[0]
    $mid = [int64]$parts[1]
  } else {
    $epoch = New-Object System.DateTime 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc)
    $utc = [System.DateTime]::UtcNow
    $span = $utc - $epoch
    $now = [int64][Math]::Floor($span.TotalSeconds)
    $local = [System.DateTime]::Now
    $mid = [int64](($local.Hour * 3600) + ($local.Minute * 60) + $local.Second)
  }
  $out = New-Object System.Collections.Hashtable
  $out['Now'] = $now
  $out['Mid'] = $mid
  return ,$out
}

function Test-FullDue([int64]$Full) {
  $clock = Get-SyncClock
  if ($null -eq $clock) { return $true }
  $since = [int64]$clock['Mid'] - 14400
  $mod = $since % 86400
  if ($mod -lt 0) { $mod = $mod + 86400 }
  $boundary = [int64]$clock['Now'] - $mod
  return ($Full -lt $boundary)
}

function Test-RelOk([string]$Rel) {
  if ($Rel -eq '.') { return $true }
  if ($Rel -match '\.\.') { return $false }
  if ($Rel -match '^areas/[A-Za-z0-9._-]+$') { return $true }
  if ($Rel -match '^users/[A-Za-z0-9._-]+$') { return $true }
  return $false
}

function Read-PullState([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  foreach ($b in $bytes) {
    if ($b -eq 13 -or $b -gt 127) { return $null }
  }
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  if ($text.EndsWith("`n")) {
    if ($text.Length -le 1) { return $null }
    $text = $text.Substring(0, $text.Length - 1)
  }
  $lines = $text.Split("`n")
  if ($lines.Length -lt 4) { return $null }
  if ($lines[0] -ne 'os-sync-state 1') { return $null }
  if ($lines[1] -notmatch '^full (\d+)$') { return $null }
  $full = [int64]$Matches[1]
  if ($lines[2] -notmatch '^me ([A-Za-z0-9-]+|-)$') { return $null }
  $me = $Matches[1]
  if ($lines[3] -ne 'bot 0' -and $lines[3] -ne 'bot 1') { return $null }
  $bot = $lines[3].Substring(4)
  $repos = New-Object System.Collections.Hashtable
  $order = New-Object System.Collections.Generic.List[string]
  for ($i = 4; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    if ($line -notmatch '^repo (ok|retry) ([0-9a-f]{40}|[0-9a-f]{64}|none) (\S+)$') { return $null }
    $status = $Matches[1]
    $sha = $Matches[2]
    $rel = $Matches[3]
    if (-not (Test-RelOk $rel)) { return $null }
    if ($repos.ContainsKey($rel)) { return $null }
    $repos[$rel] = @{ Status = $status; Sha = $sha }
    [void]$order.Add($rel)
  }
  $parsed = New-Object System.Collections.Hashtable
  $parsed['Full'] = $full
  $parsed['Me'] = $me
  $parsed['Bot'] = $bot
  $parsed['Repos'] = $repos
  $parsed['Order'] = $order
  return ,$parsed
}

function Get-DiskRels([string]$Root, [string]$Me) {
  $set = New-Object System.Collections.Generic.List[string]
  $rootGit = Join-Path $Root '.git'
  if (Test-Path -LiteralPath $rootGit) { [void]$set.Add('.') }
  $areas = Join-Path $Root 'areas'
  if (Test-Path -LiteralPath $areas -PathType Container) {
    $kids = @(Get-ChildItem -LiteralPath $areas -Directory -ErrorAction SilentlyContinue)
    foreach ($kid in $kids) {
      $git = Join-Path $kid.FullName '.git'
      if (Test-Path -LiteralPath $git) {
        [void]$set.Add('areas/' + $kid.Name)
      }
    }
  }
  if ($Me -and $Me -ne '-') {
    $user = Join-Path (Join-Path $Root 'users') $Me
    $userGit = Join-Path $user '.git'
    if (Test-Path -LiteralPath $userGit) {
      [void]$set.Add('users/' + $Me)
    }
  }
  return ,$set
}

function Test-SameRelSet($Disk, $StateOrder) {
  if ($Disk.Count -ne $StateOrder.Count) { return $false }
  foreach ($rel in $Disk) {
    $found = $false
    foreach ($other in $StateOrder) {
      if ($other -eq $rel) { $found = $true }
    }
    if (-not $found) { return $false }
  }
  return $true
}

function Quote-WinArg([string]$Text) {
  $escaped = $Text -replace '"', '\"'
  return '"' + $escaped + '"'
}

function Start-LimitedExe([string]$File, [string]$ArgsLine, [string]$HeaderValue) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $File
  $psi.Arguments = $ArgsLine
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
  $psi.EnvironmentVariables['GCM_INTERACTIVE'] = 'never'
  if ($HeaderValue) {
    $psi.EnvironmentVariables['GIT_CONFIG_COUNT'] = '1'
    $psi.EnvironmentVariables['GIT_CONFIG_KEY_0'] = 'http.https://github.com/.extraheader'
    $psi.EnvironmentVariables['GIT_CONFIG_VALUE_0'] = $HeaderValue
  }
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  try {
    [void]$proc.Start()
  } catch {
    return $null
  }
  if (-not $proc.WaitForExit(20000)) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit(2000) } catch {}
    return $null
  }
  $out = ''
  try { $out = $proc.StandardOutput.ReadToEnd() } catch { return $null }
  try { [void]$proc.StandardError.ReadToEnd() } catch {}
  $done = New-Object System.Collections.Hashtable
  $done['Code'] = $proc.ExitCode
  $done['Out'] = $out
  return ,$done
}

function Get-GitExe {
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git -and $git.Source) { return $git.Source }
  return $null
}

function Get-GhHeader {
  if ($script:ghHeaderChecked) { return $script:ghHeader }
  $script:ghHeaderChecked = $true
  $script:ghHeader = $null
  $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
  if (-not $gh -or -not $gh.Source) { return $null }
  $ran = Start-LimitedExe $gh.Source 'auth token' $null
  if ($null -eq $ran) { return $null }
  if ($ran['Code'] -ne 0) { return $null }
  $token = [string]$ran['Out']
  $token = $token.Trim()
  if (-not $token) { return $null }
  $pair = 'x-access-token:' + $token
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
  $b64 = [Convert]::ToBase64String($bytes)
  $script:ghHeader = 'Authorization: Basic ' + $b64
  $token = $null
  $pair = $null
  $bytes = $null
  $b64 = $null
  return $script:ghHeader
}

function Test-LocalOrigin([string]$Url) {
  if (-not $Url) { return $false }
  if ($Url -match '^file://') { return $true }
  if ($Url -match '^[A-Za-z][A-Za-z0-9+.-]*://') { return $false }
  if ($Url -match '^[A-Za-z]:[\\/]') { return $true }
  if ($Url.StartsWith('/')) { return $true }
  if ($Url.StartsWith('\\')) { return $false }
  if ($Url -match '^[A-Za-z0-9._-]+@') { return $false }
  return $true
}

function Test-GitHubHttps([string]$Url) {
  if (-not $Url) { return $false }
  if ($Url -match '@') { return $false }
  if ($Url -match '^https://github\.com/') { return $true }
  return $false
}

function Get-RemoteSha([string]$Text) {
  if (-not $Text) { return $null }
  $bits = $Text.Split("`n")
  foreach ($bit in $bits) {
    $bit = $bit.Trim()
    if ($bit -match '^([0-9a-f]{40}|[0-9a-f]{64})([\s].*)?$') {
      return $Matches[1]
    }
  }
  return $null
}

function Get-QuickDecision {
  $script:ghHeaderChecked = $false
  $script:ghHeader = $null
  $root = Find-CompanyRoot
  if (-not $root) { return 'bash' }
  $git = Join-Path $root '.git'
  if (-not (Test-Path -LiteralPath $git -PathType Container)) { return 'bash' }
  $statePath = Join-Path (Join-Path $git 'os-foundation') 'pull-state'
  $state = Read-PullState $statePath
  if ($null -eq $state) { return 'bash' }
  if ($state['Bot'] -eq '1') { return 'bash' }
  if (Test-FullDue ([int64]$state['Full'])) { return 'bash' }
  foreach ($rel in $state['Order']) {
    if ($state['Repos'][$rel]['Status'] -eq 'retry') { return 'bash' }
  }
  $disk = Get-DiskRels $root $state['Me']
  if (-not (Test-SameRelSet $disk $state['Order'])) { return 'bash' }
  $gitExe = Get-GitExe
  if (-not $gitExe) { return 'bash' }
  $header = $null
  foreach ($rel in $state['Order']) {
    $sha = [string]$state['Repos'][$rel]['Sha']
    if ($sha -eq 'none') { continue }
    if ($rel -eq '.') {
      $repo = $root
    } else {
      $repo = Join-Path $root ($rel -replace '/', '\')
    }
    $urlRun = Start-LimitedExe $gitExe ('-C ' + (Quote-WinArg $repo) + ' remote get-url origin') $null
    if ($null -eq $urlRun -or $urlRun['Code'] -ne 0) { return 'bash' }
    $url = ([string]$urlRun['Out']).Trim()
    $useHeader = $null
    if (Test-LocalOrigin $url) {
      $useHeader = $null
    } elseif (Test-GitHubHttps $url) {
      if (-not $header) {
        $header = Get-GhHeader
        if (-not $header) { return 'bash' }
      }
      $useHeader = $header
    } else {
      return 'bash'
    }
    $ls = Start-LimitedExe $gitExe ('-C ' + (Quote-WinArg $repo) + ' -c credential.helper= ls-remote origin refs/heads/main') $useHeader
    if ($null -eq $ls -or $ls['Code'] -ne 0) { return 'bash' }
    $remote = Get-RemoteSha ([string]$ls['Out'])
    if (-not $remote -or $remote -ne $sha) { return 'bash' }
  }
  return 'nochange'
}

function Find-GitBash {
  $found = New-Object System.Collections.Generic.List[string]
  if ($env:OS_GIT_BASH) {
    Add-BashCandidate $found $env:OS_GIT_BASH
  }
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git -and $git.Source) {
    $dir = Split-Path -Parent $git.Source
    $leaf = Split-Path -Leaf $dir
    if ($leaf -eq 'cmd' -or $leaf -eq 'bin') {
      $root = Split-Path -Parent $dir
      Add-BashCandidate $found (Join-Path $root 'bin\bash.exe')
    }
  }
  $keys = @(
    'HKLM:\SOFTWARE\GitForWindows',
    'HKCU:\SOFTWARE\GitForWindows',
    'HKLM:\SOFTWARE\WOW6432Node\GitForWindows'
  )
  foreach ($key in $keys) {
    if (-not (Test-Path -LiteralPath $key)) {
      continue
    }
    $item = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($item -and $item.InstallPath) {
      Add-BashCandidate $found (Join-Path $item.InstallPath 'bin\bash.exe')
    }
  }
  if ($env:ProgramFiles) {
    Add-BashCandidate $found (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
  }
  if ($env:ProgramW6432) {
    Add-BashCandidate $found (Join-Path $env:ProgramW6432 'Git\bin\bash.exe')
  }
  if ($found.Count -gt 0) {
    return $found[0]
  }
  return $null
}

if (Test-BarePull) {
  $quickDecision = 'bash'
  try {
    $quickDecision = Get-QuickDecision
  } catch {
    $quickDecision = 'bash'
  }
  $script:ghHeader = $null
  if ($quickDecision -eq 'nochange') {
    Write-Output 'sync: no change'
    exit 0
  }
  if ($env:OS_SYNC_PS_NO_BASH -eq '1') {
    Write-Output 'sync: bash needed'
    exit 9
  }
}

$bash = Find-GitBash
if (-not $bash) {
  Write-Output "install Git for Windows: winget install --id Git.Git -e"
  exit 3
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$syncSh = (Join-Path $here 'sync.sh') -replace '\\', '/'
$bashArgs = @($syncSh)
if ($Rest) {
  $bashArgs += $Rest
}
& $bash @bashArgs
$code = $LASTEXITCODE
if ($null -eq $code) {
  $code = 1
}
exit $code
