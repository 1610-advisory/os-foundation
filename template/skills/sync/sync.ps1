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
