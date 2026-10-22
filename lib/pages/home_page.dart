// 主页：查寝批次列表（晚归 / 卫生 / 多文档导入三类）
// 顶部可进入人员库管理、搜索记录；右下角新建批次时先选格式；点击卡片进入编辑/导出

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../main.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'hygiene_edit_page.dart';
import 'merge_page.dart';
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
    required this.merged,
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
    merged: s.merged,
    session: s,
  );

  factory _HomeEntry.fromHygiene(HygieneSession s) {
    final int dormCount = s.rows
        .where((HygieneRow r) => r.dorm.trim().isNotEmpty)
        .length;
    return _HomeEntry(
      id: s.id,
      date: s.date,
      title: s.displayTitle,
      subtitle:
          '$dormCount 个寝室'
          '${s.inspector.isEmpty ? '' : ' · 检查人员：${s.inspector}'}'
          '${s.building.isEmpty ? '' : ' · ${s.building}'}',
      hygiene: true,
      merged: s.merged,
      hygieneSession: s,
    );
  }

  final String id;
  final DateTime date;
  final String title;
  final String subtitle;
  final bool hygiene;
  final bool merged;
  final InspectionSession? session;
  final HygieneSession? hygieneSession;
}

/// 汇总当前全部记录（晚归 + 卫生），按时间倒序
List<_HomeEntry> _allEntries(AppScope scope) {
  return <_HomeEntry>[
    ...scope.storage.sessions.map(_HomeEntry.fromSession),
    ...scope.storage.hygieneSessions.map(_HomeEntry.fromHygiene),
  ]..sort((_HomeEntry a, _HomeEntry b) => b.date.compareTo(a.date));
}

Future<void> _openEditorForEntry(BuildContext context, _HomeEntry e) async {
  final String defaultInspector = AppScope.of(context)
      .storage
      .defaultInspector;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => e.hygiene
          ? HygieneEditPage(
              session: e.hygieneSession,
              defaultInspector: defaultInspector,
            )
          : SessionEditPage(
              session: e.session,
              defaultInspector: defaultInspector,
            ),
    ),
  );
}

/// 右下角 + ：选择新建格式
void showCreateSheet(BuildContext context) {
  Future<void> openEditor(InspectionSession? session) async {
    final String defaultInspector = AppScope.of(context)
        .storage
        .defaultInspector;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionEditPage(
          session: session,
          defaultInspector: defaultInspector,
        ),
      ),
    );
  }

  Future<void> openHygieneEditor(HygieneSession? session) async {
    final String defaultInspector = AppScope.of(context)
        .storage
        .defaultInspector;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HygieneEditPage(
          session: session,
          defaultInspector: defaultInspector,
        ),
      ),
    );
  }

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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            item(
              Icons.nightlight_round,
              '晚归',
              '记录晚归 / 异常人员，按文本模板复制发送',
              () => openEditor(null),
            ),
            item(
              Icons.cleaning_services_outlined,
              '卫生',
              '内务卫生评分表，可按人员库寝室自动成行',
              () => openHygieneEditor(null),
            ),
            item(
              Icons.merge_type,
              '多文档合成',
              '导入多份本软件生成的文档，合成为一份总结',
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const MergePage()),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

// ========== 导出 ==========

Future<void> _copySession(BuildContext context, InspectionSession session) async {
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

Future<void> _copyHygiene(BuildContext context, HygieneSession session) async {
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

void _showExportOptions(BuildContext context, _HomeEntry e) {
  if (e.hygiene) {
    final HygieneSession session = e.hygieneSession!;
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
  } else {
    final InspectionSession session = e.session!;
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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final MiuixColors colors = MiuixTheme.of(context).colors;

    final List<_HomeEntry> entries = _allEntries(scope);

    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '查寝助手',
        largeTitle: '查寝记录',
        actions: <Widget>[
          if (entries.isNotEmpty)
            MiuixIconButton(
              minWidth: 48,
              minHeight: 48,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RecordSearchPage(),
                ),
              ),
              child: const Icon(Icons.search, size: 22),
            ),
        ],
      ),
      floatingActionButton: MiuixFloatingActionButton(
        onPressed: () => showCreateSheet(context),
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
            itemBuilder: (BuildContext context, int i) =>
                _EntryCard(entry: entries[i]),
          ),
        );
      },
    );
  }
}

