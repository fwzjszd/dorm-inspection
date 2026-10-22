// 设置页：复刻 BiliMax 的卡片式设置行（18dp 圆角卡 + 26dp 蓝色图标）

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/device_info_service.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/common.dart';
import 'person_page.dart';

/// 设置行图标统一使用的强调蓝（BiliMax StateAccent）
const Color _kAccent = Color(0xFF3B82F6);

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final StorageService storage = AppScope.of(context).storage;

    return MiuixScaffold(
      topBar: const MiuixTopAppBar(title: '设置', largeTitle: '设置'),
      content: (EdgeInsets padding) {
        return MiuixPageContent(
          child: ListView(
            padding: padding.add(const EdgeInsets.only(bottom: 96)),
            children: <Widget>[
              const _DarkModeCard(),
              const _GroupHeader('数据'),
              _PersonLibraryRow(count: storage.persons.length),
              const SizedBox(height: 12),
              const _BackupExportRow(),
              const SizedBox(height: 12),
              const _BackupRestoreRow(),
              const SizedBox(height: 12),
              const _ClearCacheRow(),
              const _GroupHeader('查寝人员'),
              const _InspectorCard(),
              const _GroupHeader('其他'),
              const _AboutEntryRow(),
            ],
          ),
        );
      },
    );
  }
}

/// 分组小标题：15sp Medium，相对卡片左缘再内缩 4dp
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: MiuixText(
        text,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: MiuixTheme.of(context).colors.onBackgroundVariant,
      ),
    );
  }
}

/// 复合内容卡片（非整行跳转）：18dp 圆角 + 水平 16 外边距
class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: MiuixCard(
        cornerRadius: 18,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}

/// 图标 + 标题 / 描述 + 右侧值与箭头的跳转行（本身即一张卡片）
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.onTap,
    this.horizontalPadding = 16,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final VoidCallback? onTap;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: MiuixCard(
        cornerRadius: 18,
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 26, color: _kAccent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MiuixText(
                      title,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: onTap == null
                          ? colors.onSurface.withValues(alpha: 0.38)
                          : null,
                    ),
                    const SizedBox(height: 2),
                    MiuixText(
                      subtitle,
                      fontSize: 12,
                      color: colors.onBackgroundVariant,
                    ),
                  ],
                ),
              ),
              if (value != null) ...<Widget>[
                MiuixText(
                  value!,
                  fontSize: 13,
                  color: colors.onBackgroundVariant,
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                Icons.chevron_right,
                size: 22,
                color: colors.onBackgroundVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 深色模式卡：行标题 + 内嵌三段滑轨（跟随系统 / 日间 / 夜间）
class _DarkModeCard extends StatelessWidget {
  const _DarkModeCard();

  @override
  Widget build(BuildContext context) {
    final StorageService storage = AppScope.of(context).storage;
    final int selectedIndex = storage.darkMode == null
        ? 0
        : storage.darkMode == false
        ? 1
        : 2;

    return _SettingCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.dark_mode, size: 26, color: _kAccent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const MiuixText(
                      '深色模式',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    const SizedBox(height: 2),
                    MiuixText(
                      '日间、夜间或跟随系统深浅色',
                      fontSize: 12,
                      color: MiuixTheme.of(context).colors.onBackgroundVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          MiuixGlassSegmentedTabRow(
            tabs: const <String>['跟随系统', '日间', '夜间'],
            selectedIndex: selectedIndex,
            onSelect: (int i) => storage.setDarkMode(
              i == 0
                  ? null
                  : i == 1
                  ? false
                  : true,
            ),
          ),
        ],
      ),
    );
  }
}

/// 人员库入口行
class _PersonLibraryRow extends StatelessWidget {
  const _PersonLibraryRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: Icons.groups,
      title: '人员库',
      subtitle: '导入、查看与编辑查寝对象名单',
      value: '$count 人',
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const PersonPage())),
    );
  }
}

/// 导出备份行
class _BackupExportRow extends StatefulWidget {
  const _BackupExportRow();

  @override
  State<_BackupExportRow> createState() => _BackupExportRowState();
}

