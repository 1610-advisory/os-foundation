# Remote setup check for Windows: can this person reach a live Claude Code session from their phone?
# Prints one line per item: PASS, FAIL (with the fix) or ASK (check by eye).
# Changes nothing. Exit 0 when nothing failed, 1 when an item failed.
# Run: powershell -ExecutionPolicy Bypass -File skills\remote-setup\check.ps1

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:fails = 0; $script:asks = 0; $email = ''

function Pass($t) { Write-Output "PASS  $t" }
function Fail($t, $fix) { Write-Output "FAIL  $t"; Write-Output "      Fix: $fix"; $script:fails++ }
function Ask($t) { Write-Output "ASK   $t"; $script:asks++ }
function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# Read one AC value from powercfg. Returns $null when it cannot read it (for example another language).
function AcIndex($sub, $setting) {
  $out = powercfg /query SCHEME_CURRENT $sub $setting 2>$null
  $line = $out | Select-String 'Current AC Power Setting Index' | Select-Object -First 1
  if ($line -and ($line -match '0x([0-9a-fA-F]+)')) { return [Convert]::ToInt32($Matches[1], 16) }
  return $null
}

Write-Output "Remote setup check for $Root"
Write-Output ""

# 1. Claude Code
if (Has 'claude') {
  Pass "Claude Code is installed ($((claude --version 2>$null) | Select-Object -First 1))."
  try { $st = (claude auth status 2>$null | Out-String) | ConvertFrom-Json } catch { $st = $null }
  if ($st -and $st.loggedIn -and $st.authMethod -eq 'claude.ai') {
    $email = $st.email
    Pass "Claude Code is signed in with a Claude account ($email)."
  } else {
    Fail "Claude Code is not signed in with a Claude account (an API key does not work with Remote Control)." "run claude, type /login, pick your Claude account."
  }
} else {
  Fail "Claude Code is not installed." "install Claude Code (skills\remote-setup section 1)."
}
if (-not (Has 'bash') -and -not (Test-Path "$env:ProgramFiles\Git\bin\bash.exe")) {
  Fail "Git for Windows is missing. Claude Code and its Herdr link need Git Bash." "winget install --id Git.Git -e"
}

$settings = Join-Path $env:USERPROFILE '.claude\settings.json'
if ((Test-Path $settings) -and ((Get-Content $settings -Raw) -match '"remoteControlAtStartup"\s*:\s*true')) {
  Pass "Remote Control turns on for each new session."
} else {
  Fail "Remote Control is not on at startup." "add `"remoteControlAtStartup`": true to $settings, or turn it on in /config."
}

# 2. Herdr
if (Has 'herdr') {
  Pass "Herdr is installed ($((herdr --version 2>$null) | Select-Object -First 1))."
  if ((herdr integration status 2>$null) -match '^claude: current') {
    Pass "Herdr can bring Claude sessions back after a restart."
  } else {
    Fail "The Herdr link to Claude is missing or old." "herdr integration install claude"
  }
  if ((herdr status server 2>$null) -match 'status: running') {
    Pass "Herdr is running."
    $agents = herdr agent list 2>$null | Out-String
    $rootJson = ($Root -replace '\\', '\\')
    if ($agents -match '"agent":"claude"' -and $agents.Contains("`"cwd`":`"$rootJson")) {
      Pass "A Claude session runs in Herdr in the company folder."
    } else {
      Fail "No Claude session runs in Herdr in the company folder." "start one (skills\remote-setup section 3)."
    }
  } else {
    Fail "Herdr is not running." "run herdr once, then start the company session (section 3)."
  }
} else {
  Fail "Herdr is not installed." "install Herdr (skills\remote-setup section 2)."
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) { Ask "This window runs as administrator. Run Herdr and Claude in a normal window, or Herdr will refuse normal windows." }

# 3. Start after a reboot
$startup = [Environment]::GetFolderPath('Startup')
if (Test-Path (Join-Path $startup 'Company OS Herdr.lnk')) {
  Pass "Herdr starts by itself at sign-in."
} else {
  Fail "Herdr does not start by itself after a restart." "add the Startup shortcut (section 5)."
}
Ask "After a restart (Windows Update too), someone signs in once at the computer before the session comes back."

# 4. Stay awake
$sleep = AcIndex 'SUB_SLEEP' 'STANDBYIDLE'
$hib = AcIndex 'SUB_SLEEP' 'HIBERNATEIDLE'
if ($null -eq $sleep) {
  Ask "Settings > System > Power: on power, Sleep is Never (this check could not read it)."
} elseif ($sleep -eq 0 -and ($null -eq $hib -or $hib -eq 0)) {
  Pass "The computer does not sleep on power."
} else {
  Fail "The computer sleeps on power, and the session drops." "powercfg /change standby-timeout-ac 0 ; powercfg /change hibernate-timeout-ac 0"
}

$battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
if ($battery) {
  if ($battery.BatteryStatus -eq 2) { Pass "The laptop is on the power adapter." }
  else { Fail "The laptop runs on battery. It will sleep when the battery is low." "plug in the power adapter." }
  $lid = AcIndex 'SUB_BUTTONS' 'LIDACTION'
  if ($null -eq $lid) {
    Ask "Control Panel > Power Options > Choose what closing the lid does: on power, Do nothing."
  } elseif ($lid -eq 0) {
    Pass "Closing the lid on power does not sleep."
  } else {
    Fail "Closing the lid makes the laptop sleep." "powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 ; powercfg /setactive SCHEME_CURRENT"
  }
}

# 5. Same account on the phone
Ask "The Claude app on the phone uses the same account as this computer ($email)."

Write-Output ""
if ($script:fails -eq 0) {
  Write-Output "Result: no failures. Check the $($script:asks) ASK line(s) by eye, then test from the phone."
  exit 0
}
Write-Output "Result: $($script:fails) item(s) failed. Fix them in order, then run this check again."
exit 1
