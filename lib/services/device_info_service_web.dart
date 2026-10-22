// Web 平台设备信息实现：浏览器不提供原生机型信息，只能解析 User-Agent。
// iOS Safari 的 UA 自 iOS 12.2 起只含「iPhone」与系统大版本，无法拿到具体机型。

import 'package:web/web.dart' as web;

import 'device_info_service.dart';

/// 从 iOS UA（如 `... CPU iPhone OS 17_5_1 like Mac OS X ...`）提取系统版本
String? _iosVersion(String ua) {
  final Match? m = RegExp(r'(?:iPhone|iPad) OS (\d+)(?:_(\d+))?(?:_(\d+))?')
      .firstMatch(ua);
  if (m == null) return null;
  final String major = m.group(1)!;
  final String? minor = m.group(2);
  final String? patch = m.group(3);
  return <String?>[major, minor, patch]
      .whereType<String>()
      .where((String v) => v.isNotEmpty)
      .join('.');
}

Future<DeviceSummary> readDeviceSummary() async {
  final String ua = web.window.navigator.userAgent;
  final bool isTablet = RegExp(r'ipad', caseSensitive: false).hasMatch(ua) ||
      // iPadOS 13+ 桌面化 UA：Mac + 触屏
      (RegExp(r'Macintosh').hasMatch(ua) &&
          web.window.navigator.maxTouchPoints > 1);

  if (RegExp(r'iphone|ipad', caseSensitive: false).hasMatch(ua) || isTablet) {
    final String? ver = _iosVersion(ua);
    return DeviceSummary(
      isTablet ? 'iPad（网页版）' : 'iPhone（网页版）',
      ver != null ? 'iOS $ver' : 'iOS（网页版）',
    );
  }

  final Match? android = RegExp(r'Android (\d+(?:\.\d+)*)').firstMatch(ua);
  if (android != null) {
    final String? model =
        RegExp(r'; ([^;)]+) Build/').firstMatch(ua)?.group(1)?.trim();
    return DeviceSummary(
      model != null && model.isNotEmpty ? '$model（网页版）' : 'Android（网页版）',
      'Android ${android.group(1)}（网页版）',
    );
  }

  if (RegExp(r'Mac OS X').hasMatch(ua)) {
    return const DeviceSummary('Mac（网页版）', 'macOS（网页版）');
  }
  if (RegExp(r'Windows').hasMatch(ua)) {
    return const DeviceSummary('Windows PC（网页版）', 'Windows（网页版）');
  }
  return const DeviceSummary('网页浏览器', 'Web');
}
