// 卫生检查评分表编辑页
// 对应《光电与机电工程学院学生公寓内务卫生检查评分表》：
//   批次信息：日期、检查人员、检查楼栋、第几周（星期由日期自动得出）
//   每个寝室一行：8 个分项得分（地面/门面/床铺/室内摆设/墙壁及断桥窗/
//     阳台及窗户/卫生间/舍员态度）+ 奖励分 + 备注；
//   总分与评定等级自动计算，等级也可手动覆盖。
// 宿舍号只需填写房号（如 101），保存时与楼栋（如 23#）自动合成为完整寝室号（23#101）。
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

/// 分项得分输入框统一高度：上下内边距 24 + 两行 17px 标签（约 44）+ 余量，
/// 保证任意分项标签换行时同排两个输入框高度都一致。
const double _kScoreFieldHeight = 72;

/// 学院模板预留 20 个数据行，故评分表最多 20 个寝室
const int _kMaxDorms = 20;

/// 由楼栋前缀与房号合成完整寝室号（如 23# + 101 → 23#101）。
/// 房号本身已含楼栋（含 #）时原样使用；楼栋漏写 # 时自动补全。
String composeDorm(String building, String room) {
  final String b = building.trim();
  final String r = room.trim();
  if (r.isEmpty) return '';
  if (r.contains('#')) return r;
  if (b.isEmpty) return r;
  return b.endsWith('#') ? '$b$r' : '$b#$r';
}

