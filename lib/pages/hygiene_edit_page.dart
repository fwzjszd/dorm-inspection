// 卫生检查评分表编辑页
// 对应《光电与机电工程学院学生公寓内务卫生检查评分表》：
//   批次信息：日期、检查人员、检查楼栋、第几周（星期由日期自动得出）
//   每个寝室一行：8 个分项得分（地面/门面/床铺/室内摆设/墙壁及断桥窗/
//     阳台及窗户/卫生间/舍员态度）+ 奖励分 + 备注；
//   总分与评定等级自动计算，等级也可手动覆盖。
// 可按人员库中所选楼栋的宿舍名单一键自动成行。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../main.dart';
import '../models.dart';
import '../widgets/autocomplete_field.dart';
import '../widgets/common.dart';

/// 页面内所有输入框使用的紧凑内边距：
/// 默认上下各 16 时框高约 56，缩小后约 48，保证 17px 未浮动标签完整容纳。
const EdgeInsets _kFieldMargin = EdgeInsets.fromLTRB(14, 12, 14, 12);

/// 学院模板预留 20 个数据行，故评分表最多 20 个寝室
const int _kMaxDorms = 20;

class HygieneEditPage extends StatefulWidget {
  const HygieneEditPage({super.key, this.session, this.defaultInspector = ''});

  /// 为 null 表示新建
  final HygieneSession? session;

  /// 新建批次时预填的查寝人员（来自设置页的默认人员）
  final String defaultInspector;

  @override
  State<HygieneEditPage> createState() => _HygieneEditPageState();
}

class _HygieneEditPageState extends State<HygieneEditPage> {
  late final TextEditingController _inspectorCtrl;
  late final TextEditingController _buildingCtrl;
  late final TextEditingController _weekCtrl;
  late DateTime _date;
  final List<_HygieneEntry> _entries = <_HygieneEntry>[];

