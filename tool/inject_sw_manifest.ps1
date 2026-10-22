# 在 flutter build web 之后运行：
# 枚举 build\web 下全部产物，将相对路径列表注入 build\web\service_worker.js
# 的 PRECACHE_URLS 常量，使 PWA 安装时即可完整离线缓存（含 CanvasKit、
# 同源回落字体、main.dart.js 与全部资源）。
#
# CanvasKit 经 --no-web-resources-cdn 同源托管；回落字体基址由
# tool/patch_bootstrap.ps1 构建后补丁指向同源 fonts/s/（零第三方 CDN）。
param(
  [string]$WebDir = (Join-Path $PSScriptRoot '..\build\web'),
  # 每次部署唯一的缓存版本标识（CI 传 commit SHA）。
  # 必须随构建产物变化，否则浏览器逐字节比对认为 SW 未更新，会一直返回旧缓存。
  [string]$CacheStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
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

# 注入随本次部署变化的缓存版本号，强制浏览器识别到新 SW 并清理旧缓存
$cachePattern = "const CACHE_VERSION = '[^']*';"
$cacheReplacement = "const CACHE_VERSION = 'dorm-inspection-$CacheStamp';"
$updated = [regex]::Replace($updated, $cachePattern, { param($m) $cacheReplacement })

[System.IO.File]::WriteAllText($swPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Injected $($urls.Count) precache URLs, CACHE_VERSION=dorm-inspection-$CacheStamp"
