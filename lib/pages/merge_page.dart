// 多文档合成页
// 逐个导入「本软件生成」的导出文档（晚归 .docx / 卫生 .docx、.xlsx），
// 自动识别类型，按导入顺序简单拼接为一条晚归汇总和 / 或一条卫生汇总，
// 落库为新记录并可立即导出汇总文档。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../main.dart';
import '../models.dart';
import '../services/merge_service.dart';
import '../widgets/common.dart';

class MergePage extends StatefulWidget {
  const MergePage({super.key});

  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  final MergeService _service = MergeService();
  final List<ImportedDoc> _docs = <ImportedDoc>[];

  bool _busy = false;

  /// 当前筛选条件（默认即汇总口径：优秀 / 不合格 / 无人宿舍）
  MergeFilter _filter = const MergeFilter();

  /// 是否偏离了默认汇总口径（默认口径下不提示「筛选已启用」）
  bool get _hasFilter {
    final MergeFilter f = _filter;
    if (f.dormKeyword.trim().isNotEmpty || f.buildings.isNotEmpty) return true;
    return f.grades.length != HygieneGrade.summaryDefaults.length ||
        !f.grades.containsAll(HygieneGrade.summaryDefaults);
  }

  /// 已选文件路径去重，避免同一文件重复导入
  final Set<String> _paths = <String>{};

