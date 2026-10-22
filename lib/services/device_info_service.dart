// 跨平台设备信息读取：关于页显示的设备型号与系统版本
// 原生端走 device_info_plus 原生字段，Web 端解析浏览器 UA。
//
// Web 平台选择 device_info_service_web.dart，其余选择 _io.dart。
export 'device_info_service_io.dart'
    if (dart.library.js_interop) 'device_info_service_web.dart';

class DeviceSummary {
  const DeviceSummary(this.model, this.system);

  /// 设备型号，如「HUAWEI JEF-AN00」「iPhone 15 Pro」
  final String model;

  /// 系统版本，如「Android 13 (API 33)」「iOS 18.1」
  final String system;
}
