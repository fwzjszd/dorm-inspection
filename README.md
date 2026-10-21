# 查寝助手 · iOS 版

> ## ⚠️ 重要提示：本分支未经测试，不保证稳定性
>
> 本 `ios` 分支在 Android 稳定版（[`main`](https://github.com/fwzjszd/dorm-inspection)）基础上补充了 iOS 工程与云端构建配置，但 **尚未在任何 iPhone 真机或 iOS 模拟器上完成编译、安装与功能验证**。
>
> - 不保证能够一次编译通过；
> - 不保证安装后所有功能（Excel 导入导出、文件分享、模板填充等）行为与 Android 版一致；
> - 不保证运行过程中不会崩溃或丢失数据；
> - 仅供有 Flutter / iOS 开发经验的用户尝鲜、联调与反馈问题使用，**请勿用于正式查寝工作**，日常使用请切换到 `main` 分支下载 Android 安装包。
>
> 如在使用中发现问题，欢迎在 [Issues](https://github.com/fwzjszd/dorm-inspection/issues) 反馈，并附上构建日志或崩溃信息。

一款面向高校学生干部 / 辅导员的移动端查寝工具，使用 Flutter 开发。将「人员名单管理、晚归未归登记、卫生检查评分、Excel 导入导出」整合到一部手机里，查寝现场即可生成与学院模板格式一致的表格并分享，无需回到电脑前二次整理。

## 分支说明

| 分支 | 平台 | 状态 |
|---|---|---|
| `main` | Android | 主力分支，已通过 analyze / test 与真机验证，Release 页提供可直接安装的 APK |
| `ios`（本分支） | iOS | 实验性分支，工程与 CI 已补齐但**未经测试，不保证稳定性** |

两个分支的 Dart 业务代码（`lib/`）保持一致，差异仅在平台工程与 CI 配置。

## 功能特性

- **人员库管理**：从 Excel 一键导入名单，自动识别「姓名 / 学号 / 班级 / 宿舍 / 床号 / 辅导员」等常见表头（支持关键词模糊匹配与无表头默认列序）；也可在应用内手动增删改。
- **晚归 / 未归查寝**：按批次登记异常学生（宿舍、床号、未归原因等），支持历史输入词自动补全，按学院下发模板导出 Excel 并直接分享。
- **卫生检查评分**：以寝室为单位填写卫生检查表，导出时原样填充学院下发的 Word 评分表模板（`assets/hygiene_template.docx`），不破坏原有排版。
- **本地存储、离线可用**：所有数据通过 `shared_preferences` 以 JSON 保存在本机，无需联网、无后端、不收集任何个人信息。
- **深色液态玻璃界面**：基于 [flutter_miuix](https://pub.dev/packages/flutter_miuix) 与 `BackdropFilter` 实现的液态玻璃底栏（模糊导轨 + 清晰选中药丸、弹簧阻尼动效），全局锁定深色模式。

## 技术栈

| 项 | 说明 |
|---|---|
| 框架 | Flutter 3.47.7 / Dart 3.13 |
| UI | Material + flutter_miuix，自绘液态玻璃底栏（`lib/pages/home_shell.dart`） |
| 表格处理 | excel、archive（兼容 openpyxl / WPS 生成的 xlsx） |
| 文件与分享 | file_picker、path_provider、share_plus |
| 本地持久化 | shared_preferences（JSON 序列化，模型见 `lib/models.dart`） |
| iOS 工程 | `ios/Runner.xcworkspace`，Bundle ID `com.dorminspection.dormInspection` |

## 目录结构

```
lib/
├── main.dart                     # 应用入口、主题与全局状态
├── models.dart                   # 人员、查寝记录、查寝批次、卫生评分等数据模型
├── pages/                        # 主页骨架、人员库、查寝登记、卫生评分、设置等页面
├── services/                     # Excel 智能导入导出、本地持久化、设备信息、记录合并
└── widgets/                      # Toast、自动补全输入框等通用组件
assets/
├── hygiene_template.docx         # 学院卫生检查评分表模板（导出时填充）
└── avatar、icon                  # 头像与应用图标
ios/                              # Xcode 工程（Runner / RunnerTests）
.github/workflows/ios-build.yml   # iOS 云端构建工作流（macos-15，无需本地 Mac）
```

## 构建与运行

### 方式一：GitHub Actions 云端构建（无需 Mac）

仓库已内置 [ios-build.yml](.github/workflows/ios-build.yml)，在仓库 **Actions → iOS Build → Run workflow** 手动触发，可选三种分发方式：

- `adhoc`（默认）：Ad Hoc 签名，产出可直接安装到已登记设备的 ipa；
- `testflight`：签名并上传 TestFlight；
- `none`：仅编译验证，产出未签名 ipa，**不需要任何密钥**，适合先验证代码能否编译通过。

使用签名构建前，需在仓库 **Settings → Secrets and variables → Actions** 配置：

| Secret | 说明 |
|---|---|
| `IOS_TEAM_ID` | Apple Developer Team ID（10 位） |
| `BUILD_CERTIFICATE_BASE64` | Distribution 证书 `.p12` 的 Base64 |
| `P12_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `PROVISIONING_PROFILE_BASE64` | 描述文件 `.mobileprovision` 的 Base64 |
| `APP_STORE_CONNECT_KEY_ID` 等 3 项 | 仅 `testflight` 方式需要 |

> 描述文件对应的 Bundle ID 必须为 `com.dorminspection.dormInspection`。构建产物在本次运行页面底部的 Artifacts 下载（保留 30 天）。

### 方式二：本地构建（需 macOS + Xcode）

```bash
flutter pub get
flutter analyze
flutter run                  # 连接 iOS 真机或模拟器后运行
flutter build ipa --release  # 产出 build/ios/ipa 下的 ipa
```

安装到真机还需在 Xcode 中配置有效的签名团队（Signing & Capabilities）。

## iOS 端待验证的已知风险

以下环节在 Android 上工作正常，但 iOS 行为存在差异，**均尚未实测**：

- **文件选择器**：`file_picker` 选取 Excel / Word 文件时的权限与 iCloud 文档选择器行为；
- **文件分享与保存**：`share_plus`、`path_provider` 导出 xlsx / docx 后的分享面板与目标 App 兼容性；
- **模板填充**：卫生评分 Word 模板（docx）在 iOS 上的路径读取与导出；
- **字体与渲染**：液态玻璃模糊效果、深色模式在不同机型上的性能表现。

## 数据与隐私

- 应用完全离线运行，不包含任何网络请求与统计 SDK。
- 人员名单、查寝记录仅保存在设备本地；卸载应用或清除数据即会删除。
- 仓库 **不包含** 任何真实学生数据：本地人员表（`*.xlsx`）与截图已通过 `.gitignore` 排除。

## 开源协议

本项目基于 [GNU General Public License v3.0](LICENSE) 开源，欢迎在遵守 GPLv3 条款的前提下自由使用、修改与分发。
