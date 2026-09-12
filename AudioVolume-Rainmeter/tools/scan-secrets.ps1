# AudioVolume / scan-secrets.ps1
# Scans the repository for credentials before you push it anywhere.
#
# ASCII only on purpose: Windows PowerShell 5.1 reads .ps1 files as ANSI.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\scan-secrets.ps1
#   powershell -ExecutionPolicy Bypass -File tools\scan-secrets.ps1 -Root . -Verbose
#
# Exit code 0 = clean, 1 = something matched (suitable for CI).

[CmdletBinding()]
param(
  [string]$Root = '',
  [string[]]$ExcludeDir = @('.git', 'dist', 'node_modules', 'build', '.vs', '.vscode'),
  [switch]$ShowBenign
)

$ErrorActionPreference = "Stop"

# $PSScriptRoot is not reliably available inside a param() default in Windows
# PowerShell 5.1 when the script is invoked with -File, so resolve it here.
if ([string]::IsNullOrWhiteSpace($Root)) {
  if ($PSScriptRoot) { $Root = Split-Path -Parent $PSScriptRoot } else { $Root = (Get-Location).Path }
}

# ---------------------------------------------------------------- patterns
# name -> regex. Keep these specific; broad patterns cause noise.
$Patterns = [ordered]@{
  'OpenAI key'          = 'sk-[A-Za-z0-9_\-]{20,}'
  'Anthropic key'       = 'sk-ant-[A-Za-z0-9_\-]{20,}'
  'GitHub token'        = 'gh[pousr]_[A-Za-z0-9]{30,}'
  'GitHub fine-grained' = 'github_pat_[A-Za-z0-9_]{30,}'
  'AWS access key'      = 'AKIA[0-9A-Z]{16}'
  'Google API key'      = 'AIza[0-9A-Za-z_\-]{30,}'
  'Slack token'         = 'xox[baprs]-[A-Za-z0-9\-]{12,}'
  'Stripe key'          = 'sk_(live|test)_[A-Za-z0-9]{20,}'
  'Private key block'   = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'Bearer header'       = '(?i)authorization\s*:\s*bearer\s+\S{12,}'
  'Generic secret'      = '(?i)(api[_-]?key|apikey|secret[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)\s*[:=]\s*["'']?[A-Za-z0-9_\-]{16,}'
  'Password literal'    = '(?i)\b(password|passwd|pwd)\s*[:=]\s*["''][^"'']{6,}["'']'
  'URI with creds'      = '[a-z][a-z0-9+.\-]*://[^/\s:@]+:[^/\s@]+@[^\s]+'
  'JWT'                 = 'eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'
}

# ---------------------------------------------------------------- collect files
$rootFull = (Resolve-Path $Root).Path
$all = Get-ChildItem $rootFull -Recurse -File -Force -ErrorAction SilentlyContinue
$files = $all | Where-Object {
  $rel = $_.FullName.Substring($rootFull.Length).TrimStart('\', '/')
  $skip = $false
  foreach ($d in $ExcludeDir) {
    if ($rel -eq $d -or $rel.StartsWith($d + '\') -or $rel.StartsWith($d + '/')) { $skip = $true; break }
  }
  -not $skip
}

Write-Host "[scan] root     : $rootFull"
Write-Host "[scan] files    : $(($files | Measure-Object).Count)"
Write-Host "[scan] excluding: $($ExcludeDir -join ', ')"
Write-Host ""

# binary-ish extensions whose raw text we still read, but matches are reported
$textExt = @('.txt','.md','.ini','.lua','.ps1','.bat','.cmd','.vbs','.cs','.js','.ts','.json','.yml','.yaml','.xml','.config','.inc','.gitignore','.gitattributes','.php','.py','.sh','.psm1','.psd1')

$findings = New-Object System.Collections.ArrayList

foreach ($f in $files) {
  $ext = $f.Extension.ToLowerInvariant()
  $isText = ($textExt -contains $ext) -or ($f.Name -like '.*' -and $f.Extension -eq '')
  $readAsText = $isText -or $f.Length -lt 4MB   # small binaries too (exe strings can hide keys)

  try {
    $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  } catch {
    continue
  }

  # for binaries, also pull UTF-16 strings (Windows resources are often UTF-16)
  $extra = ''
  if (-not $isText) {
    try {
      $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
      $extra = [System.Text.Encoding]::Unicode.GetString($bytes)
    } catch { }
  }

  foreach ($name in $Patterns.Keys) {
    $rx = $Patterns[$name]
    foreach ($hay in @($txt, $extra)) {
      if ([string]::IsNullOrEmpty($hay)) { continue }
      foreach ($m in [regex]::Matches($hay, $rx)) {
        $snippet = $m.Value
        if ($snippet.Length > 60) { $snippet = $snippet.Substring(0, 60) + '...' }
        # mask the middle so the report itself is not a leak
        if ($snippet.Length -gt 16) {
          $snippet = $snippet.Substring(0, 6) + '***' + $snippet.Substring($snippet.Length - 6)
        }
        [void]$findings.Add([pscustomobject]@{
          File    = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/')
          Rule    = $name
          Preview = $snippet
        })
      }
    }
  }
}

# ---------------------------------------------------------------- report
if ($findings.Count -eq 0) {
  Write-Host "  no credentials found" -ForegroundColor Green
  Write-Host ""
  Write-Host "Note: this is a pattern scan. It cannot prove the absence of every secret." -ForegroundColor DarkGray
  Write-Host "      Anything you typed into a chat with an AI assistant is worth re-checking by eye." -ForegroundColor DarkGray
  exit 0
}

Write-Host "$($findings.Count) potential secret(s):" -ForegroundColor Red
foreach ($g in $findings | Group-Object File) {
  Write-Host ""
  Write-Host "  $($g.Name)" -ForegroundColor Yellow
  $g.Group | Select-Object -Unique Rule, Preview | ForEach-Object {
    Write-Host "      [$($_.Rule)]  $($_.Preview)"
  }
}
Write-Host ""
Write-Host "Before pushing:" -ForegroundColor Cyan
Write-Host "  1. delete the value and load it from an environment variable instead"
Write-Host "  2. if it was ever committed, rotate (revoke) the key -- history keeps it forever"
Write-Host "  3. enable GitHub secret scanning on the repository"
exit 1
