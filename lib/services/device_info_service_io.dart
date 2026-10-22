// 原生平台（Android / iOS / 桌面）设备信息实现。

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'device_info_service.dart';

Future<DeviceSummary> readDeviceSummary() async {
  final DeviceInfoPlugin plugin = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    final AndroidDeviceInfo info = await plugin.androidInfo;
    return DeviceSummary(
      '${info.manufacturer} ${info.model}',
      'Android ${info.version.release} (API ${info.version.sdkInt})',
    );
  }
  if (Platform.isIOS) {
    final IosDeviceInfo info = await plugin.iosInfo;
    return DeviceSummary(
      info.utsname.machine,
      '${info.systemName} ${info.systemVersion}',
    );
  }
  return DeviceSummary(
    Platform.operatingSystem,
    Platform.operatingSystemVersion,
  );
}