class _BackupExportRowState extends State<_BackupExportRow> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final AppScope scope = AppScope.of(context);
    try {
      final File file = await scope.excel.exportBackupFile(
        scope.storage.exportBackup(),
      );
      await scope.excel.shareFile(file);
    } catch (_) {
      if (mounted) scope.snackbar.showSnackbar('导出备份失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: Icons.ios_share,
      title: '导出数据备份',
      subtitle: '将人员库、查寝记录与设置保存为备份文件',
      onTap: _busy ? null : _export,
    );
  }
}

/// 恢复备份行
class _BackupRestoreRow extends StatefulWidget {
  const _BackupRestoreRow();

  @override
  State<_BackupRestoreRow> createState() => _BackupRestoreRowState();
}

class _BackupRestoreRowState extends State<_BackupRestoreRow> {
  bool _busy = false;

  Future<void> _restore() async {
    if (_busy) return;
    final AppScope scope = AppScope.of(context);
    final Map<String, dynamic>? data = await scope.excel.pickBackupFile();
    if (data == null || !mounted) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('从备份恢复'),
        content: const Text('将用备份内容覆盖当前的人员库、查寝记录与设置，确定继续吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await scope.storage.restoreBackup(data);
      if (mounted) scope.snackbar.showSnackbar('已从备份恢复');
    } catch (_) {
      if (mounted) scope.snackbar.showSnackbar('恢复备份失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: Icons.settings_backup_restore,
      title: '从备份恢复',
      subtitle: '选择备份文件覆盖当前数据',
      onTap: _busy ? null : _restore,
    );
  }
}

/// 清除缓存行：统计并一键清空应用临时目录（导出用的临时表格等），
/// 不触碰人员库、查寝记录与设置等持久数据。
class _ClearCacheRow extends StatefulWidget {
  const _ClearCacheRow();

  @override
  State<_ClearCacheRow> createState() => _ClearCacheRowState();
}

class _ClearCacheRowState extends State<_ClearCacheRow> {
  String _sizeLabel = '统计中…';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  Future<int> _calcCacheBytes(Directory dir) async {
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    const List<String> units = <String>['KB', 'MB', 'GB'];
    double value = bytes / 1024;
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> _refreshSize() async {
    final Directory dir = await getTemporaryDirectory();
    final int bytes = await _calcCacheBytes(dir);
    if (!mounted) return;
    setState(() {
      _sizeLabel = _formatBytes(bytes);
    });
  }

  Future<void> _clear() async {
    if (_busy) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清除缓存'),
        content: Text('$_sizeLabel 的临时文件（导出表格等）将被删除，人员库与查寝记录不受影响。确定清除吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final AppScope scope = AppScope.of(context);
    try {
      final Directory dir = await getTemporaryDirectory();
      await for (final FileSystemEntity entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // 被占用或无权限的文件跳过。
        }
      }
      await _refreshSize();
      if (mounted) scope.snackbar.showSnackbar('缓存已清除');
    } catch (_) {
      if (mounted) scope.snackbar.showSnackbar('清除缓存失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: Icons.cleaning_services_outlined,
      title: '清除缓存',
      subtitle: '删除导出产生的临时文件，不影响记录数据',
      value: _busy ? null : _sizeLabel,
      onTap: _busy ? null : _clear,
    );
  }
}

/// 关于入口行
class _AboutEntryRow extends StatelessWidget {
  const _AboutEntryRow();

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      icon: Icons.info_outline,
      title: '关于',
      subtitle: '版本号与开放源代码许可',
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
    );
  }
}

/// 设置页的查寝人员管理卡：输入并添加，可勾选默认（新建批次时预填该姓名）
class _InspectorCard extends StatefulWidget {
  const _InspectorCard();