  /// 是否正在保存，用于防抖（保存过程中禁用按钮、忽略重复点击）
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final HygieneSession? s = widget.session;
    _inspectorCtrl = TextEditingController(
      text: s?.inspector ?? widget.defaultInspector,
    );
    _buildingCtrl = TextEditingController(text: s?.building ?? '');
    _weekCtrl = TextEditingController(text: '${s?.week ?? 1}');
    _date = s?.date ?? DateTime.now();
    if (s != null) {
      for (final HygieneRow r in s.rows) {
        _entries.add(_HygieneEntry.fromRow(r));
      }
    }
  }

  @override
  void dispose() {
    _inspectorCtrl.dispose();
    _buildingCtrl.dispose();
    _weekCtrl.dispose();
    for (final _HygieneEntry e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  void _addRow() {
    if (_entries.length >= _kMaxDorms) {
      AppScope.of(context).snackbar.showSnackbar('最多只能添加 $_kMaxDorms 个寝室');
      return;
    }
    setState(() {
      _entries.add(_HygieneEntry.empty());
    });
  }

  void _removeRow(int index) {
    setState(() {
      _entries.removeAt(index).dispose();
    });
  }

  /// 按人员库中所选楼栋的宿舍名单自动补全评分行（已存在的宿舍跳过）
  void _autoFillDorms() {
    final AppScope scope = AppScope.of(context);
    final String prefix = _buildingCtrl.text.trim();
    final List<String> dorms = scope.storage.dormsInBuilding(prefix);
    if (dorms.isEmpty) {
      scope.snackbar.showSnackbar(
        prefix.isEmpty ? '人员库中没有宿舍信息，请先在人员页导入' : '人员库中没有「$prefix」的宿舍',
      );
      return;
    }
    final Set<String> existing = _entries
        .map((_HygieneEntry e) => e.dorm.text.trim())
        .toSet();
    int added = 0;
    int skippedFull = 0;
    setState(() {
      for (final String d in dorms) {
        if (existing.contains(d)) continue;
        if (_entries.length + added >= _kMaxDorms) {
          skippedFull++;
          continue;
        }
        _entries.add(_HygieneEntry.fromDorm(d));
        added++;
      }
    });
    final String message;
    if (added == 0 && skippedFull == 0) {
      message = '该楼栋宿舍已全部在列表中';
    } else if (added == 0) {
      message = '寝室数量已达上限 $_kMaxDorms 个';
    } else if (skippedFull > 0) {
      message = '已填入 $added 个寝室，另有 $skippedFull 个因达 $_kMaxDorms 个上限未填入';
    } else {
      message = '已按人员库填入 $added 个寝室';
    }
    scope.snackbar.showSnackbar(message);
  }

  HygieneSession _buildSession() {
    final List<HygieneRow> rows = _entries
        .map(
          (_HygieneEntry e) => HygieneRow(
            id: e.id,
            dorm: e.dorm.text.trim(),
            grade: e.grade,
            bonus: double.tryParse(e.bonus.text.trim()) ?? 0,
            remark: e.remark.text.trim(),
            scores: <String, double>{
              for (final HygieneItem item in kHygieneItems)
                item.key: double.tryParse(e.score(item.key).text.trim()) ?? 0,
            },
          ),
        )
        .where((HygieneRow r) => r.dorm.isNotEmpty)
        .toList();
    return HygieneSession(
      id: widget.session?.id ?? 'h_${DateTime.now().microsecondsSinceEpoch}',
      date: _date,
      inspector: _inspectorCtrl.text.trim(),
      building: _buildingCtrl.text.trim(),
      week: int.tryParse(_weekCtrl.text.trim()) ?? 1,
      weekday: _date.weekday,
      rows: rows,
    );
  }

  /// 返回第一个超出满分上限的提示（无则返回 null）
  String? _firstOverLimitHint() {
    for (int i = 0; i < _entries.length; i++) {
      final _HygieneEntry e = _entries[i];
      for (final HygieneItem item in kHygieneItems) {
        final double? v = double.tryParse(e.score(item.key).text.trim());
        if (v != null && v > item.max) {
          final String dorm = e.dorm.text.trim();
          return '第${i + 1}个寝室${dorm.isEmpty ? '' : '（$dorm）'}'
              '的「${item.label}」得分为 ${fmtScore(v)}，超过满分 ${item.max}';
        }
      }
    }
    return null;
  }

  Future<void> _saveAndExportWord() async {
    if (_saving) return;
    final AppScope scope = AppScope.of(context);
    final String? over = _firstOverLimitHint();
    if (over != null) {
      scope.snackbar.showSnackbar('$over，请修正后再保存');
      return;
    }
    setState(() => _saving = true);
    final HygieneSession session = _buildSession();
    scope.storage.upsertHygiene(session);
    try {
      final File file = await scope.excel.exportHygieneWord(session);
      await scope.excel.shareFile(file);
      scope.snackbar.showSnackbar('已保存并导出 Word 文档');
    } catch (e) {
      scope.snackbar.showSnackbar('导出失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final List<String> buildingSuggestions = <String>{
      ...scope.storage.buildings,
      ...scope.storage.suggestionsFor('building'),
    }.toList();

    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '卫生评分表',
        largeTitle: widget.session == null ? '新建卫生检查' : '编辑卫生检查',
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
            padding: padding.add(const EdgeInsets.only(bottom: 110)),
            children: <Widget>[
              const SectionTitle('批次信息'),
              GroupCard(
                children: <Widget>[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _pickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.calendar_today, size: 20),
                          const SizedBox(width: 16),
                          Expanded(
                            child: MiuixText(
                              '${_date.year}年${_date.month}月${_date.day}日'
                              '　星期${_kWeekdayCn[_date.weekday - 1]}',
                              fontSize: 16,
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                    child: AutocompleteField(
                      controller: _inspectorCtrl,
                      label: '检查人员，如 陈伟照',
                      suggestions: scope.storage.suggestionsFor('inspector'),
                      singleLine: true,
                      insideMargin: _kFieldMargin,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                    child: AutocompleteField(
                      controller: _buildingCtrl,
                      label: '检查楼栋，如 14#',
                      suggestions: buildingSuggestions,
                      singleLine: true,
                      insideMargin: _kFieldMargin,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                    child: MiuixTextField(
                      controller: _weekCtrl,
                      label: '第几周，如 14',
                      insideMargin: _kFieldMargin,
                      singleLine: true,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SectionTitle('寝室评分'),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: MiuixButton(
                    onPressed: _autoFillDorms,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.auto_awesome_motion_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('按人员库自动填入寝室'),
                      ],
                    ),
                  ),
                ),
              ),
              if (_entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: MiuixText(
                    '暂无寝室，点击上方按钮按楼栋自动填入，或手动添加',
                    color: colors.onBackgroundVariant,
                    textAlign: TextAlign.center,
                  ),
                ),
              for (int i = 0; i < _entries.length; i++)
                _DormCard(
                  key: ValueKey<String>(_entries[i].id),
                  index: i + 1,
                  entry: _entries[i],
                  dormSuggestions: scope.storage.dormsInBuilding(
                    _buildingCtrl.text.trim(),
                  ),
                  onChanged: () => setState(() {}),
                  onRemove: () => _removeRow(i),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: MiuixButton(
                    onPressed: _addRow,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.add, size: 18),
                        SizedBox(width: 8),
                        Text('手动添加寝室'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: MiuixButton(
                    onPressed: _saving ? null : _saveAndExportWord,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.description_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('保存并导出word文档'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: MiuixButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    colors: const MiuixButtonColors(
                      color: Colors.red,
                      disabledColor: Colors.red,
                      contentColor: Colors.white,
                      disabledContentColor: Colors.white,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.close_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('取消'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const List<String> _kWeekdayCn = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];
}

/// 一个寝室的评分卡片
class _DormCard extends StatelessWidget {
  const _DormCard({
    super.key,
    required this.index,
    required this.entry,
    required this.dormSuggestions,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _HygieneEntry entry;
  final List<String> dormSuggestions;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  double get _total {
    double sum = 0;
    for (final HygieneItem item in kHygieneItems) {
      sum += double.tryParse(entry.score(item.key).text.trim()) ?? 0;
    }
    sum += double.tryParse(entry.bonus.text.trim()) ?? 0;
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final String autoGrade = HygieneGrade.suggest(_total);
    final String grade = entry.grade.isEmpty ? autoGrade : entry.grade;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: MiuixCard(
        cornerRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 4),
              child: Row(
                children: <Widget>[
                  MiuixText(
                    '寝室 $index',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '总分 ${fmtScore(_total)} · $grade',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  MiuixIconButton(
                    minWidth: 48,
                    minHeight: 48,
                    onPressed: onRemove,
                    child: Icon(Icons.close, size: 20, color: colors.error),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: AutocompleteField(
                controller: entry.dorm,
                label: '所在寝室号，如 14#101',
                suggestions: dormSuggestions,
                singleLine: true,
                insideMargin: _kFieldMargin,
              ),
            ),
            // 等级选择：自动 / 优秀 / 良好 / 合格 / 不合格
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _gradeChip(context, '自动', '', autoGrade),
                  for (final String g in HygieneGrade.values)
                    _gradeChip(context, g, g, autoGrade),
                ],
              ),
            ),
            // 8 个分项得分，两列布局（每格自适应高度，超上限时下方显示红色提示）
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < kHygieneItems.length; i += 2)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: _scoreField(context, kHygieneItems[i]),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: i + 1 < kHygieneItems.length
                                ? _scoreField(context, kHygieneItems[i + 1])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: MiuixTextField(
                controller: entry.bonus,
                label: '奖励分（无则留空）',
                insideMargin: _kFieldMargin,
                singleLine: true,
                keyboardType: TextInputType.number,
                onChanged: (_) => onChanged(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: AutocompleteField(
                controller: entry.remark,
                label: '备注（无则留空）',
                suggestions: const <String>[],
                singleLine: true,
                insideMargin: _kFieldMargin,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreField(BuildContext context, HygieneItem item) {
    return _ScoreField(
      controller: entry.score(item.key),
      label: '${item.label}（满分${item.max}）',
      max: item.max.toDouble(),
      onChanged: onChanged,
    );
  }

  Widget _gradeChip(
    BuildContext context,
    String label,
    String value,
    String autoGrade,
  ) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool selected = entry.grade == value;
    // “自动”档位下，实际生效等级用小圆点颜色提示
    final bool activeHint = value.isEmpty || value == autoGrade;
    return GestureDetector(
      onTap: () {
        entry.grade = value;
        onChanged();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary
              : colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? colors.primary
                : colors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? Colors.white : colors.onBackground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (value.isNotEmpty && activeHint && !selected) ...<Widget>[
              const SizedBox(width: 5),
              Icon(Icons.circle, size: 7, color: colors.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分项得分输入框：只接受数字与一个小数点（最多 1 位小数），
/// 超过满分上限时边框变红并给出提示；总分由外层自动计算。
class _ScoreField extends StatefulWidget {
  const _ScoreField({
    required this.controller,
    required this.label,
    required this.max,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final double max;
  final VoidCallback onChanged;

  @override
  State<_ScoreField> createState() => _ScoreFieldState();
}

class _ScoreFieldState extends State<_ScoreField> {
  /// 过滤字母、符号等非法字符：只保留数字与最多一个小数点（小数点后限 1 位）
  static String _sanitize(String raw) {
    final StringBuffer sb = StringBuffer();
    bool hasDot = false;
    int decimals = 0;
    for (final int code in raw.codeUnits) {
      if (code == 0x2E) {
        // '.'
        if (hasDot) continue;
        hasDot = true;
        sb.write('.');
      } else if (code >= 0x30 && code <= 0x39) {
        // 0-9
        if (hasDot) {
          if (decimals >= 1) continue;
          decimals++;
        }
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }

  bool get _over {
    final double? v = double.tryParse(widget.controller.text.trim());
    return v != null && v > widget.max;
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextFieldColors baseColors =
        MiuixTextFieldDefaults.textFieldColors(context);
    final bool over = _over;

    Widget field = MiuixTextField(
      controller: widget.controller,
      label: widget.label,
      insideMargin: _kFieldMargin,
      singleLine: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      colors: over
          ? MiuixTextFieldColors(
              backgroundColor: baseColors.backgroundColor,
              labelColor: colors.error,
              borderColor: colors.error,
            )
          : null,
      onChanged: (String v) {
        final String clean = _sanitize(v);
        if (clean != v) {
          widget.controller.value = TextEditingValue(
            text: clean,
            selection: TextSelection.collapsed(offset: clean.length),
          );
        }
        widget.onChanged();
      },
    );
    if (over) {
      field = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            MiuixTextFieldDefaults.cornerRadius,
          ),
          border: Border.all(color: colors.error, width: 2),
        ),
        child: field,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        field,
        if (over)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 3),
            child: Text(
              '不能超过满分 ${fmtScore(widget.max)}',
              style: TextStyle(fontSize: 11, color: colors.error),
            ),
          ),
      ],
    );
  }
}

/// 一个寝室评分行对应的一组控制器
class _HygieneEntry {
  _HygieneEntry._({
    required this.id,
    required this.dorm,
    required this.bonus,
    required this.remark,
    required this.scoreCtrls,
    this.grade = '',
  });

  factory _HygieneEntry.empty() {
    return _HygieneEntry._(
      id: 'hr_${DateTime.now().microsecondsSinceEpoch}',
      dorm: TextEditingController(),
      bonus: TextEditingController(),
      remark: TextEditingController(),
      scoreCtrls: Map<String, TextEditingController>.fromEntries(
        kHygieneItems.map(
          (HygieneItem e) => MapEntry<String, TextEditingController>(
            e.key,
            TextEditingController(),
          ),
        ),
      ),
    );
  }

  factory _HygieneEntry.fromDorm(String dorm) {
    return _HygieneEntry.empty()..dorm.text = dorm;
  }

  factory _HygieneEntry.fromRow(HygieneRow r) {
    return _HygieneEntry._(
      id: r.id,
      dorm: TextEditingController(text: r.dorm),
      bonus: TextEditingController(text: r.bonus == 0 ? '' : fmtScore(r.bonus)),
      remark: TextEditingController(text: r.remark),
      grade: r.grade,
      scoreCtrls: Map<String, TextEditingController>.fromEntries(
        kHygieneItems.map(
          (HygieneItem e) => MapEntry<String, TextEditingController>(
            e.key,
            TextEditingController(
              text: (r.scores[e.key] ?? 0) == 0
                  ? ''
                  : fmtScore(r.scores[e.key] ?? 0),
            ),
          ),
        ),
      ),
    );
  }

  final String id;
  final TextEditingController dorm;
  final TextEditingController bonus;
  final TextEditingController remark;
  final Map<String, TextEditingController> scoreCtrls;

  /// 手选等级，空表示按总分自动判定
  String grade;

  TextEditingController score(String key) => scoreCtrls[key]!;

  void dispose() {
    dorm.dispose();
    bonus.dispose();
    remark.dispose();
    for (final TextEditingController c in scoreCtrls.values) {
      c.dispose();
    }
  }
}