/// 查寝记录卡片：首页与搜索页共用
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final _HomeEntry entry;

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: MiuixCard(
        cornerRadius: 18,
        onPressed: () => _openEditorForEntry(context, entry),
        onLongPress: () => _confirmDelete(context, entry),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                            entry.title,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _TypeBadge(
                          hygiene: entry.hygiene,
                          merged: entry.merged,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    MiuixText(
                      entry.subtitle,
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
                onPressed: () => _showExportOptions(context, entry),
                child: const Icon(Icons.ios_share, size: 20),
              ),
              MiuixIconButton(
                minWidth: 48,
                minHeight: 48,
                onPressed: () => _confirmDelete(context, entry),
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
  }
}

/// 记录搜索页：按标题、检查人员、寝室号、姓名 / 学号 / 班级、原因、等级等过滤
class RecordSearchPage extends StatefulWidget {
  const RecordSearchPage({super.key});

  @override
  State<RecordSearchPage> createState() => _RecordSearchPageState();
}

class _RecordSearchPageState extends State<RecordSearchPage> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _matches(_HomeEntry e, String kw) {
    bool hit(String v) => v.toLowerCase().contains(kw);
    if (hit(e.title) || hit(e.subtitle)) return true;
    if (e.hygiene) {
      final HygieneSession s = e.hygieneSession!;
      if (hit(s.building) || hit(s.inspector)) return true;
      return s.rows.any(
        (HygieneRow r) => hit(r.dorm) || hit(r.grade) || hit(r.remark),
      );
    }
    final InspectionSession s = e.session!;
    if (hit(s.dormRange) || hit(s.inspector)) return true;
    return s.records.any(
      (InspectionRecord r) =>
          hit(r.dorm) ||
          hit(r.name) ||
          hit(r.studentId) ||
          hit(r.className) ||
          hit(r.reason) ||
          hit(r.counselor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final String kw = _query.trim().toLowerCase();
    final List<_HomeEntry> results = kw.isEmpty
        ? _allEntries(scope)
        : _allEntries(scope).where((_HomeEntry e) => _matches(e, kw)).toList();

    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '搜索记录',
        largeTitle: '搜索记录',
        navigationIcon: MiuixIconButton(
          minWidth: 48,
          minHeight: 48,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
      ),
      content: (EdgeInsets padding) {
        return MiuixPageContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 4),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (String v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: '搜索标题、寝室号、姓名、学号、检查人员…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.search_off,
                              size: 56,
                              color: colors.onBackgroundVariant,
                            ),
                            const SizedBox(height: 10),
                            MiuixText(
                              kw.isEmpty ? '还没有查寝记录' : '没有匹配的记录',
                              color: colors.onBackgroundVariant,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 6, bottom: 24),
                        itemCount: results.length,
                        itemBuilder: (BuildContext context, int i) =>
                            _EntryCard(entry: results[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 卡片上的类型徽标：晚归 / 卫生 / 多文档导入
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.hygiene, required this.merged});

  final bool hygiene;
  final bool merged;

  @override
  Widget build(BuildContext context) {
    final Color tint;
    final IconData icon;
    final String label;
    if (merged) {
      tint = const Color(0xFF7E57C2);
      icon = Icons.merge_type;
      label = '多文档导入';
    } else if (hygiene) {
      tint = const Color(0xFF2E9E5B);
      icon = Icons.cleaning_services_outlined;
      label = '卫生';
    } else {
      tint = const Color(0xFF5B6BDB);
      icon = Icons.nightlight_round;
      label = '晚归';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: tint),
          const SizedBox(width: 4),
          Text(
            label,
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
