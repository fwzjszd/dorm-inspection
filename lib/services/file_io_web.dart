// Web 平台（含 iOS Safari / 添加到主屏幕的 PWA）的文件输出实现：
// 优先用 Web Share API 调起系统分享（可直接发微信 / 存「文件」），
// 不支持分享文件时退化为浏览器下载（Safari 会存入「下载项」/「文件」App）。

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_io.dart';

/// 触发分享或下载。
Future<void> saveOrShareFile(ExportedFile file) async {
  final JSUint8Array data = Uint8List.fromList(file.bytes).toJS;
  final web.Blob blob = web.Blob(<JSUint8Array>[data].toJS);

  // 系统级分享（iOS Safari 12.2+ 支持分享文件；桌面 Chromium 支持）
  final web.Navigator nav = web.window.navigator;
  final web.ShareData shareData = web.ShareData(
    files: <web.File>[web.File(<web.Blob>[blob].toJS, file.name)].toJS,
  );
  bool shared = false;
  // 部分浏览器（如旧版 WebView / 桌面 Firefox）没有 canShare 方法，
  // 直接调用会抛 NoSuchMethodError，这里先探测再调用。
  if (nav.has('canShare') && nav.has('share')) {
    try {
      if (nav.canShare(shareData)) {
        await nav.share(shareData).toDart;
        shared = true;
      }
    } catch (_) {
      // 用户取消或分享失败时退回下载。
      shared = false;
    }
  }

  if (!shared) {
    final String url = web.URL.createObjectURL(blob);
    final web.HTMLAnchorElement anchor =
        web.document.createElement('a') as web.HTMLAnchorElement
          ..href = url
          ..download = file.name
          ..style.display = 'none';
    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    // 延迟释放对象 URL，保证浏览器已开始读取。
    Future<void>.delayed(const Duration(seconds: 10), () {
      web.URL.revokeObjectURL(url);
    });
  }
}
