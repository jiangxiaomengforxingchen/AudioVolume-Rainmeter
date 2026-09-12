# AudioVolume / mdview.ps1
# Renders a .md file to HTML and opens it in the default browser.
#
# Why this exists: Obsidian is vault-based and will not display a lone .md file, so
# double-clicking a single README only showed an empty vault. This script converts the
# Markdown to a self-contained HTML page -- no configuration, no plugins, no internet.
#
# Usage: mdview.ps1 "path\to\file.md"

param([Parameter(Mandatory=$true)][string]$Path)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Path)) {
  Write-Host "file not found: $Path"
  Read-Host "press enter to close"
  exit 1
}

# Read as UTF-8 explicitly. Windows PowerShell 5.1 defaults to the system ANSI codepage
# (GBK on Chinese Windows), which turns a UTF-8 Markdown file into mojibake such as
# "AudioVolume 鈥?Rainmeter 鎵０鍣?". Never rely on the default here.
$md = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
# strip a stray BOM if the file has one
if ($md.Length -gt 0 -and $md[0] -eq [char]0xFEFF) { $md = $md.Substring(1) }

# ---------------------------------------------------------------- escape HTML
$e = $md
$e = $e.Replace('&', '&amp;')
$e = $e.Replace('"', '&quot;')
$e = $e.Replace('<', '&lt;')
$e = $e.Replace('>', '&gt;')

# ---------------------------------------------------------------- fences
$codes = New-Object System.Collections.ArrayList
$e = [regex]::Replace($e, '(?s)```[a-zA-Z]*\r?\n(.*?)```', {
  param($m)
  [void]$codes.Add($m.Groups[1].Value)
  return "CODEBLOCKTK" + ($codes.Count - 1) + "TK"
})

# ---------------------------------------------------------------- headings
$e = [regex]::Replace($e, '(?m)^###### (.*)$', '<h6>$1</h6>')
$e = [regex]::Replace($e, '(?m)^##### (.*)$',  '<h5>$1</h5>')
$e = [regex]::Replace($e, '(?m)^#### (.*)$',   '<h4>$1</h4>')
$e = [regex]::Replace($e, '(?m)^### (.*)$',    '<h3>$1</h3>')
$e = [regex]::Replace($e, '(?m)^## (.*)$',     '<h2>$1</h2>')
$e = [regex]::Replace($e, '(?m)^# (.*)$',      '<h1>$1</h1>')

# ---------------------------------------------------------------- images, links, code, bold
$e = [regex]::Replace($e, '!\[([^\]]*)\]\(([^)]+)\)', '<img alt="$1" src="$2">')
$e = [regex]::Replace($e, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
$e = [regex]::Replace($e, '`([^`]+)`', '<code>$1</code>')
$e = [regex]::Replace($e, '\*\*([^*]+)\*\*', '<strong>$1</strong>')

# ---------------------------------------------------------------- restore fences
for ($i = 0; $i -lt $codes.Count; $i++) {
  $e = $e.Replace("CODEBLOCKTK$i" + "TK", "<pre><code>" + $codes[$i] + "</code></pre>")
}

# ---------------------------------------------------------------- block pass: tables, hr, paragraphs
$lines = $e -split "`n"
$body = New-Object System.Collections.Generic.List[string]
$inTable = $false

foreach ($raw in $lines) {
  $t = $raw.TrimEnd()

  if ($t -match '^\|.*\|$') {
    if (-not $inTable) { $body.Add('<table>'); $inTable = $true }
    if ($t -match '^\|[\s\-\|:]+\|$') { continue }   # header separator row
    $cells = $t.Trim('|') -split '\|'
    $row = '<tr>'
    foreach ($c in $cells) { $row += '<td>' + $c.Trim() + '</td>' }
    $body.Add($row + '</tr>')
    continue
  }

  if ($inTable) { $body.Add('</table>'); $inTable = $false }

  if ($t -match '^-{3,}\s*$') { $body.Add('<hr>'); continue }
  if ($t.Trim() -eq '') { $body.Add(''); continue }
  if ($t.StartsWith('<')) { $body.Add($t); continue }

  $body.Add('<p>' + $t + '</p>')
}
if ($inTable) { $body.Add('</table>') }

# ---------------------------------------------------------------- wrap in a page
$css = @(
 'body{max-width:900px;margin:40px auto;padding:0 24px;'
 'font:16px/1.75 -apple-system,"Segoe UI",Roboto,"Microsoft YaHei",sans-serif;'
 'color:#24292f;background:#ffffff}'
 'h1,h2{border-bottom:1px solid #d8dee4;padding-bottom:.3em}'
 'h1{font-size:2em;margin-top:.6em}h2{font-size:1.5em}h3{font-size:1.25em}'
 'code{background:#f6f8fa;padding:.2em .4em;border-radius:6px;'
 'font-family:Consolas,"Courier New",monospace;font-size:85%}'
 'pre{background:#f6f8fa;padding:16px;border-radius:6px;overflow:auto;line-height:1.45}'
 'pre code{background:none;padding:0}'
 'table{border-collapse:collapse;margin:16px 0;display:block;overflow:auto}'
 'th,td{border:1px solid #d0d7de;padding:6px 13px}'
 'tr:nth-child(2n){background:#f6f8fa}'
 'a{color:#0969da;text-decoration:none}a:hover{text-decoration:underline}'
 'img{max-width:100%;border:1px solid #d8dee4;border-radius:6px}'
 'hr{border:0;border-top:1px solid #d8dee4;margin:28px 0}'
 'blockquote{margin:0;padding:0 1em;color:#57606a;border-left:.25em solid #d0d7de}'
)

$head = '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">' +
        '<meta name="viewport" content="width=device-width,initial-scale=1">' +
        '<title>' + [System.IO.Path]::GetFileName($Path) + '</title>' +
        '<style>' + ($css -join '') + '</style></head><body>'

$html = $head + ($body -join "`n") + '</body></html>'

# Write the preview NEXT TO the source file: relative image paths such as
# "docs/preview.png" only resolve if the HTML lives in the same folder tree.
$outDir = Split-Path -Parent $Path
$outFile = Join-Path $outDir ([System.IO.Path]::GetFileNameWithoutExtension($Path) + '-mdview.html')

try {
  [System.IO.File]::WriteAllText($outFile, $html, (New-Object System.Text.UTF8Encoding($false)))
} catch {
  # read-only folder (e.g. a mounted archive): fall back to TEMP
  $outFile = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($Path) + '-mdview.html')
  [System.IO.File]::WriteAllText($outFile, $html, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "[note] source folder not writable, preview written to TEMP"
  Write-Host "[note] relative images will not show in this fallback location"
}

Write-Host "rendered -> $outFile"
Start-Process $outFile
