# 查寝助手

一款查寝工具，使用 Flutter 开发，目前支持 Android 和 Web 端。将「人员名单管理、晚归未归登记、卫生检查评分、Excel 导入导出」整合到手机里，查寝现场即可生成与学院模板格式一致的表格并分享，无需回到电脑前二次整理。

## 功能特性

- **人员库管理**：从 Excel 一键导入名单，自动识别「姓名 / 学号 / 班级 / 宿舍 / 床号 / 辅导员」等常见表头（支持关键词模糊匹配与无表头默认列序）；也可在应用内手动增删改。
- **晚归 / 未归查寝**：按批次登记异常学生（宿舍、床号、未归原因等），支持历史输入词自动补全，按学院下发模板导出 Excel 并直接分享。
- **卫生检查评分**：以寝室为单位填写卫生检查表，导出时原样填充学院下发的 Word 评分表模板（`assets/hygiene_template.docx`），不破坏原有排版。
- **本地存储、离线可用**：所有数据通过 `shared_preferences` 以 JSON 保存在本机，无需联网、无后端、不收集任何个人信息。
- **深色液态玻璃界面**：基于 [flutter_miuix](https://pub.dev/packages/flutter_miuix) 与 `BackdropFilter` 实现的液态玻璃底栏（模糊导轨 + 清晰选中药丸、弹簧阻尼动效），全局锁定深色模式。

## 技术栈

| 项 | 说明 |
|---|---|
| 框架 | Flutter / Dart 3 |
| UI | Material + flutter_miuix，自绘液态玻璃底栏（`lib/pages/home_shell.dart`） |
| 表格处理 | excel、archive（兼容 openpyxl / WPS 生成的 xlsx） |
| 文件与分享 | file_picker、path_provider、share_plus |
| 本地持久化 | shared_preferences（JSON 序列化，模型见 `lib/models.dart`） |

## 目录结构

```
lib/
├── main.dart                     # 应用入口、主题与全局状态
├── models.dart                   # 人员、查寝记录、查寝批次、卫生评分等数据模型
├── pages/
│   ├── home_shell.dart           # 主页骨架 + 液态玻璃底栏（PageView 滑动切换）
│   ├── home_page.dart            # 查寝批次列表（晚归 / 卫生两类）
│   ├── person_page.dart          # 人员库管理
│   ├── session_edit_page.dart    # 晚归批次登记与导出
│   ├── hygiene_edit_page.dart    # 卫生检查评分填写与导出
│   └── settings_page.dart        # 设置（检查人员名单等）
├── services/
│   ├── excel_service.dart        # Excel 智能导入、模板导出
│   └── storage_service.dart      # 本地数据持久化
└── widgets/                      # Toast、自动补全输入框等通用组件
assets/
└── hygiene_template.docx         # 学院卫生检查评分表模板（导出时填充）
```

## 构建与运行

前置条件：已安装 Flutter SDK（Dart SDK ^3.13.5）与 Android 工具链。

```bash
flutter pub get
flutter run                       # 连接设备或模拟器后运行
flutter build apk --release       # 产出 build/app/outputs/flutter-apk/app-release.apk
flutter analyze                   # 静态检查
```

## 数据与隐私

- 应用完全离线运行，不包含任何网络请求与统计 SDK。
- 人员名单、查寝记录仅保存在设备本地；卸载应用或清除数据即会删除。
- 仓库 **不包含** 任何真实学生数据：根目录下的本地人员表（`*.xlsx`）与截图已通过 `.gitignore` 排除。

## 开源协议

本项目基于 [GNU General Public License v3.0](LICENSE) 开源，欢迎在遵守 GPLv3 条款的前提下自由使用、修改与分发。
