// 跨平台设备信息读取：关于页显示的设备型号与系统版本
// Android / iOS 走 device_info_plus 原生字段，其余平台回退到 dart:io。

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceSummary {
  const DeviceSummary(this.model, this.system);

  /// 设备型号，如「HUAWEI JEF-AN00」「iPhone 15 Pro」
  final String model;

  /// 系统版本，如「Android 13 (API 33)」「iOS 18.1」
  final String system;
}

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
