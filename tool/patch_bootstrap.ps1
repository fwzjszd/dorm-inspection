# 在 flutter build web --no-web-resources-cdn 之后运行：
# 补丁 build\web\flutter_bootstrap.js 的引擎引导调用，把 CanvasKit 文本整形
# 所需的回落字体基址 fontFallbackBaseUrl 指向同源的 fonts/s/（其目录结构与
# https://fonts.gstatic.com/s/ 一致，字体已随 web/fonts 一并托管）。
#
# 背景：--no-web-resources-cdn 只会把 CanvasKit 本地化（useLocalCanvasKit:true），
# 但 Flutter 没有为回落字体提供构建期开关，默认仍请求 https://fonts.gstatic.com/s/。
# 本脚本通过官方 loader 的 onEntrypointLoaded -> initializeEngine 注入同源基址，
# 从而实现零第三方 CDN、可完全离线。幂等，可重复执行。
param(
  [string]$WebDir = (Join-Path $PSScriptRoot '..\build\web')
)

$ErrorActionPreference = 'Stop'
$WebDir = (Resolve-Path $WebDir).Path
$bootstrapPath = Join-Path $WebDir 'flutter_bootstrap.js'

if (-not (Test-Path $bootstrapPath)) {
  throw "flutter_bootstrap.js not found in $WebDir (run 'flutter build web' first)"
}

$content = [System.IO.File]::ReadAllText($bootstrapPath)

if ($content -match 'fontFallbackBaseUrl') {
  Write-Host 'flutter_bootstrap.js already patched, skipped.'
  exit 0
}

$fontsDir = Join-Path $WebDir 'fonts\s'
if (-not (Test-Path $fontsDir)) {
  Write-Warning "fonts/s directory not found under $WebDir; fallback fonts may 404."
}

# 仅替换构建产物末尾默认生成的那次 _flutter.loader.load({...}) 调用。
# 不传 serviceWorkerSettings：内置 flutter_service_worker 已弃用，
# PWA 的 service_worker.js 由 index.html 负责注册。
$pattern = '(?s)_flutter\.loader\.load\(\{.*?\}\);'
$replacement = @'
_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    var appRunner = await engineInitializer.initializeEngine({
      fontFallbackBaseUrl: new URL('fonts/s/', document.baseURI).href
    });
    await appRunner.runApp();
  }
});
'@

$updated = [regex]::Replace($content, $pattern, { param($m) $replacement })

if ($updated -eq $content) {
  throw 'Default _flutter.loader.load({...}) call not found in flutter_bootstrap.js'
}

[System.IO.File]::WriteAllText($bootstrapPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'Patched flutter_bootstrap.js: fontFallbackBaseUrl -> same-origin fonts/s/'
