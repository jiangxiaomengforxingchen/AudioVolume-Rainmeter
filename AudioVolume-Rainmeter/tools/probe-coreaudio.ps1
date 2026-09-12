# AudioVolume - Core Audio probe
# Runs the capture helper directly and prints the raw levels, so you can tell whether
# "no level" comes from the capture side or the display side.
#
# ASCII only on purpose: Windows PowerShell 5.1 reads .ps1 files as ANSI.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\probe-coreaudio.ps1
#   powershell -ExecutionPolicy Bypass -File tools\probe-coreaudio.ps1 -Seconds 20

[CmdletBinding()]
param(
  [int]$Seconds = 10,
  [int]$IntervalMs = 200
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Exe = Join-Path $RepoRoot "skin\AudioVolume\@Resources\bin\AudioLevelHelper.exe"

if (-not (Test-Path $Exe)) {
  throw "helper not found: $Exe  (run tools\build.ps1 first)"
}

$tmp = Join-Path $env:TEMP ("av-probe-" + [guid]::NewGuid().ToString("N") + ".txt")

Write-Host "starting helper ..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $Exe `
  -ArgumentList '--out', "`"$tmp`"", '--interval', '80' `
  -PassThru -WindowStyle Hidden

Write-Host "sampling for $Seconds s (play some music, or talk into the microphone) ..." -ForegroundColor Cyan
Write-Host ""
Write-Host ("{0,-9} {1,-26} {2}" -f "time", "playback", "microphone")
Write-Host ("-" * 62)

$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds $IntervalMs
  if (-not (Test-Path $tmp)) { continue }
  try {
    $text = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
  } catch {
    continue
  }

  $out = [regex]::Match($text, 'out=(\d+)').Groups[1].Value
  $mic = [regex]::Match($text, 'mic=(\d+)').Groups[1].Value
  if ($out -eq "" -and $mic -eq "") { continue }

  $barOut = "#" * [math]::Min([int]$out / 4, 22)
  $barMic = "#" * [math]::Min([int]$mic / 4, 22)
  Write-Host ("{0,-9} {1,3}% {2,-22} {3,3}% {4}" -f `
    (Get-Date -Format "HH:mm:ss"), $out, $barOut, $mic, $barMic)
}

Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "How to read this:" -ForegroundColor Yellow
Write-Host "  * playback column moves but the skin stays flat -> display side"
Write-Host "    (check the Rainmeter log for Lua errors, and that level.txt is written)"
Write-Host "  * both columns are 0                            -> capture side"
Write-Host "    (wrong default device, exclusive mode, or a muted endpoint)"
Write-Host "  * both columns always equal                     -> the two Script measures"
Write-Host "    point at the same .lua file, so their Lua state collides"
