# Set the remote-setup defaults (defaults.txt, next to this file) in ~/.claude/settings.json.
# Keeps every other key. Makes the file when it is missing. Changes nothing when the file
# is not valid JSON. Prints the old and the new value of each setting.
# Run: powershell -ExecutionPolicy Bypass -File skills\remote-setup\set-settings.ps1
param([string]$Settings = (Join-Path $env:USERPROFILE '.claude\settings.json'))

# Windows PowerShell 5.1 writes arrays as {"value":[...],"Count":n} unless this type data is removed.
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }

$defaults = Join-Path $PSScriptRoot 'defaults.txt'
$text = ''
if (Test-Path -LiteralPath $Settings) { $text = [IO.File]::ReadAllText($Settings) }
if ($text.Trim() -eq '') { $text = '{}' }
try { $obj = $text | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }
if (-not ($obj -is [System.Management.Automation.PSCustomObject])) {
  Write-Output "set-settings: $Settings is not a valid JSON object. Nothing changed. Fix the file, then run this again."
  exit 1
}

$changed = $false
foreach ($line in [IO.File]::ReadAllLines($defaults)) {
  $line = $line.Trim()
  if ($line -eq '' -or $line.StartsWith('#') -or -not $line.Contains('=')) { continue }
  $key, $val = $line -split '=', 2
  $new = $val | ConvertFrom-Json
  $prop = $obj.PSObject.Properties[$key]
  $old = if ($prop) { $prop.Value | ConvertTo-Json -Compress } else { $null }
  if ($old -eq $val) { Write-Output "${key}: already $val."; continue }
  $obj | Add-Member -NotePropertyName $key -NotePropertyValue $new -Force
  $was = if ($null -ne $old) { $old } else { 'not set' }
  Write-Output "${key}: set to $val (was $was)."
  $changed = $true
}

if ($changed) {
  $dir = Split-Path -Parent $Settings
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $json = $obj | ConvertTo-Json -Depth 100
  [IO.File]::WriteAllText($Settings, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
}
exit 0
