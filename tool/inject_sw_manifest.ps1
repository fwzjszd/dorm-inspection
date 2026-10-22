# 在 flutter build web 之后运行：
# 枚举 build\web 下全部产物，将相对路径列表注入 build\web\service_worker.js
# 的 PRECACHE_URLS 常量，使 PWA 安装时即可完整离线缓存（含 CanvasKit、
# 同源回落字体、main.dart.js 与全部资源）。
#
# CanvasKit 经 --no-web-resources-cdn 同源托管；回落字体基址由
# tool/patch_bootstrap.ps1 构建后补丁指向同源 fonts/s/（零第三方 CDN）。
param(
  [string]$WebDir = (Join-Path $PSScriptRoot '..\build\web')
)

$ErrorActionPreference = 'Stop'
$WebDir = (Resolve-Path $WebDir).Path
$swPath = Join-Path $WebDir 'service_worker.js'

if (-not (Test-Path $swPath)) {
  throw "service_worker.js not found in $WebDir"
}

$files = Get-ChildItem -Path $WebDir -Recurse -File
$urls = New-Object System.Collections.Generic.List[string]
$urls.Add('./') | Out-Null
foreach ($f in $files) {
  $rel = $f.FullName.Substring($WebDir.Length).Replace('\', '/').TrimStart('/')
  if ($rel -eq 'service_worker.js') { continue }
  $urls.Add("./$rel") | Out-Null
}

# 用 JSON 序列化保证路径里的特殊字符被正确转义
$json = ($urls | Sort-Object | ConvertTo-Json -Compress)
if ($urls.Count -eq 1) { $json = "[$json]" }

$content = Get-Content $swPath -Raw -Encoding UTF8
$pattern = '(?s)const PRECACHE_URLS = \[.*?\];'
$replacement = 'const PRECACHE_URLS = ' + $json + ';'
$updated = [regex]::Replace($content, $pattern, { param($m) $replacement })

if ($updated -eq $content) {
  throw 'PRECACHE_URLS placeholder not found in service_worker.js'
}

[System.IO.File]::WriteAllText($swPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Injected $($urls.Count) precache URLs into service_worker.js"
