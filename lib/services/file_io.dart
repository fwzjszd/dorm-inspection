// 跨平台文件输出：原生端写临时文件并调起系统分享，
// Web 端（含 iOS Safari/PWA）直接触发浏览器下载或系统分享面板。
//
// Web 平台选择 file_io_web.dart，其余平台选择 file_io_io.dart。
export 'file_io_io.dart' if (dart.library.js_interop) 'file_io_web.dart';

/// 导出结果：文件名 + 字节内容，由平台实现负责落盘 / 分享 / 下载。
class ExportedFile {
  const ExportedFile(this.name, this.bytes);

  final String name;
  final List<int> bytes;
}
