// 主页：查寝批次列表（晚归 / 卫生两类）
// 顶部可进入人员库管理；右下角新建批次时先选格式；点击卡片进入编辑/导出

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../main.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'hygiene_edit_page.dart';
import 'person_page.dart';
import 'session_edit_page.dart';

/// 列表中的一条（晚归批次或卫生批次）
class _HomeEntry {
  const _HomeEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.hygiene,
    this.session,
    this.hygieneSession,
  });

  factory _HomeEntry.fromSession(InspectionSession s) => _HomeEntry(
    id: s.id,
    date: s.date,
    title: s.displayTitle,
    subtitle:
        '${s.records.length} 条记录'
        '${s.inspector.isEmpty ? '' : ' · 检查人员：${s.inspector}'}',
    hygiene: false,
    session: s,
  );

  factory _HomeEntry.fromHygiene(HygieneSession s) {
    final int dormCount =
        s.rows.where((HygieneRow r) => r.dorm.trim().isNotEmpty).length;
    return _HomeEntry(
      id: s.id,
      date: s.date,
      title: s.displayTitle,
      subtitle:
          '$dormCount 个寝室'
          '${s.inspector.isEmpty ? '' : ' · 检查人员：${s.inspector}'}'
          '${s.building.isEmpty ? '' : ' · ${s.building}'}',
      hygiene: true,
      hygieneSession: s,
    );
  }

  final String id;
  final DateTime date;
  final String title;
  final String subtitle;
  final bool hygiene;
  final InspectionSession? session;
  final HygieneSession? hygieneSession;
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _openEditor(
    BuildContext context,
    InspectionSession? session,
  ) async {
    final String defaultInspector =
        AppScope.of(context).storage.defaultInspector;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionEditPage(
          session: session,
          defaultInspector: defaultInspector,
        ),
      ),
    );
  }

  Future<void> _openHygieneEditor(
    BuildContext context,
    HygieneSession? session,
  ) async {
    final String defaultInspector =
        AppScope.of(context).storage.defaultInspector;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HygieneEditPage(
          session: session,
          defaultInspector: defaultInspector,
        ),
      ),
    );
  }

  /// 右下角 + ：选择新建格式
  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        Widget item(
          IconData icon,
          String title,
          String subtitle,
          VoidCallback onTap,
        ) {
          return ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择查寝格式',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              item(
                Icons.nightlight_round,
                '晚归',
                '记录晚归 / 异常人员，按文本模板复制发送',
                () => _openEditor(context, null),
              ),
              item(
                Icons.cleaning_services_outlined,
                '卫生',
                '内务卫生评分表，可按人员库寝室自动成行',
                () => _openHygieneEditor(context, null),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ========== 晚归批次导出 ==========

  Future<void> _copySession(
    BuildContext context,
    InspectionSession session,
  ) async {
    final AppScope scope = AppScope.of(context);
    await Clipboard.setData(
      ClipboardData(text: scope.excel.buildSessionText(session)),
    );
    scope.snackbar.showSnackbar('已按模板复制，可直接粘贴发送');
  }

  Future<void> _exportSessionWord(
    BuildContext context,
    InspectionSession session,
  ) async {
    final AppScope scope = AppScope.of(context);
    try {
      final File file = await scope.excel.exportSessionWord(session);
      await scope.excel.shareFile(file);
    } catch (e) {
      scope.snackbar.showSnackbar('导出失败：$e');
    }
  }

  void _showSessionExportOptions(
    BuildContext context,
    InspectionSession session,
  ) {
    showExportOptionsSheet(
      context,
      options: <ExportOption>[
        ExportOption(
          icon: Icons.content_copy_rounded,
          title: '复制到剪切板',
          subtitle: '按模板生成文本，可直接粘贴到微信 / 飞书发送',
          onTap: () => _copySession(context, session),
        ),
        ExportOption(
          icon: Icons.description_outlined,
          title: '导出为word',
          subtitle: '生成 .docx 文档并分享',
          onTap: () => _exportSessionWord(context, session),
        ),
      ],
    );
  }

  // ========== 卫生批次导出 ==========

  Future<void> _copyHygiene(
    BuildContext context,
    HygieneSession session,
  ) async {
    final AppScope scope = AppScope.of(context);
    await Clipboard.setData(
      ClipboardData(text: scope.excel.buildHygieneText(session)),
    );
    scope.snackbar.showSnackbar('已按评分表模板复制，可直接粘贴发送');
  }

  Future<void> _exportHygieneWord(
    BuildContext context,
    HygieneSession session,
  ) async {
    final AppScope scope = AppScope.of(context);
    try {
      final File file = await scope.excel.exportHygieneWord(session);
      await scope.excel.shareFile(file);
    } catch (e) {
      scope.snackbar.showSnackbar('导出失败：$e');
    }
  }

  Future<void> _exportHygieneExcel(
    BuildContext context,
    HygieneSession session,
  ) async {
    final AppScope scope = AppScope.of(context);
    try {
      final File file = await scope.excel.exportHygiene(session);
      await scope.excel.shareFile(file);
    } catch (e) {
      scope.snackbar.showSnackbar('导出失败：$e');
    }
  }

  void _showHygieneExportOptions(
    BuildContext context,
    HygieneSession session,
  ) {
    showExportOptionsSheet(
      context,
      options: <ExportOption>[
        ExportOption(
          icon: Icons.content_copy_rounded,
          title: '复制到剪切板',
          subtitle: '按评分表模板生成文本，可直接粘贴发送',
          onTap: () => _copyHygiene(context, session),
        ),
        ExportOption(
          icon: Icons.description_outlined,
          title: '导出为word',
          subtitle: '按学院模板生成 .docx 文档并分享',
          onTap: () => _exportHygieneWord(context, session),
        ),
        ExportOption(
          icon: Icons.table_chart_outlined,
          title: '导出为Excel',
          subtitle: '生成 .xlsx 表格文件并分享',
          onTap: () => _exportHygieneExcel(context, session),
        ),
      ],
    );
  }

  // ========== 删除 ==========

  Future<void> _confirmDelete(BuildContext context, _HomeEntry entry) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(entry.hygiene ? '删除卫生检查' : '删除批次'),
        content: Text('确定删除「${entry.title}」吗？此操作不可恢复。'),
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
    if (ok == true && context.mounted) {
      final AppScope scope = AppScope.of(context);
      if (entry.hygiene) {
        scope.storage.deleteHygiene(entry.id);
      } else {
        scope.storage.deleteSession(entry.id);
      }
      scope.snackbar.showSnackbar('已删除');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final MiuixColors colors = MiuixTheme.of(context).colors;

    // 合并两类批次并按时间倒序
    final List<_HomeEntry> entries = <_HomeEntry>[
      ...scope.storage.sessions.map(_HomeEntry.fromSession),
      ...scope.storage.hygieneSessions.map(_HomeEntry.fromHygiene),
    ]..sort((_HomeEntry a, _HomeEntry b) => b.date.compareTo(a.date));

    return MiuixScaffold(
      topBar: const MiuixTopAppBar(
        title: '查寝助手',
        largeTitle: '查寝记录',
      ),
      floatingActionButton: MiuixFloatingActionButton(
        onPressed: () => _showCreateSheet(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      content: (EdgeInsets padding) {
        if (entries.isEmpty) {
          return MiuixPageContent(
            child: Padding(
              padding: padding,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.fact_check_outlined,
                      size: 64,
                      color: colors.onBackgroundVariant,
                    ),
                    const SizedBox(height: 12),
                    MiuixText('还没有查寝记录', color: colors.onBackgroundVariant),
                    const SizedBox(height: 6),
                    MiuixText(
                      '点击右下角 + 选择晚归或卫生格式',
                      color: colors.onBackgroundVariant,
                      fontSize: 13,
                    ),
                    if (scope.storage.persons.isEmpty) ...<Widget>[
                      const SizedBox(height: 20),
                      MiuixButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PersonPage(),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.file_upload_outlined, size: 18),
                            SizedBox(width: 6),
                            Text('先导入人员 Excel'),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return MiuixPageContent(
          child: ListView.builder(
            padding: padding.add(const EdgeInsets.only(bottom: 96)),
            itemCount: entries.length,
            itemBuilder: (BuildContext context, int i) {
              final _HomeEntry e = entries[i];
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: MiuixCard(
                  cornerRadius: 18,
                  onPressed: () {
                    if (e.hygiene) {
                      _openHygieneEditor(context, e.hygieneSession);
                    } else {
                      _openEditor(context, e.session);
                    }
                  },
                  onLongPress: () => _confirmDelete(context, e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Flexible(
                                    child: MiuixText(
                                      e.title,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _TypeBadge(hygiene: e.hygiene),
                                ],
                              ),
                              const SizedBox(height: 6),
                              MiuixText(
                                e.subtitle,
                                fontSize: 12,
                                color: colors.onBackgroundVariant,
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                        MiuixIconButton(
                          minWidth: 48,
                          minHeight: 48,
                          onPressed: () {
                            if (e.hygiene) {
                              _showHygieneExportOptions(
                                context,
                                e.hygieneSession!,
                              );
                            } else {
                              _showSessionExportOptions(context, e.session!);
                            }
                          },
                          child: const Icon(Icons.ios_share, size: 20),
                        ),
                        MiuixIconButton(
                          minWidth: 48,
                          minHeight: 48,
                          onPressed: () => _confirmDelete(context, e),
                          child: Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: colors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 卡片右上角的格式徽标：晚归 / 卫生
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.hygiene});

  final bool hygiene;

  @override
  Widget build(BuildContext context) {
    final Color tint = hygiene ? const Color(0xFF2E9E5B) : const Color(0xFF5B6BDB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            hygiene ? Icons.cleaning_services_outlined : Icons.nightlight_round,
            size: 11,
            color: tint,
          ),
          const SizedBox(width: 4),
          Text(
            hygiene ? '卫生' : '晚归',
            style: TextStyle(
              fontSize: 11,
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