/// 从完整寝室号中剥离楼栋前缀，得到纯房号（用于编辑旧数据时的输入框回显）。
String roomOf(String building, String dorm) {
  final String b = building.trim();
  final String d = dorm.trim();
  if (b.isNotEmpty && d.startsWith(b) && d.length > b.length) {
    return d.substring(b.length);
  }
  final int hash = d.indexOf('#');
  if (hash >= 0 && hash < d.length - 1) return d.substring(hash + 1);
  return d;
}

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

  /// 页面滚动控制器：保存校验失败时自动滚动到第一张出错的寝室卡片
  final ScrollController _scrollController = ScrollController();

  /// 各寝室卡片对应的 GlobalKey（用于保存失败时 ensureVisible 定位）
  final Map<String, GlobalKey> _cardKeys = <String, GlobalKey>{};

  /// 保存校验未通过的卡片：entryId -> 错误信息，对应卡片顶部显示红条
  final Map<String, String> _errors = <String, String>{};

  GlobalKey _cardKeyFor(_HygieneEntry e) =>
      _cardKeys.putIfAbsent(e.id, () => GlobalKey());

  /// 卡片内任意输入变化时清除该卡的错误标记
  void _clearError(String entryId) {
    if (_errors.remove(entryId) != null) setState(() {});
  }

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
        _entries.add(_HygieneEntry.fromRow(r, _buildingCtrl.text));
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
    _scrollController.dispose();
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
      final _HygieneEntry e = _entries.removeAt(index);
      _cardKeys.remove(e.id);
      _errors.remove(e.id);
      e.dispose();
    });
  }

  /// 按人员库中所选楼栋的宿舍名单自动补全评分行（已存在的房号跳过）
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
        final String room = roomOf(prefix, d);
        if (existing.contains(room)) continue;
        if (_entries.length + added >= _kMaxDorms) {
          skippedFull++;
          continue;
        }
        _entries.add(_HygieneEntry.fromRoom(room));
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
    final String building = _buildingCtrl.text.trim();
    final List<HygieneRow> rows = _entries
        .map(
          (_HygieneEntry e) => HygieneRow(
            id: e.id,
            dorm: composeDorm(building, e.dorm.text),
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
      building: building,
      week: int.tryParse(_weekCtrl.text.trim()) ?? 1,
      weekday: _date.weekday,
      rows: rows,
    );
  }

  /// 保存前校验错误
  _SaveError? _validate(int index, _HygieneEntry e, String building) {
    final String dorm = composeDorm(building, e.dorm.text);
    // 寝室号与所有分值、奖励分都为空：视为空行，导出时同样会被过滤，跳过
    bool hasAnyScore = false;
    for (final HygieneItem item in kHygieneItems) {
      final double? v = double.tryParse(e.score(item.key).text.trim());
      if (v == null) continue;
      hasAnyScore = true;
      // 分数不符合规范：超过分项满分
      if (v > item.max) {
        return _SaveError(
          index,
          e.id,
          dorm,
          '「${item.label}」得分为 ${fmtScore(v)}，超过满分 ${fmtScore(item.max.toDouble())}，分数不符合规范',
        );
      }
    }
    final double? bonus = double.tryParse(e.bonus.text.trim());
    if (bonus != null && bonus != 0) hasAnyScore = true;
    if (dorm.isEmpty && hasAnyScore) {
      return _SaveError(index, e.id, dorm, '未填写寝室号');
    }
    // 总分判定等级（含不合格、优秀）与总分超 100（奖励分累加）均不限制保存。
    return null;
  }

  Future<void> _saveAndExportWord() async {
    if (_saving) return;
    final AppScope scope = AppScope.of(context);
    final String building = _buildingCtrl.text.trim();
    _SaveError? firstError;
    final Map<String, String> errorMap = <String, String>{};
    for (int i = 0; i < _entries.length; i++) {
      final _SaveError? err = _validate(i, _entries[i], building);
      if (err != null) {
        errorMap[err.entryId] = err.message;
        firstError ??= err;
      }
    }
    if (firstError != null) {
      setState(
        () => _errors
          ..clear()
          ..addAll(errorMap),
      );
      final _SaveError e = firstError;
      scope.snackbar.showSnackbar(
        '第${e.index + 1}个寝室${e.dorm.isEmpty ? '' : '（${e.dorm}）'}${e.message}，请修正后再保存',
      );
      // 自动跳转到第一张出错卡片；未渲染时按卡片序号估算滚动位置兜底
      final _SaveError targetErr = firstError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? ctx = _cardKeys[targetErr.entryId]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.1,
          );
        } else if (_scrollController.hasClients) {
          final double maxExtent = _scrollController.position.maxScrollExtent;
          // 批次信息两组卡片约 420，其后每张寝室卡片约 500
          final double target = (420.0 + targetErr.index * 500.0)
              .clamp(0.0, maxExtent)
              .toDouble();
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      return;
    }
    setState(() {
      _errors.clear();
      _saving = true;
    });
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
    final String building = _buildingCtrl.text.trim();
    final List<String> buildingSuggestions = <String>{
      ...scope.storage.buildings,
      ...scope.storage.suggestionsFor('building'),
    }.toList();
    final List<String> roomSuggestions = scope.storage
        .dormsInBuilding(building)
        .map((String d) => roomOf(building, d))
        .toList();

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
            controller: _scrollController,
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
                      label: '检查楼栋，如 23#',
                      suggestions: buildingSuggestions,
                      singleLine: true,
                      insideMargin: _kFieldMargin,
                      // 切换楼栋后刷新各寝室的房号候选与合成预览
                      onChanged: (_) => setState(() {}),
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
                  key: _cardKeyFor(_entries[i]),
                  index: i + 1,
                  entry: _entries[i],
                  building: building,
                  dormSuggestions: roomSuggestions,
                  errorText: _errors[_entries[i].id],
                  onFieldChanged: () => _clearError(_entries[i].id),
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

/// 一个寝室的评分卡片。
/// 卡片内部输入变化只重建本卡（监听各自的 controller），
/// 不触发页面级 setState，避免整页 20 卡重建导致输入掉焦。
class _DormCard extends StatefulWidget {
  const _DormCard({
    super.key,
    required this.index,
    required this.entry,
    required this.building,
    required this.dormSuggestions,
    required this.errorText,
    required this.onFieldChanged,
    required this.onRemove,
  });

  final int index;
  final _HygieneEntry entry;

