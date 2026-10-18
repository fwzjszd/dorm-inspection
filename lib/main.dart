// 查寝 App 入口：miuix 主题 + 全局状态注入

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_miuix/miuix.dart';

import 'pages/home_shell.dart';
import 'services/excel_service.dart';
import 'services/storage_service.dart';
import 'widgets/app_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerAppLicense();
  final StorageService storage = await StorageService.create();
  runApp(DormInspectionApp(storage: storage));
}

/// 将应用自身的 GPLv3 协议文本注册进系统的许可注册表，
/// 使设置页「开放源代码许可」页面既能看到三方依赖许可，也能看到本项目协议。
void _registerAppLicense() {
  LicenseRegistry.addLicense(() async* {
    final String license = await rootBundle.loadString('LICENSE');
    yield LicenseEntryWithLineBreaks(<String>['查寝助手'], license);
  });
}

/// 全局状态容器：任意页面通过 [AppScope.of] 获取存储 / Excel 服务与 Snackbar
class AppScope extends InheritedNotifier<StorageService> {
  const AppScope({
    super.key,
    required this.storage,
    required this.excel,
    required this.snackbar,
    required super.child,
  }) : super(notifier: storage);

  final StorageService storage;
  final ExcelService excel;
  final AppToastState snackbar;

  static AppScope of(BuildContext context) {
    final AppScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未在组件树中找到');
    return scope!;
  }
}

class DormInspectionApp extends StatelessWidget {
  DormInspectionApp({super.key, required this.storage});

  final StorageService storage;
  final ExcelService excel = ExcelService();
  final AppToastState snackbar = AppToastState();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      storage: storage,
      excel: excel,
      snackbar: snackbar,
      child: Builder(
        builder: (BuildContext context) {
          // 液态玻璃 + 深色模式锁定，不再给用户切换
          const MiuixColorSchemeMode themeMode = MiuixColorSchemeMode.dark;
          return MiuixThemeController(
            colorSchemeMode: themeMode,
            child: Builder(
              builder: (BuildContext context) {
                final MiuixThemeData themeData = MiuixTheme.of(context);
                return MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: '查寝助手',
                  // Material 组件（日期选择器等）使用中文文案
                  locale: const Locale('zh', 'CN'),
                  supportedLocales: const <Locale>[Locale('zh', 'CN')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: ThemeData(
                    useMaterial3: true,
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: themeData.colors.primary,
                      brightness: themeData.brightness,
                    ),
                    brightness: themeData.brightness,
                  ),
                  builder: (BuildContext context, Widget? child) {
                    return Stack(
                      children: <Widget>[
                        ?child,
                        AppToastHost(state: snackbar),
                      ],
                    );
                  },
                  home: const HomeShell(),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
