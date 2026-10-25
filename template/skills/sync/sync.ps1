# Windows sync commands. Not tested.
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

if ($Rest -contains '-h' -or $Rest -contains '--help' -or $args -contains '--help') {
  Write-Output "sync.ps1 is not tested. Use sync.sh on macOS or Linux."
  exit 0
}

Write-Error "sync.ps1 is not tested."
exit 2
