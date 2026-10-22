import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 统计应用临时目录占用字节数；个别文件不可读时忽略。
Future<int> calculateCacheBytes() async {
  final Directory dir = await getTemporaryDirectory();
  int total = 0;
  try {
    await for (final FileSystemEntity entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
  } catch (_) {
    // 临时目录下个别文件不可读时忽略，按已统计部分计。
  }
  return total;
}

/// 清空应用临时目录（导出用的临时表格等），不触碰持久数据。
Future<void> clearCache() async {
  final Directory dir = await getTemporaryDirectory();
  await for (final FileSystemEntity entity in dir.list()) {
    try {
      await entity.delete(recursive: true);
    } catch (_) {
      // 被占用或无权限的文件跳过。
    }
  }
}
