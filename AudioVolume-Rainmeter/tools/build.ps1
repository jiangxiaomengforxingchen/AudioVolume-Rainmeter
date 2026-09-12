# AudioVolume build script (ASCII only: Windows PowerShell 5.1 reads .ps1 as ANSI,
# so non-ASCII characters in this file would be mangled).
#
#  1. compile src/AudioLevelHelper.cs -> skin/AudioVolume/@Resources/bin/AudioLevelHelper.exe
#  2. package dist/AudioVolume-v<version>.zip  (extract and run install.bat)
#  3. remind about .rmskin (cannot be scripted: Rainmeter only accepts signed packages)
#
# usage: powershell -ExecutionPolicy Bypass -File tools\build.ps1

[CmdletBinding()]
param(
  [string]$Version = "1.0.0",
  [switch]$SkipCompile,
  [switch]$SkipZip
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SrcFile  = Join-Path $RepoRoot "src\AudioLevelHelper.cs"
$BinDir   = Join-Path $RepoRoot "skin\AudioVolume\@Resources\bin"
$ExePath  = Join-Path $BinDir "AudioLevelHelper.exe"
$DistDir  = Join-Path $RepoRoot "dist"
$ZipPath  = Join-Path $DistDir "AudioVolume-v$Version.zip"

function Info($m) { Write-Host "[build] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ ok  ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[warn ] $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 1. compile
if (-not $SkipCompile) {
  Info "compiling AudioLevelHelper.cs ..."
  $csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1

  if (-not $csc) {
    throw "csc.exe not found (.NET Framework 4.x is required)"
  }
  Info "compiler: $csc"

  & $csc /nologo /target:exe /platform:x64 /optimize+ /out:$ExePath $SrcFile
  if ($LASTEXITCODE -ne 0) { throw "compile failed (exit $LASTEXITCODE)" }
  Ok ("built " + $ExePath + " (" + (Get-Item $ExePath).Length + " bytes)")
} else {
  Warn "compile skipped (-SkipCompile)"
}

# ---------------------------------------------------------------- 2. checks
Info "pre-flight checks ..."
$ini = Join-Path $RepoRoot "skin\AudioVolume\AudioVolume.ini"
$bad = Select-String -Path $ini -Pattern '[^\x00-\x7F]' -AllMatches
if ($bad) {
  throw ("AudioVolume.ini contains non-ASCII text at line " + $bad[0].LineNumber +
         " -- Rainmeter parses skin files as ANSI, CJK will render as garbage")
}
Ok "AudioVolume.ini is pure ASCII"

foreach ($lua in Get-ChildItem (Join-Path $BinDir "*.lua")) {
  $bytes = [System.IO.File]::ReadAllBytes($lua.FullName)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw ($lua.Name + " has a UTF-8 BOM, which makes Lua fail with 'unexpected symbol near ?'")
  }
}
Ok "lua scripts have no BOM"

$lines = [System.IO.File]::ReadAllLines($ini, [System.Text.Encoding]::UTF8)
$panelIdx = ($lines | Select-String -Pattern '^\[PanelBg\]' | Select-Object -First 1).LineNumber
$cardIdx  = ($lines | Select-String -Pattern '^\[S_CardBg\]' | Select-Object -First 1).LineNumber
if ($panelIdx -gt $cardIdx) {
  throw "[PanelBg] must be declared before the card meters, otherwise it covers them"
}
Ok "[PanelBg] declared before card meters"

# ---------------------------------------------------------------- 3. zip
if (-not $SkipZip) {
  Info "packaging zip ..."
  if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }
  if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

  $stage = Join-Path $env:TEMP ("av-build-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $stage | Out-Null

  Copy-Item (Join-Path $RepoRoot "skin")        (Join-Path $stage "skin") -Recurse
  Copy-Item (Join-Path $RepoRoot "install.bat") $stage
  Copy-Item (Join-Path $RepoRoot "README.md")   $stage
  Copy-Item (Join-Path $RepoRoot "LICENSE")     $stage

  # runtime artifacts must not ship
  foreach ($junk in @("level.txt", "state.txt", "level-test.txt")) {
    $p = Join-Path $stage ("skin\AudioVolume\@Resources\bin\" + $junk)
    if (Test-Path $p) { Remove-Item $p -Force }
  }

  Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $ZipPath -CompressionLevel Optimal
  Remove-Item $stage -Recurse -Force

  $kb = [math]::Round((Get-Item $ZipPath).Length / 1KB, 1)
  Ok ("packaged " + $ZipPath + " (" + $kb + " KB)")
}

# ---------------------------------------------------------------- 4. rmskin
if (Test-Path "C:\Program Files\Rainmeter\Rainmeter.exe") {
  Warn ".rmskin cannot be scripted: Rainmeter only installs packages signed by Skin Packager"
  Write-Host "        Rainmeter tray icon -> Manage -> 'Create .rmskin package...'" -ForegroundColor DarkGray
  Write-Host "        see docs/BUILD.md section 3" -ForegroundColor DarkGray
} else {
  Warn "Rainmeter not found, skipping .rmskin hint"
}

Write-Host ""
Ok "build finished"