  Future<void> _addFiles() async {
    final AppScope scope = AppScope.of(context);
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['docx', 'xlsx'],
      );
    } catch (e) {
      scope.snackbar.showSnackbar('选择文件失败：$e');
      return;
    }
    if (picked.isEmpty) return;

    setState(() => _busy = true);
    int added = 0;
    for (final PlatformFile pf in picked) {
      final String? path = pf.path;
      if (path == null || !_paths.add(path)) continue;
      try {
        final List<int> bytes = await File(path).readAsBytes();
        final ImportedDoc doc = _service.parseBytes(bytes, pf.name, path: path);
        _docs.add(doc);
        added++;
      } catch (e) {
        _paths.remove(path);
        scope.snackbar.showSnackbar('无法识别「${pf.name}」：$e');
      }
    }
    if (mounted) {
      setState(() => _busy = false);
      if (added > 0) {
        scope.snackbar.showSnackbar('已添加 $added 份文档');
      }
    }
  }

  void _removeDoc(int index) {
    setState(() {
      final ImportedDoc doc = _docs.removeAt(index);
      if (doc.path.isNotEmpty) _paths.remove(doc.path);
    });
  }

  // onReorderItem 的 newIndex 已按插入位置调整，无需再减 1
  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final ImportedDoc doc = _docs.removeAt(oldIndex);
      _docs.insert(newIndex, doc);
    });
  }

  // ========== 筛选 ==========

  Future<void> _openFilter() async {
    final MergeOptions options = _service.optionsOf(_docs);
    final TextEditingController kwCtrl = TextEditingController(
      text: _filter.dormKeyword,
    );
    Set<String> buildings = Set<String>.from(_filter.buildings);
    // 默认汇总口径：优秀 / 不合格 / 无人宿舍
    Set<String> grades = _filter.grades.isEmpty
        ? Set<String>.from(HygieneGrade.summaryDefaults)
        : Set<String>.from(_filter.grades);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheet) {
            MergeFilter current() => MergeFilter(
              dormKeyword: kwCtrl.text,
              buildings: buildings,
              grades: grades,
            );

            MergePreview preview = _service.previewOf(_docs, current());
            final bool nothing =
                preview.records == 0 &&
                preview.rows == 0 &&
                preview.persons == 0;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 0,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    '筛选条件',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '卫生汇总默认只保留优秀、不合格、无人宿舍；'
                    '人员名单不受筛选影响',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  MiuixTextField(
                    controller: kwCtrl,
                    label: '宿舍号关键词，如 111（留空不限）',
                    singleLine: true,
                    onChanged: (_) => setSheet(() {}),
                  ),
                  if (options.buildings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    const Text(
                      '楼栋',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final String b in options.buildings)
                          _FilterChip(
                            label: b,
                            selected: buildings.contains(b),
                            onTap: () => setSheet(() {
                              if (!buildings.remove(b)) buildings.add(b);
                            }),
                          ),
                      ],
                    ),
                  ],
                  if (options.grades.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    const Text(
                      '卫生等级',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final String g in options.grades)
                          _FilterChip(
                            label: g,
                            color: g == HygieneGrade.unoccupied
                                ? const Color(0xFFB8860B)
                                : const Color(0xFF2E9E5B),
                            selected: grades.contains(g),
                            onTap: () => setSheet(() {
                              if (!grades.remove(g)) grades.add(g);
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5B6BDB).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '筛选后：晚归 ${preview.records} 条、'
                      '卫生 ${preview.rows} 个寝室、人员 ${preview.persons} 人',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: MiuixButton(
                          onPressed: () => setSheet(() {
                            kwCtrl.clear();
                            buildings = <String>{};
                            grades = Set<String>.from(
                              HygieneGrade.summaryDefaults,
                            );
                          }),
                          child: const Text('恢复默认'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MiuixButton(
                          onPressed: nothing
                              ? null
                              : () {
                                  setState(() => _filter = current());
                                  Navigator.pop(ctx);
                                },
                          colors: MiuixButtonDefaults.buttonColorsPrimary(
                            context,
                          ),
                          child: const Text('应用筛选'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    kwCtrl.dispose();
  }

  // ========== 合成 ==========

  Future<void> _merge() async {
    final AppScope scope = AppScope.of(context);
    setState(() => _busy = true);
    MergeResult result;
    try {
      result = _service.merge(_docs, filter: _filter);
      // 落库生成新记录（新 id 会插入列表顶部并持久化）；筛选后为空则不落库
      if (result.session != null && result.session!.records.isNotEmpty) {
        scope.storage.upsertSession(result.session!);
      }
      if (result.hygiene != null && result.hygiene!.rows.isNotEmpty) {
        scope.storage.upsertHygiene(result.hygiene!);
      }
      if (result.persons.isNotEmpty) {
        scope.storage.addPersons(result.persons);
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      scope.snackbar.showSnackbar('合成失败：$e');
      return;
    }

    final InspectionSession? session =
        result.session != null && result.session!.records.isNotEmpty
        ? result.session
        : null;
    final HygieneSession? hygiene =
        result.hygiene != null && result.hygiene!.rows.isNotEmpty
        ? result.hygiene
        : null;
    final List<Person> persons = result.persons;

    // 筛选后内容为空时提示，不生成空记录
    if (session == null && hygiene == null && persons.isEmpty) {
      if (mounted) setState(() => _busy = false);
      scope.snackbar.showSnackbar('当前筛选条件下没有可合成的内容');
      return;
    }

    final List<String> parts = <String>[];
    if (session != null) parts.add('晚归 ${session.records.length} 条');
    if (hygiene != null) parts.add('卫生 ${hygiene.rows.length} 个寝室');
    if (persons.isNotEmpty) parts.add('人员 ${persons.length} 人');
    scope.snackbar.showSnackbar('合成完成：${parts.join('，')}');

    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    await _askExport(session, hygiene);
  }

  /// 落库后询问是否立即导出汇总文档
  Future<void> _askExport(
    InspectionSession? session,
    HygieneSession? hygiene,
  ) async {
    final AppScope scope = AppScope.of(context);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '已生成汇总记录，是否导出文档？',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (session != null)
                ListTile(
                  leading: const Icon(Icons.nightlight_round),
                  title: const Text('导出晚归汇总 Word'),
                  subtitle: const Text('生成 .docx 并分享'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final File file = await scope.excel.exportSessionWord(
                        session,
                      );
                      await scope.excel.shareFile(file);
                    } catch (e) {
                      scope.snackbar.showSnackbar('导出失败：$e');
                    }
                  },
                ),
              if (hygiene != null) ...<Widget>[
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('导出卫生汇总 Word'),
                  subtitle: const Text('生成 .docx 并分享'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final File file = await scope.excel.exportHygieneWord(
                        hygiene,
                      );
                      await scope.excel.shareFile(file);
                    } catch (e) {
                      scope.snackbar.showSnackbar('导出失败：$e');
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: const Text('导出卫生汇总 Excel'),
                  subtitle: const Text('生成 .xlsx 并分享'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final File file = await scope.excel.exportHygiene(
                        hygiene,
                      );
                      await scope.excel.shareFile(file);
                    } catch (e) {
                      scope.snackbar.showSnackbar('导出失败：$e');
                    }
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('暂不导出'),
                subtitle: const Text('已保存在查寝记录中，稍后可随时导出'),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final int insCount = _docs
        .where((ImportedDoc d) => d.type == ImportDocType.inspection)
        .length;
    final int hygCount = _docs
        .where((ImportedDoc d) => d.type == ImportDocType.hygiene)
        .length;
    final int personCount = _docs.length - insCount - hygCount;

    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '多文档合成',
        largeTitle: '多文档合成',
        navigationIcon: MiuixIconButton(
          minWidth: 48,
          minHeight: 48,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
      ),
      content: (EdgeInsets padding) {
        return MiuixPageContent(
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 顶部说明与筛选入口随内容整体应用脚手架顶部内边距，
                  // 避免被展开的大标题遮挡；水平边距与下方筛选区、卡片统一为 20。
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, padding.top + 8, 20, 0),
                    child: MiuixText(
                      '导入本软件生成的文档（晚归 .docx、卫生 .docx / .xlsx、'
                      '人员名单 .xlsx），将按添加顺序合成一份总结文档。',
                      fontSize: 13,
                      color: colors.onBackgroundVariant,
                    ),
                  ),
                  if (_docs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          MiuixText(
                            '已选 ${_docs.length} 份（晚归 $insCount 份、'
                            '卫生 $hygCount 份、人员 $personCount 份），'
                            '长按拖动可调整顺序',
                            fontSize: 12,
                            color: colors.onBackgroundVariant,
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _openFilter,
                            icon: Icon(
                              _hasFilter
                                  ? Icons.filter_alt
                                  : Icons.filter_alt_outlined,
                              size: 18,
                              color: _hasFilter
                                  ? const Color(0xFF5B6BDB)
                                  : colors.onBackgroundVariant,
                            ),
                            label: Text(
                              _hasFilter ? '筛选已启用（点击修改）' : '设置筛选条件',
                              style: TextStyle(
                                color: _hasFilter
                                    ? const Color(0xFF5B6BDB)
                                    : colors.onBackgroundVariant,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              side: BorderSide(
                                color: _hasFilter
                                    ? const Color(0xFF5B6BDB)
                                    : colors.dividerLine,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _docs.isEmpty
                        ? _buildEmpty(colors)
                        : _buildList(padding),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: MiuixButton(
                      onPressed: (_docs.isEmpty || _busy) ? null : _merge,
                      colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.merge_type, size: 18),
                          SizedBox(width: 8),
                          Text('开始合成并生成记录'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        );
      },
      // 底部内边距把加号抬到下方全宽“开始合成”按钮之上，避免两者在右下角遮挡。
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: MiuixFloatingActionButton(
          onPressed: _busy ? null : _addFiles,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEmpty(MiuixColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.merge_type, size: 64, color: colors.onBackgroundVariant),
          const SizedBox(height: 12),
          MiuixText('还没有添加文档', color: colors.onBackgroundVariant),
          const SizedBox(height: 6),
          MiuixText(
            '点击右下角 + 选择本软件导出的文档',
            fontSize: 13,
            color: colors.onBackgroundVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildList(EdgeInsets padding) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return ReorderableListView.builder(
      // 顶部内边距已由外层说明/筛选区消费，这里只留与筛选区的间距，
      // 否则文档卡片会被整体推到屏幕中部。
      padding: EdgeInsets.fromLTRB(
        padding.left,
        8,
        padding.right,
        padding.bottom + 96,
      ),
      itemCount: _docs.length,
      onReorderItem: _reorder,
      itemBuilder: (BuildContext context, int i) {
        final ImportedDoc doc = _docs[i];
        final Color tint;
        final IconData icon;
        final String tag;
        final String detail;
        switch (doc.type) {
          case ImportDocType.hygiene:
            tint = const Color(0xFF2E9E5B);
            icon = Icons.cleaning_services_outlined;
            tag = '卫生';
            detail = '${doc.hygiene?.rows.length ?? 0} 个寝室';
          case ImportDocType.person:
            tint = const Color(0xFFB8860B);
            icon = Icons.groups_outlined;
            tag = '人员';
            detail = '${doc.persons?.length ?? 0} 人';
          case ImportDocType.inspection:
            tint = const Color(0xFF5B6BDB);
            icon = Icons.nightlight_round;
            tag = '晚归';
            detail = '${doc.session?.records.length ?? 0} 条记录';
        }
        return Padding(
          key: ValueKey<String>('merge_doc_$i'),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: MiuixCard(
            cornerRadius: 16,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: <Widget>[
                  Icon(Icons.drag_indicator, color: colors.onBackgroundVariant),
                  const SizedBox(width: 4),
                  Icon(icon, color: tint),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        MiuixText(doc.fileName, fontSize: 15, maxLines: 1),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            _MiniBadge(tag: tag, tint: tint),
                            const SizedBox(width: 8),
                            MiuixText(
                              detail,
                              fontSize: 12,
                              color: colors.onBackgroundVariant,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  MiuixIconButton(
                    minWidth: 44,
                    minHeight: 44,
                    onPressed: () => _removeDoc(i),
                    child: Icon(Icons.close, size: 20, color: colors.error),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 类型小徽标
class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.tag, required this.tint});

  final String tag;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 11,
          color: tint,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 筛选弹窗中的可选项
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = const Color(0xFF5B6BDB),
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          selected ? '✓ $label' : label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : color,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
