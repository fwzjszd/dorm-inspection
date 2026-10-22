// Android 应用内更新检测：读取 GitHub Releases 最新发布，与当前版本比较，
// 下载其中的 APK 资产并拉起系统安装器。
//
// 仅在 Android 端使用（关于页「检查更新」入口只在 Android 显示），
// 网络访问使用 dart:io 自带的 HttpClient，不引入额外网络库。

import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// 一次 GitHub Release 中与更新相关的信息。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
    required this.htmlUrl,
    required this.publishedAt,
  });

  /// 发布版本标签，如 V20261021.01 / v1.0.2
  final String version;

  /// 更新说明（Release body）
  final String releaseNotes;

  /// APK 下载直链
  final String apkUrl;

  /// APK 文件名
  final String apkName;

  /// APK 字节大小，未知时为 0
  final int apkSize;

  /// Release 网页地址（无 APK 资产时引导浏览器打开）
  final String htmlUrl;

  /// 发布时间（UTC）
  final DateTime? publishedAt;
}

class UpdateResult {
  const UpdateResult({required this.hasUpdate, this.info});

  final bool hasUpdate;
  final UpdateInfo? info;
}

class UpdateException implements Exception {
  UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UpdateService {
  const UpdateService._();

  static const String _apiUrl =
      'https://api.github.com/repos/fwzjszd/dorm-inspection/releases/latest';

  static HttpClient _client() {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'dorm-inspection-app';
  }

  /// 查询最新 Release；仓库尚未发布任何 Release（404）时返回 null。
  static Future<UpdateInfo?> fetchLatestRelease() async {
    final HttpClient client = _client();
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(_apiUrl));
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode == HttpStatus.notFound) {
        return null;
      }
      if (resp.statusCode != HttpStatus.ok) {
        throw UpdateException('服务响应异常（${resp.statusCode}）');
      }
      final String body = await resp.transform(utf8.decoder).join();
      final dynamic json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        throw UpdateException('服务返回内容无法解析');
      }
      return _parseRelease(json);
    } on SocketException {
      throw UpdateException('网络连接失败，请检查网络后重试');
    } on HttpException {
      throw UpdateException('网络请求失败，请稍后重试');
    } finally {
      client.close(force: true);
    }
  }

  static UpdateInfo? _parseRelease(Map<String, dynamic> json) {
    final dynamic tagNode = json['tag_name'];
    final dynamic assetsNode = json['assets'];
    if (tagNode is! String || assetsNode is! List) {
      return null;
    }
    Map<String, dynamic>? apk;
    for (final dynamic asset in assetsNode) {
      if (asset is Map<String, dynamic> &&
          asset['name'] is String &&
          (asset['name'] as String).toLowerCase().endsWith('.apk')) {
        apk = asset;
        break;
      }
    }
    if (apk == null) {
      return null;
    }
    final dynamic urlNode = apk['browser_download_url'];
    if (urlNode is! String) {
      return null;
    }
    DateTime? publishedAt;
    final dynamic dateNode = json['published_at'];
    if (dateNode is String) {
      publishedAt = DateTime.tryParse(dateNode)?.toLocal();
    }
    return UpdateInfo(
      version: tagNode,
      releaseNotes: (json['body'] as String?)?.trim() ?? '',
      apkUrl: urlNode,
      apkName: apk['name'] as String,
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
      htmlUrl: (json['html_url'] as String?) ?? '',
      publishedAt: publishedAt,
    );
  }

  /// 比较发布版本与当前版本：发布版本更新返回 true。
  /// 兼容 V20261021.01、v1.0.2、1.0.1+4 等写法，逐段按数值比较，
  /// 无法解析为数字的段落退化为字符串比较。
  static bool isNewer(String remoteVersion, String currentVersion) {
    return _compareVersions(
          _normalize(remoteVersion),
          _normalize(currentVersion),
        ) >
        0;
  }

  static String _normalize(String version) {
    String v = version.trim();
    if (v.toLowerCase().startsWith('v')) {
      v = v.substring(1);
    }
    // pubspec 构建号 1.0.1+4 中 + 之后不参与版本新旧比较
    final int plus = v.indexOf('+');
    if (plus >= 0) {
      v = v.substring(0, plus);
    }
    return v;
  }

  static int _compareVersions(String a, String b) {
    final List<String> sa = a.split(RegExp(r'[.\-_]'));
    final List<String> sb = b.split(RegExp(r'[.\-_]'));
    final int len = sa.length > sb.length ? sa.length : sb.length;
    for (int i = 0; i < len; i++) {
      final String pa = i < sa.length ? sa[i] : '0';
      final String pb = i < sb.length ? sb[i] : '0';
      final int? na = int.tryParse(pa);
      final int? nb = int.tryParse(pb);
      int cmp;
      if (na != null && nb != null) {
        cmp = na.compareTo(nb);
      } else {
        cmp = pa.compareTo(pb);
      }
      if (cmp != 0) {
        return cmp;
      }
    }
    return 0;
  }

  /// 综合检查：当前版本 [currentVersion] 为空（debug 包）时一律视为可更新。
  static Future<UpdateResult> checkForUpdate(String currentVersion) async {
    final UpdateInfo? info = await fetchLatestRelease();
    if (info == null) {
      throw UpdateException('最新发布中未找到 Android 安装包');
    }
    if (currentVersion.isEmpty) {
      return UpdateResult(hasUpdate: true, info: info);
    }
    return UpdateResult(
      hasUpdate: isNewer(info.version, currentVersion),
      info: info,
    );
  }

  /// 下载时统一使用的固定文件名（不带版本号），避免每个版本各留一份安装包。
  static const String _apkFileName = 'dorm-inspection-update.apk';

  /// 更新安装包的存放目录：优先外部应用专属文件目录（系统安装器可直接读取，
  /// 无需文件共享配置），不可用时回退内部缓存目录。
  static Future<Directory> _downloadsDirectory() async {
    // getExternalStorageDirectory 在非 Android 平台返回 null（其 Future 本身也可空）。
    final Directory? external = await getExternalStorageDirectory();
    return external ?? await getTemporaryDirectory();
  }

  /// 清理更新下载目录中残留的安装包：删除所有 .apk 文件（保留其它文件）。
  /// 安装包体量大（约 58MB/份），安装完成后系统不会自动删除来源 APK，
  /// 若不清理，历次版本会一直计入系统设置中的「用户数据」。
  static Future<void> cleanupDownloadedApks() async {
    final Directory dir = await _downloadsDirectory();
    try {
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
          try {
            await entity.delete();
          } catch (_) {
            // 安装器仍占用等情况下跳过，下次启动或再次清理时删除。
          }
        }
      }
    } catch (_) {
      // 目录尚不存在等情况无需处理。
    }
  }

  /// 统计更新下载目录中残留 APK 的字节数，供设置页「清除缓存」展示。
  static Future<int> leftoverApkBytes() async {
    int total = 0;
    final Directory dir = await _downloadsDirectory();
    try {
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// 下载 APK 到应用专属目录，[onProgress] 回调 0~1 的进度。
  ///
  /// 使用不带版本号的固定文件名，下载前先删除历史版本残留的安装包，
  /// 保证任意时刻最多只有一份 APK。固定文件名不做跨进程断点续传
  /// （旧版本的部分文件追加到新版本会导致安装包损坏），下载失败重新全量下载。
  static Future<File> downloadApk(
    UpdateInfo info, {
    required void Function(double progress) onProgress,
  }) async {
    final Directory dir = await _downloadsDirectory();
    // 删除历次版本（含本版本）残留的所有 APK，防止多版本堆积与脏续传。
    await cleanupDownloadedApks();
    final File file = File('${dir.path}/$_apkFileName');

    final HttpClient client = _client();
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(info.apkUrl));
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) {
        throw UpdateException('下载失败（${resp.statusCode}）');
      }
      final int total = info.apkSize > 0
          ? info.apkSize
          : (resp.contentLength > 0 ? resp.contentLength : 0);
      final IOSink sink = file.openWrite(mode: FileMode.write);
      int received = 0;
      try {
        await for (final List<int> chunk in resp) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress(received / total);
          }
        }
      } finally {
        await sink.close();
      }
      onProgress(1);
      return file;
    } on SocketException {
      throw UpdateException('下载失败：网络连接中断');
    } on HttpException {
      throw UpdateException('下载失败，请稍后重试');
    } finally {
      client.close(force: true);
    }
  }

  /// 调起系统 APK 安装界面。
  static Future<void> installApk(File file) async {
    final OpenResult result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw UpdateException(
        result.message.isNotEmpty ? '无法打开安装器：${result.message}' : '无法打开安装器',
      );
    }
  }
}