  /// 当前批次的楼栋前缀，用于把房号实时合成为完整寝室号预览
  final String building;
  final List<String> dormSuggestions;

  /// 保存校验失败时卡片顶部显示的错误信息（null 表示无错误）
  final String? errorText;

  /// 任意输入框内容变化时回调（用于清除该卡的错误标记）
  final VoidCallback onFieldChanged;
  final VoidCallback onRemove;

  @override
  State<_DormCard> createState() => _DormCardState();
}

class _DormCardState extends State<_DormCard> {
  @override
  void initState() {
    super.initState();
    widget.entry.dorm.addListener(_onFieldChanged);
    widget.entry.bonus.addListener(_onFieldChanged);
    widget.entry.remark.addListener(_onFieldChanged);
    for (final TextEditingController c in widget.entry.scoreCtrls.values) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    widget.entry.dorm.removeListener(_onFieldChanged);
    widget.entry.bonus.removeListener(_onFieldChanged);
    widget.entry.remark.removeListener(_onFieldChanged);
    for (final TextEditingController c in widget.entry.scoreCtrls.values) {
      c.removeListener(_onFieldChanged);
    }
    super.dispose();
  }

  void _onFieldChanged() {
    widget.onFieldChanged();
    if (mounted) setState(() {});
  }

  /// 切换「无人宿舍」开关：
  /// 打开 → 清空 8 个分项得分与奖励分，备注自动填「无人宿舍」，除寝室号外全卡输入框置灰；
  /// 关闭 → 移除自动填入的备注，恢复编辑。
  void _toggleUnoccupied(bool value) {
    final _HygieneEntry e = widget.entry;
    setState(() {
      e.lockedUnoccupied = value;
      if (value) {
        for (final TextEditingController c in e.scoreCtrls.values) {
          c.clear();
        }
        e.bonus.clear();
        e.grade = '';
        e.remark.text = HygieneGrade.unoccupied;
      } else if (e.remark.text.trim() == HygieneGrade.unoccupied) {
        e.remark.clear();
      }
    });
    widget.onFieldChanged();
  }

