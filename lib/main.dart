// 查寝 App 入口：miuix 主题 + 全局状态注入

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_miuix/miuix.dart';

import 'dart:async';
import 'dart:io' show Platform;

import 'pages/home_shell.dart';
import 'services/excel_service.dart';
import 'services/storage_service.dart';
import 'services/update_service.dart';
import 'widgets/app_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerAppLicense();
  // Android 端后台清理应用内更新残留的旧安装包（每份约 58MB，
  // 系统安装完成后不会自动删除来源 APK）。不 await，避免影响启动速度。
  if (Platform.isAndroid) {
    unawaited(UpdateService.cleanupDownloadedApks());
  }
  // 不再在此 await 存储加载：数据量大时 jsonDecode 会把首帧阻塞数百毫秒，
  // 表现为点开应用长时间黑屏 / 卡死。先挂闪屏，加载在首帧之后进行。
  runApp(const AppBoot());
}

/// 启动门：立即显示轻量闪屏，存储服务（SharedPreferences + 数据解析）
/// 在首帧渲染后于后台完成，就绪后无缝切换到主应用。
class AppBoot extends StatefulWidget {
  const AppBoot({super.key});

  @override
  State<AppBoot> createState() => _AppBootState();
}

class _AppBootState extends State<AppBoot> {
  StorageService? _storage;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final StorageService storage = await StorageService.create();
      if (!mounted) return;
      setState(() => _storage = storage);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final StorageService? storage = _storage;
    if (storage != null) {
      return DormInspectionApp(storage: storage);
    }
    // 默认深色闪屏（与应用默认主题一致），无玻璃 / 无列表，构建开销极小
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF101216),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '查寝助手',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    '本地数据加载失败：$_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
          // 用户主题选择：跟随系统 / 日间 / 夜间
          final StorageService storage = AppScope.of(context).storage;
          final MiuixColorSchemeMode themeMode = storage.darkMode == null
              ? MiuixColorSchemeMode.system
              : storage.darkMode == true
              ? MiuixColorSchemeMode.dark
              : MiuixColorSchemeMode.light;
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
