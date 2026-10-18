// 设置页：数据与查寝人员管理（外观默认液态玻璃+深色模式，不再提供切换）

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../main.dart';
import '../services/storage_service.dart';
import '../widgets/common.dart';
import 'person_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final StorageService storage = AppScope.of(context).storage;
    final MiuixColors colors = MiuixTheme.of(context).colors;

    return MiuixScaffold(
      topBar: const MiuixTopAppBar(title: '设置', largeTitle: '设置'),
      content: (EdgeInsets padding) {
        return MiuixPageContent(
          child: ListView(
            padding: padding.add(const EdgeInsets.only(bottom: 96)),
            children: <Widget>[
              const SectionTitle('数据'),
              GroupCard(
                children: <Widget>[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PersonPage(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Row(
                        children: <Widget>[
                          const Expanded(child: MiuixText('人员库', fontSize: 16)),
                          MiuixText(
                            '${storage.persons.length} 人',
                            fontSize: 14,
                            color: colors.onBackgroundVariant,
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 22,
                            color: colors.onBackgroundVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const _BackupSetting(),
                ],
              ),
              const SectionTitle('查寝人员'),
              const _InspectorSetting(),
            ],
          ),
        );
      },
    );
  }
}

/// 设置页的查寝人员管理：输入并添加，可勾选默认（新建批次时预填该姓名）
class _InspectorSetting extends StatefulWidget {
  const _InspectorSetting();

  @override
  State<_InspectorSetting> createState() => _InspectorSettingState();
}

class _InspectorSettingState extends State<_InspectorSetting> {
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

    return GroupCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
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
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: <Widget>[
                  IgnorePointer(
                    child: MiuixRadioButton(
                      selected: storage.defaultInspector == name,
                      onChanged: (_) {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: MiuixText(name, fontSize: 16)),
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
    );
  }
}

/// 数据备份：导出整库为 .json 备份文件分享，或从备份文件恢复覆盖当前数据
class _BackupSetting extends StatefulWidget {
  const _BackupSetting();

  @override
  State<_BackupSetting> createState() => _BackupSettingState();
}

class _BackupSettingState extends State<_BackupSetting> {
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

  Widget _row(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback? onTap,
  ) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MiuixText(
                    title,
                    fontSize: 16,
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
            Icon(icon, size: 22, color: colors.onBackgroundVariant),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GroupCard(
      children: <Widget>[
        _row(
          '导出数据备份',
          '将人员库、查寝记录与设置保存为备份文件',
          Icons.ios_share,
          _busy ? null : _export,
        ),
        _row(
          '从备份恢复',
          '选择备份文件覆盖当前数据',
          Icons.settings_backup_restore,
          _busy ? null : _restore,
        ),
      ],
    );
  }
}