  double get _total {
    double sum = 0;
    for (final HygieneItem item in kHygieneItems) {
      sum += double.tryParse(widget.entry.score(item.key).text.trim()) ?? 0;
    }
    sum += double.tryParse(widget.entry.bonus.text.trim()) ?? 0;
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final _HygieneEntry entry = widget.entry;
    final bool unoccupied = entry.lockedUnoccupied;
    final String autoGrade = HygieneGrade.suggest(_total);
    final String grade = entry.grade.isEmpty ? autoGrade : entry.grade;
    final String fullDorm = composeDorm(widget.building, entry.dorm.text);
    final String? errorText = widget.errorText;

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
                    '寝室 ${widget.index}',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(width: 10),
                  // 占据删除按钮前的全部剩余空间，避免与 Spacer 平分导致徽标被压窄；
                  // Align 保证短文本时徽标只占内容宽度，长文本才省略。
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (unoccupied
                                      ? const Color(0xFFB8860B)
                                      : colors.primary)
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unoccupied
                              ? HygieneGrade.unoccupied
                              : '总分 ${fmtScore(_total)} · $grade',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: unoccupied
                                ? const Color(0xFFB8860B)
                                : colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 无人宿舍开关：打开后除寝室号外全卡输入框置灰，备注自动填「无人宿舍」
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleUnoccupied(!unoccupied),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        children: <Widget>[
                          Text(
                            '无人',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onBackground,
                            ),
                          ),
                          const SizedBox(width: 6),
                          MiuixSwitch(
                            value: unoccupied,
                            onChanged: _toggleUnoccupied,
                          ),
                        ],
                      ),
                    ),
                  ),
                  MiuixIconButton(
                    minWidth: 48,
                    minHeight: 48,
                    onPressed: widget.onRemove,
                    child: Icon(Icons.close, size: 20, color: colors.error),
                  ),
                ],
              ),
            ),
            // 保存校验错误提示条：红色边框 + 错误信息
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colors.error.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.error_outline, size: 16, color: colors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorText,
                          style: TextStyle(fontSize: 12, color: colors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AutocompleteField(
                    controller: entry.dorm,
                    label: '寝室号（只填房号，不含楼栋），如 101',
                    suggestions: widget.dormSuggestions,
                    singleLine: true,
                    insideMargin: _kFieldMargin,
                  ),
                  // 固定高度槽位：实时提示将填入第一列的完整寝室号，
                  // 无论显示与否都不改变树结构，避免输入框重挂载掉焦
                  SizedBox(
                    height: 18,
                    child: fullDorm.isEmpty
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(left: 4, top: 3),
                            child: Text(
                              '自动合成为：$fullDorm',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onBackgroundVariant,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            // 等级选择：自动 / 优秀 / 良好 / 合格 / 不合格（无人宿舍时禁用）
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
              child: Opacity(
                opacity: unoccupied ? 0.4 : 1,
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
            ),
            // 8 个分项得分，两列布局；每个输入框固定等高，标签换行也不会
            // 造成同排两个框高低不一（超上限仅在固定槽位内红字提示）
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
                            child: _scoreField(
                              context,
                              kHygieneItems[i],
                              !unoccupied,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: i + 1 < kHygieneItems.length
                                ? _scoreField(
                                    context,
                                    kHygieneItems[i + 1],
                                    !unoccupied,
                                  )
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
                enabled: !unoccupied,
                keyboardType: TextInputType.number,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: AutocompleteField(
                controller: entry.remark,
                label: '备注（无则留空）',
                suggestions: const <String>[],
                singleLine: true,
                enabled: !unoccupied,
                insideMargin: _kFieldMargin,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreField(BuildContext context, HygieneItem item, bool enabled) {
    return _ScoreField(
      controller: widget.entry.score(item.key),
      label: '${item.label}（满分${item.max}）',
      max: item.max.toDouble(),
      enabled: enabled,
    );
  }

  Widget _gradeChip(
    BuildContext context,
    String label,
    String value,
    String autoGrade,
  ) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool selected = widget.entry.grade == value;
    // “自动”档位下，实际生效等级用小圆点颜色提示
    final bool activeHint = value.isEmpty || value == autoGrade;
    final bool disabled = widget.entry.lockedUnoccupied;
    return GestureDetector(
      onTap: disabled
          ? null
          : () {
              setState(() => widget.entry.grade = value);
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

/// 非法字符过滤结果：[text] 为过滤后的文本，[cursor] 为对应的光标位置
class _SanitizedResult {
  const _SanitizedResult(this.text, this.cursor);

  final String text;
  final int cursor;
}

/// 分项得分输入框：只接受数字与一个小数点（最多 1 位小数）。
/// 超过满分时仅把边框/标签变红并在固定槽位提示，绝不增减 widget 树节点，
/// 也不关闭键盘或抢夺焦点；总分由外层卡片自动计算。
class _ScoreField extends StatefulWidget {
  const _ScoreField({
    required this.controller,
    required this.label,
    required this.max,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final double max;

  /// 无人宿舍锁定时置灰禁用
  final bool enabled;

  @override
  State<_ScoreField> createState() => _ScoreFieldState();
}

class _ScoreFieldState extends State<_ScoreField> {
  /// 防止程序化回写 controller 时递归触发监听
  bool _suppressing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// 过滤字母、符号等非法字符：只保留数字与最多一个小数点（小数点后限 1 位），
  /// 同时按被过滤字符的位置把光标移动到正确处（而非强制跳到末尾）。
  _SanitizedResult _sanitize(String raw, TextSelection selection) {
    final int rawLen = raw.length;
    final int oldCursor =
        selection.baseOffset < 0 || selection.baseOffset > rawLen
        ? rawLen
        : selection.baseOffset;
    final StringBuffer sb = StringBuffer();
    bool hasDot = false;
    int decimals = 0;
    int newCursor = 0;
    for (int i = 0; i < rawLen; i++) {
      final int code = raw.codeUnitAt(i);
      bool kept = false;
      if (code == 0x2E) {
        // '.'
        if (!hasDot) {
          hasDot = true;
          sb.write('.');
          kept = true;
        }
      } else if (code >= 0x30 && code <= 0x39) {
        // 0-9
        if (hasDot) {
          if (decimals >= 1) continue;
          decimals++;
        }
        sb.writeCharCode(code);
        kept = true;
      }
      if (kept && i < oldCursor) newCursor = sb.length;
    }
    // 光标原本就在末尾（常见于末尾输入被过滤）时，保持在结果末尾
    if (oldCursor >= rawLen) newCursor = sb.length;
    return _SanitizedResult(sb.toString(), newCursor);
  }

  void _onTextChanged() {
    if (_suppressing) return;
    final String raw = widget.controller.text;
    final _SanitizedResult res = _sanitize(raw, widget.controller.selection);
    if (res.text != raw) {
      _suppressing = true;
      widget.controller.value = TextEditingValue(
        text: res.text,
        selection: TextSelection.collapsed(offset: res.cursor),
      );
      _suppressing = false;
    }
    if (mounted) setState(() {});
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 固定高度：长标签（如「墙壁及断桥窗（满分5）」）换行成两行时，
        // 其余单行标签的输入框也保持相同高度，同排两框严格等高
        SizedBox(
          height: _kScoreFieldHeight,
          child: MiuixTextField(
            controller: widget.controller,
            label: widget.label,
            insideMargin: _kFieldMargin,
            singleLine: true,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // 超限只换配色，MiuixTextField 始终是树中同一个节点，不会重挂载
            colors: over
                ? MiuixTextFieldColors(
                    backgroundColor: baseColors.backgroundColor,
                    labelColor: colors.error,
                    borderColor: colors.error,
                  )
                : null,
          ),
        ),
        // 固定高度的提示槽位：超限与否树结构完全一致，仅文字颜色/内容变化
        SizedBox(
          height: 17,
          child: over
              ? Padding(
                  padding: const EdgeInsets.only(left: 4, top: 3),
                  child: Text(
                    '不能超过满分 ${fmtScore(widget.max)}',
                    style: TextStyle(fontSize: 11, color: colors.error),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

/// 一个寝室评分行对应的一组控制器。
/// 注意：[dorm] 中只保存房号（不含楼栋前缀），保存时再与楼栋合成。
class _HygieneEntry {
  _HygieneEntry._({
    required this.id,
    required this.dorm,
    required this.bonus,
    required this.remark,
    required this.scoreCtrls,
    this.grade = '',
    this.lockedUnoccupied = false,
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

  factory _HygieneEntry.fromRoom(String room) {
    return _HygieneEntry.empty()..dorm.text = room;
  }

  factory _HygieneEntry.fromRow(HygieneRow r, String building) {
    return _HygieneEntry._(
      id: r.id,
      dorm: TextEditingController(text: roomOf(building, r.dorm)),
      bonus: TextEditingController(text: r.bonus == 0 ? '' : fmtScore(r.bonus)),
      remark: TextEditingController(text: r.remark),
      grade: r.grade,
      lockedUnoccupied: r.isUnoccupied,
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

  /// 「无人宿舍」开关是否打开：打开时除寝室号外全卡输入框置灰、备注为「无人宿舍」
  bool lockedUnoccupied;

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

/// 保存前校验发现的错误（用于提示、卡片红条与自动跳转定位）
class _SaveError {
  const _SaveError(this.index, this.entryId, this.dorm, this.message);

  /// 卡片在列表中的序号（从 0 开始，提示文案中 +1）
  final int index;

  /// 对应的 _HygieneEntry.id
  final String entryId;

  /// 合成后的完整寝室号（可能为空）
  final String dorm;

  /// 卡片上显示的错误信息
  final String message;
}
