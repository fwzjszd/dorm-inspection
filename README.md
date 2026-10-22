# 查寝助手 · 网页版（PWA）分支

> ⚠️ **本分支为实验性的网页版（Flutter Web / PWA）改造，尚未经过充分测试，不保证稳定性与功能完整性。**
> 数据结构、导入导出兼容性、iOS Safari 上的实际表现等均可能存在问题，请自行承担使用风险。
> 稳定的 Android 原生版本请见 `main` 分支。

本分支把「查寝助手」改造为可安装的网页应用（PWA），主要目的是让 **iOS 用户无需 App Store / 无需开发者证书** 即可使用：用 iPhone 自带的 Safari 打开网页，「添加到主屏幕」后像普通 App 一样全屏运行。

- 在线 / 安装地址：<https://fwzjszd.github.io/dorm-inspection/>
- 数据全部保存在**当前浏览器本地**（Flutter Web 的 shared_preferences 走浏览器本地存储），无后端、不上传、不收集任何信息。
- 首次打开并加载完成后，Service Worker 会缓存全部资源，**此后断网也能打开**。
- **零第三方 CDN**：CanvasKit 与中文回落字体均同源托管，加载与离线使用不依赖 Google 字体等外部服务（在网络受限环境下也能正常出界面）。

## 在 iPhone / iPad 上安装使用

1. 用系统自带的 **Safari** 打开 <https://fwzjszd.github.io/dorm-inspection/>（必须是 Safari，Chrome 等第三方浏览器不支持「添加到主屏幕」全屏安装）。
2. 等待页面加载完毕（首次需下载约数 MB 资源）。
3. 点底部工具栏的「分享」按钮（方框向上箭头）→ 选择「**添加到主屏幕**」→ 右上角「添加」。
4. 回到桌面，点开名为「查寝助手」的图标，即可全屏使用；首次加载成功后支持离线打开。

> 注意：网页版的数据只存在于**这一台设备的这一个浏览器**里，清除 Safari 数据或卸载图标会丢失数据，且不会与 Android 版自动同步。请及时使用「导出」功能备份。

## 与 Android 版的差异

| 方面 | 说明 |
|---|---|
| 文件导入 | 通过浏览器文件选择器选取 Excel / Word，不再访问设备文件目录。 |
| 文件导出 | 浏览器环境下以下载 / 系统分享（Web Share，受 Safari 支持程度影响）方式保存文件。 |
| 数据存储 | 保存在浏览器本地，与原生 App 存储相互独立。 |
| 渲染 | 使用 Flutter Web 的 CanvasKit 渲染器，字体与 CanvasKit 已同源托管。 |
| 打包分发 | 无需发包，推送 `web-pwa` 分支即由 GitHub Actions 自动构建并发布到 GitHub Pages。 |

## 自动部署

推送到 `web-pwa` 分支会触发 [.github/workflows/web-deploy.yml](.github/workflows/web-deploy.yml)：

1. `flutter build web --release --base-href /dorm-inspection/ --no-web-resources-cdn`（CanvasKit 同源）；
2. `tool/patch_bootstrap.ps1`：把回落字体基址 `fontFallbackBaseUrl` 指向同源 `fonts/s/`；
3. `tool/inject_sw_manifest.ps1`：枚举 `build/web` 全部产物注入 Service Worker 预缓存清单；
4. 上传并部署到 GitHub Pages。

> 仓库需先在 **Settings → Pages → Build and deployment → Source** 选择 **GitHub Actions**。

## 本地构建与预览

前置：Flutter 3.47.x（Dart 3.13）。

```bash
flutter pub get

# 构建（Windows PowerShell）
flutter build web --release --base-href /dorm-inspection/ --no-web-resources-cdn
powershell -ExecutionPolicy Bypass -File tool/patch_bootstrap.ps1
powershell -ExecutionPolicy Bypass -File tool/inject_sw_manifest.ps1

# 本地静态预览（需带 /dorm-inspection/ 前缀，可用任意静态服务器指向 build/web）
```

## 数据与隐私

- 网页版完全离线运行，除首次加载同源静态资源外不发起第三方网络请求。
- 人员名单、查寝记录仅保存在当前浏览器本地；清除浏览器数据即会删除。
- 仓库不包含任何真实学生数据。

## 开源协议

本项目基于 [GNU General Public License v3.0](LICENSE) 开源。