  @override
  State<_InspectorCard> createState() => _InspectorCardState();
}

class _InspectorCardState extends State<_InspectorCard> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final AppScope scope = AppScope.of(context);
    if (!scope.storage.addInspector(_ctrl.text)) {
      scope.snackbar.showSnackbar('姓名不能为空，且不能重复');
      return;
    }
    _ctrl.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _confirmRemove(String name) async {
    final StorageService storage = AppScope.of(context).storage;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除查寝人员'),
        content: Text('确定删除「$name」吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      storage.removeInspector(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final StorageService storage = AppScope.of(context).storage;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final List<String> list = storage.inspectors;

    return _SettingCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: MiuixTextField(
                    controller: _ctrl,
                    label: '查寝人员姓名',
                    singleLine: true,
                    insideMargin: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 10),
                MiuixButton(onPressed: _add, child: const Text('添加')),
              ],
            ),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: MiuixText(
                '尚未添加；添加后新建晚归 / 卫生批次会自动预填默认人员',
                fontSize: 12,
                color: colors.onBackgroundVariant,
              ),
            ),
          for (final String name in list)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => storage.setDefaultInspector(name),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: <Widget>[
                    IgnorePointer(
                      child: MiuixRadioButton(
                        selected: storage.defaultInspector == name,
                        onChanged: (_) {},
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: MiuixText(name, fontSize: 15)),
                    if (storage.defaultInspector == name)
                      MiuixText('默认', fontSize: 12, color: colors.primary),
                    MiuixIconButton(
                      minWidth: 48,
                      minHeight: 48,
                      onPressed: () => _confirmRemove(name),
                      child: Icon(Icons.close, size: 18, color: colors.error),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 关于页：头部应用信息 + 构建信息 / 设备信息 / 制作者分组卡片
/// （参考 BiliMax 助手同款页面），无「访问官网」入口。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  // 构建时间与版本号均在 release 打包时由 --dart-define 注入：
  // BUILD_TIME 为打包机当时时间（固定值），APP_VERSION 取自 pubspec。
  // 未注入时只能显示「未注入」，绝不能回退 DateTime.now()——
  // 否则每次打开关于页都会显示手机当前时间，看似"与手机时间同步"。
  static const String _buildTime = String.fromEnvironment(
    'BUILD_TIME',
    defaultValue: '',
  );

  static const String _appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '',
  );

  String _deviceModel = '读取中…';
  String _systemVersion = '读取中…';

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final DeviceSummary summary = await readDeviceSummary();
    final String model = summary.model;
    final String system = summary.system;
    if (!mounted) {
      return;
    }
    setState(() {
      _deviceModel = model;
      _systemVersion = system;
    });
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final String buildTime = _buildTime.isNotEmpty
        ? '$_buildTime CST'
        : '未注入（debug 构建）';
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '关于',
        navigationIcon: MiuixIconButton(
          minWidth: 48,
          minHeight: 48,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
      ),
      content: (EdgeInsets padding) {
        return MiuixPageContent(
          child: ListView(
            padding: padding.add(const EdgeInsets.fromLTRB(16, 8, 16, 24)),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const MiuixText(
                      '查寝助手',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        MiuixText(
                          _appVersion.isNotEmpty
                              ? '版本 $_appVersion'
                              : '版本（release 包可见）',
                          fontSize: 14,
                          color: colors.onBackgroundVariant,
                        ),
                        // 应用内更新只支持 Android（GitHub Releases 中的 APK 资产）
                        if (Platform.isAndroid) ...<Widget>[
                          const SizedBox(width: 10),
                          _CheckUpdateButton(
                            currentVersion: _appVersion,
                            snackbar: AppScope.of(context).snackbar,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    MiuixText(
                      '宿舍晚归与卫生检查记录工具',
                      fontSize: 14,
                      color: colors.onBackgroundVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _AboutCard(
                children: <Widget>[
                  _AboutInfoRow(
                    label: '构建类型',
                    value: kReleaseMode ? 'Release 正式构建' : 'Debug 调试构建',
                  ),
                  _AboutInfoRow(label: '构建时间', value: buildTime),
                  const _AboutInfoRow(label: '构建者', value: 'fwzjszd'),
                ],
              ),
              _AboutCard(
                children: <Widget>[
                  _AboutInfoRow(label: '设备型号', value: _deviceModel),
                  _AboutInfoRow(label: '系统版本', value: _systemVersion),
                ],
              ),
              _AboutCard(
                children: <Widget>[
                  MiuixText(
                    '制作者',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.onBackground,
                  ),
                  const SizedBox(height: 10),
                  const _MakerRow(
                    name: 'fwzjszd',
                    githubUrl: 'https://github.com/fwzjszd',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _SettingRow(
                icon: Icons.account_balance_outlined,
                title: '开放源代码许可',
                subtitle: '查寝助手使用的开源项目及其协议',
                horizontalPadding: 0,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const OpenSourceLicensesPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Center(
                child: MiuixText(
                  'Powered by Flutter miuix',
                  fontSize: 14,
                  color: colors.onBackgroundVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 关于页版本号旁的「检查更新」按钮：仅 Android 端放入。
/// 检查 GitHub Releases 最新发布，发现新版本时弹出下载/安装对话框。
class _CheckUpdateButton extends StatefulWidget {
  const _CheckUpdateButton({required this.currentVersion, required this.snackbar});

  /// 当前包版本（由 --dart-define=APP_VERSION 注入，可能为空）
  final String currentVersion;

  final AppToastState snackbar;

  @override
  State<_CheckUpdateButton> createState() => _CheckUpdateButtonState();
}

class _CheckUpdateButtonState extends State<_CheckUpdateButton> {
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final UpdateResult result =
          await UpdateService.checkForUpdate(widget.currentVersion);
      if (!mounted) return;
      if (!result.hasUpdate) {
        await _showResultDialog(
          title: '已是最新版本',
          content: '当前版本${widget.currentVersion.isNotEmpty ? ' ${widget.currentVersion}，' : '，'}'
              '暂无需更新。',
        );
        return;
      }
      await showDialog<bool>(
        context: context,
        builder: (_) => _UpdateDialog(info: result.info!),
      );
    } on UpdateException catch (e) {
      if (mounted) widget.snackbar.showSnackbar(e.message);
    } catch (_) {
      if (mounted) widget.snackbar.showSnackbar('检查更新失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResultDialog({
    required String title,
    required String content,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _busy ? null : _check,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            const Icon(Icons.refresh, size: 14, color: _kAccent),
          const SizedBox(width: 2),
          const MiuixText(
            '检查更新',
            fontSize: 13,
            color: _kAccent,
          ),
        ],
      ),
    );
  }
}

/// 新版本对话框：展示版本/大小/更新说明，支持下载进度与拉起安装。
class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null = 未开始下载
  File? _apkFile;
  String? _error;
  bool _installing = false;

  bool get _downloading => _progress != null && _progress! < 1 && _apkFile == null;

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '大小未知';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> _download() async {
    if (_progress != null) return;
    setState(() {
      _error = null;
      _progress = 0;
    });
    try {
      final File file = await UpdateService.downloadApk(
        widget.info,
        onProgress: (double p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) {
        setState(() {
          _apkFile = file;
          _progress = 1;
        });
      }
    } on UpdateException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _progress = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '下载失败，请稍后重试';
          _progress = null;
        });
      }
    }
  }

  Future<void> _install() async {
    final File? file = _apkFile;
    if (file == null || _installing) return;
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      await UpdateService.installApk(file);
      if (mounted) Navigator.of(context).pop(true);
    } on UpdateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UpdateInfo info = widget.info;
    final String? date = info.publishedAt == null
        ? null
        : '${info.publishedAt!.year}-'
            '${info.publishedAt!.month.toString().padLeft(2, '0')}-'
            '${info.publishedAt!.day.toString().padLeft(2, '0')}';
    return AlertDialog(
      title: Text('发现新版本 ${info.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MiuixText(
            <String>[
              _formatSize(info.apkSize),
              if (date != null) '发布于 $date',
            ].join('　·　'),
            fontSize: 12,
            color: MiuixTheme.of(context).colors.onBackgroundVariant,
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: Text(
                info.releaseNotes.isNotEmpty ? info.releaseNotes : '（未提供更新说明）',
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
          ),
          if (_progress != null) ...<Widget>[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress! >= 1 ? null : _progress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _apkFile != null
                  ? '下载完成，可以安装'
                  : '正在下载… ${(_progress! * 100).clamp(0, 99).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red)),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed:
              _downloading || _installing ? null : () => Navigator.of(context).pop(),
          child: const Text('以后再说'),
        ),
        if (_apkFile == null)
          TextButton(
            onPressed: _downloading ? null : _download,
            child: Text(_progress == null ? '下载更新' : '下载中…'),
          )
        else
          TextButton(
            onPressed: _installing ? null : _install,
            child: Text(_installing ? '正在打开…' : '立即安装'),
          ),
      ],
    );
  }
}

/// 关于页的分组信息卡片：18dp 圆角卡 + 统一内边距
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MiuixCard(
        cornerRadius: 18,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// 卡片内「标签 ………… 值」左右分布的一行信息
class _AboutInfoRow extends StatelessWidget {
  const _AboutInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          MiuixText(label, fontSize: 16, color: colors.onBackgroundVariant),
          Expanded(
            child: MiuixText(value, fontSize: 16, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// 制作者行：头像 + 昵称，右侧为圆形 GitHub 跳转按钮
class _MakerRow extends StatelessWidget {
  const _MakerRow({required this.name, this.githubUrl});

  final String name;
  final String? githubUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          ClipOval(
            child: Image.asset(
              'assets/avatar/fwzjszd.png',
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          MiuixText(name, fontSize: 17),
          const Spacer(),
          if (githubUrl != null) _GithubCircleButton(url: githubUrl!),
        ],
      ),
    );
  }
}

/// 制作者行右侧的圆形 GitHub 跳转按钮：
/// 半透明圆形底 + 中央白色线性 Octocat（24×24），
/// 点击以外部浏览器打开作者主页。
class _GithubCircleButton extends StatelessWidget {
  const _GithubCircleButton({required this.url});

  /// 圆形按钮直径
  static const double size = 40;

  final String url;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Material(
      color: colors.onBackground.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final Uri uri = Uri.parse(url);
          final bool ok = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!ok && context.mounted) {
            AppScope.of(context).snackbar.showSnackbar('无法打开链接');
          }
        },
        child: SizedBox(
          width: size,
          height: size,
          child: Padding(
            padding: const EdgeInsets.all(size * 0.24),
            child: CustomPaint(
              painter: _GithubMarkPainter(colors.onBackground),
            ),
          ),
        ),
      ),
    );
  }
}

/// 绘制线性 GitHub Octocat 标志（feathericons 风格，viewBox 0 0 24 24）。
/// 内联 SVG path 解析器支持 M/m、L/l、H/h、V/v、C/c、S/s、A/a、Z。
class _GithubMarkPainter extends CustomPainter {
  const _GithubMarkPainter(this.color);

  static const String _pathData =
      'M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4';
  static const String _tailData = 'M9 18c-4.51 2-5-2-7-2';

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path source = _parsePath(_pathData)
      ..addPath(_parsePath(_tailData), Offset.zero);
    final double s = size.width / 24;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..scale(s, s)
      ..drawPath(source, paint)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _GithubMarkPainter oldDelegate) =>
      oldDelegate.color != color;

  static Path _parsePath(String data) {
    final Path path = Path();
    final RegExp token = RegExp(r'[A-Za-z]|-?\d*\.?\d+');
    final List<String> tokens = token
        .allMatches(data)
        .map((Match m) => m.group(0)!)
        .toList();
    final RegExp letter = RegExp(r'[A-Za-z]');

    double curX = 0;
    double curY = 0;
    // 上一条已执行命令，用于 S/s 的控制点反射
    String lastCmd = '';
    double? lastX2;
    double? lastY2;
    String? cmd;
    int i = 0;

    double nextNum() => double.parse(tokens[i++]);
    bool cubicPrev() =>
        lastCmd == 'C' || lastCmd == 'c' || lastCmd == 'S' || lastCmd == 's';

    parse:
    while (i < tokens.length) {
      if (letter.hasMatch(tokens[i])) {
        cmd = tokens[i++];
      }
      switch (cmd) {
        case 'M':
          curX = nextNum();
          curY = nextNum();
          path.moveTo(curX, curY);
          lastCmd = 'M';
          // 后续隐式坐标对按直线处理
          cmd = 'L';
          continue parse;
        case 'm':
          curX += nextNum();
          curY += nextNum();
          path.moveTo(curX, curY);
          lastCmd = 'm';
          cmd = 'l';
          continue parse;
        case 'L':
          curX = nextNum();
          curY = nextNum();
          path.lineTo(curX, curY);
          lastCmd = 'L';
          continue parse;
        case 'l':
          curX += nextNum();
          curY += nextNum();
          path.lineTo(curX, curY);
          lastCmd = 'l';
          continue parse;
        case 'H':
          curX = nextNum();
          path.lineTo(curX, curY);
          lastCmd = 'H';
          continue parse;
        case 'h':
          curX += nextNum();
          path.lineTo(curX, curY);
          lastCmd = 'h';
          continue parse;
        case 'V':
          curY = nextNum();
          path.lineTo(curX, curY);
          lastCmd = 'V';
          continue parse;
        case 'v':
          curY += nextNum();
          path.lineTo(curX, curY);
          lastCmd = 'v';
          continue parse;
        case 'C':
          final double x1 = nextNum();
          final double y1 = nextNum();
          final double x2 = nextNum();
          final double y2 = nextNum();
          curX = nextNum();
          curY = nextNum();
          path.cubicTo(x1, y1, x2, y2, curX, curY);
          lastCmd = 'C';
          lastX2 = x2;
          lastY2 = y2;
          continue parse;
        case 'c':
          final double x1 = curX + nextNum();
          final double y1 = curY + nextNum();
          final double x2 = curX + nextNum();
          final double y2 = curY + nextNum();
          curX += nextNum();
          curY += nextNum();
          path.cubicTo(x1, y1, x2, y2, curX, curY);
          lastCmd = 'c';
          lastX2 = x2;
          lastY2 = y2;
          continue parse;
        case 'S':
          final double x2 = nextNum();
          final double y2 = nextNum();
          final double x = nextNum();
          final double y = nextNum();
          final double x1 = cubicPrev() ? 2 * curX - lastX2! : curX;
          final double y1 = cubicPrev() ? 2 * curY - lastY2! : curY;
          path.cubicTo(x1, y1, x2, y2, x, y);
          curX = x;
          curY = y;
          lastCmd = 'S';
          lastX2 = x2;
          lastY2 = y2;
          continue parse;
        case 's':
          final double x2 = curX + nextNum();
          final double y2 = curY + nextNum();
          final double x = curX + nextNum();
          final double y = curY + nextNum();
          final double x1 = cubicPrev() ? 2 * curX - lastX2! : curX;
          final double y1 = cubicPrev() ? 2 * curY - lastY2! : curY;
          path.cubicTo(x1, y1, x2, y2, x, y);
          curX = x;
          curY = y;
          lastCmd = 's';
          lastX2 = x2;
          lastY2 = y2;
          continue parse;
        case 'A':
        case 'a':
          final double rx = nextNum();
          final double ry = nextNum();
          final double rot = nextNum();
          final double large = nextNum();
          final double sweep = nextNum();
          final bool relative = cmd == 'a';
          double x = nextNum();
          double y = nextNum();
          if (relative) {
            x += curX;
            y += curY;
          }
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            rotation: rot,
            largeArc: large == 1,
            clockwise: sweep == 1,
          );
          curX = x;
          curY = y;
          lastCmd = relative ? 'a' : 'A';
          continue parse;
        case 'Z':
        case 'z':
          path.close();
          lastCmd = 'z';
          continue parse;
        default:
          break parse;
      }
      // 每个命令分支末尾均 continue parse 回顶部重新取下一个 token：
      // 是字母则切换命令，是数字则隐式重复当前命令。绝不能在参数耗尽时直接
      // break，否则中途切换命令会丢失后续路径。
    }
    return path;
  }
}

/// 单个致谢开源项目的数据
class _LicenseEntryData {
  const _LicenseEntryData({
    required this.name,
    required this.spdx,
    required this.description,
    required this.copyright,
    required this.url,
  });

  final String name;
  final String spdx;
  final String description;
  final String copyright;
  final String url;
}

/// 开放源代码许可页：致谢卡片式排版（参考 BiliMax 同步器同款页面）
class OpenSourceLicensesPage extends StatelessWidget {
  const OpenSourceLicensesPage({super.key});

  // 以下为本项目 pubspec.yaml 中真实声明的直接依赖，
  // 名称、协议、版权署名与仓库链接均取自各包自带的 LICENSE / pubspec 原文。
  static const List<_LicenseEntryData> _entries = <_LicenseEntryData>[
    _LicenseEntryData(
      name: 'flutter_miuix',
      spdx: 'Apache-2.0',
      description: '全部界面组件库（HyperOS 风格），含连续曲率圆角、弹性动效、液态玻璃模糊与动态取色',
      copyright: 'Copyright 2026 flutter_miuix contributors',
      url: 'https://github.com/ChuxinNeko/flutter_miuix',
    ),
    _LicenseEntryData(
      name: 'excel',
      spdx: 'MIT',
      description: '读取与生成 .xlsx 表格（名单导入、查寝与卫生检查结果导出）',
      copyright: 'Copyright (c) 2021 Kawaljeet Singh',
      url: 'https://github.com/justkawal/excel',
    ),
    _LicenseEntryData(
      name: 'archive',
      spdx: 'MIT',
      description: '解析前对 xlsx 压缩包做兼容性清洗（openpyxl / WPS 生成的文件）',
      copyright: 'Copyright (c) 2013-2021 Brendan Duncan',
      url: 'https://github.com/brendan-duncan/archive',
    ),
    _LicenseEntryData(
      name: 'file_picker',
      spdx: 'MIT',
      description: '选择名单表格与备份文件',
      copyright: 'Copyright (c) 2018 Miguel Ruivo',
      url: 'https://github.com/vicajilau/flutter_file_picker',
    ),
    _LicenseEntryData(
      name: 'url_launcher',
      spdx: 'BSD-3-Clause',
      description: '在本页点击链接时打开对应开源仓库',
      copyright: 'Copyright 2013 The Flutter Authors',
      url:
          'https://github.com/flutter/packages/tree/main/packages/url_launcher',
    ),
    _LicenseEntryData(
      name: 'path_provider',
      spdx: 'BSD-3-Clause',
      description: '获取应用文档与缓存目录，用于备份文件的读写',
      copyright: 'Copyright 2013 The Flutter Authors',
      url: 'https://github.com/flutter/packages/tree/main/packages/path_provider',
    ),
    _LicenseEntryData(
      name: 'share_plus',
      spdx: 'BSD-3-Clause',
      description: '将导出的表格 / 备份文件分享到微信、QQ 等其他应用',
      copyright: 'Copyright 2017, the Flutter project authors',
      url: 'https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus',
    ),
    _LicenseEntryData(
      name: 'shared_preferences',
      spdx: 'BSD-3-Clause',
      description: '本地持久化人员库、查寝批次与各项设置',
      copyright: 'Copyright 2013 The Flutter Authors',
      url: 'https://github.com/flutter/packages/tree/main/packages/shared_preferences',
    ),
    _LicenseEntryData(
      name: 'device_info_plus',
      spdx: 'BSD-3-Clause',
      description: '关于页读取设备型号与 Android 系统版本',
      copyright: 'Copyright 2017 The Chromium Authors',
      url: 'https://github.com/fluttercommunity/plus_plugins/tree/main/packages/device_info_plus',
    ),
  ];

  Future<void> _openUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      AppScope.of(context).snackbar.showSnackbar('无法打开链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '开放源代码许可',
        navigationIcon: MiuixIconButton(
          minWidth: 48,
          minHeight: 48,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
      ),
      content: (EdgeInsets padding) {
        return MiuixPageContent(
          child: ListView(
            padding: padding.add(const EdgeInsets.only(bottom: 24)),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: MiuixText(
                  '查寝助手在开发中使用或参考了以下开源项目，在此向各项目作者致谢：',
                  fontSize: 15,
                  height: 1.6,
                  color: colors.onBackgroundVariant,
                ),
              ),
              for (final _LicenseEntryData e in _entries)
                _LicenseCard(data: e, onTap: () => _openUrl(context, e.url)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: MiuixText(
                  '查寝助手自身基于 GNU GPL v3.0 开源。',
                  fontSize: 13,
                  color: colors.onBackgroundVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 单个开源项目的致谢卡片：名称 + 协议徽标 + 描述 + 版权 + 可点击链接
class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.data, required this.onTap});

  final _LicenseEntryData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: MiuixCard(
        cornerRadius: 18,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MiuixText(
                data.name,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.onBackground,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  data.spdx,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _kAccent,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              MiuixText(
                data.description,
                fontSize: 15,
                height: 1.55,
                color: colors.onBackgroundVariant,
              ),
              const SizedBox(height: 8),
              MiuixText(
                data.copyright,
                fontSize: 14,
                color: colors.onBackgroundVariant,
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    data.url,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _kAccent,
                      decoration: TextDecoration.underline,
                      decorationColor: _kAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
