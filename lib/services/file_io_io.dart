// 原生平台（Android / iOS / 桌面）的文件输出实现：
// 写入临时目录后调起系统分享面板。

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_io.dart';

/// 写出文件并调起系统分享。
Future<void> saveOrShareFile(ExportedFile file) async {
  final Directory outDir = await getTemporaryDirectory();
  final File outFile = File(p.join(outDir.path, file.name));
  await outFile.writeAsBytes(file.bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(files: <XFile>[XFile(outFile.path)]),
  );
}
