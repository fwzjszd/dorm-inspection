// 查寝批次编辑页
// 严格对应输出模板：
//   标题（M月d日检查宿舍，可改）
//   宿舍范围（检查人员：xxx）
//   每条记录：宿舍 姓名学号 / 床号 / 班级 / 原因 / 辅导员
// 所有字段均可直接键入或从下拉候选选择，候选来自导入的人员库与历史输入；
// 选择姓名后自动带出该人员的学号、班级、宿舍、床号、辅导员。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../main.dart';
import '../models.dart';
import '../widgets/autocomplete_field.dart';
import '../widgets/common.dart';

class SessionEditPage extends StatefulWidget {
  const SessionEditPage({super.key, this.session, this.defaultInspector = ''});

  /// 为 null 表示新建批次
  final InspectionSession? session;

  /// 新建批次时预填的查寝人员（来自设置页的默认人员）
  final String defaultInspector;

  @override
  State<SessionEditPage> createState() => _SessionEditPageState();
}

class _SessionEditPageState extends State<SessionEditPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _rangeCtrl;
  late final TextEditingController _inspectorCtrl;
  late DateTime _date;
  final List<_RecordEntry> _entries = <_RecordEntry>[];

  /// 是否正在保存，用于防抖（保存过程中禁用按钮、忽略重复点击）
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final InspectionSession? s = widget.session;
    _titleCtrl = TextEditingController(text: s?.title ?? '');
    _rangeCtrl = TextEditingController(text: s?.dormRange ?? '');
    _inspectorCtrl = TextEditingController(
      text: s?.inspector ?? widget.defaultInspector,
    );
    _date = s?.date ?? DateTime.now();
    if (s != null) {
      for (final InspectionRecord r in s.records) {
        _entries.add(_RecordEntry.fromRecord(r));
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _rangeCtrl.dispose();
    _inspectorCtrl.dispose();
    for (final _RecordEntry e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  String get _effectiveTitle => _titleCtrl.text.trim().isNotEmpty
      ? _titleCtrl.text.trim()
      : '${_date.month}月${_date.day}日检查宿舍';

  void _addRecord() {
    setState(() {
      _entries.add(_RecordEntry.empty());
    });
  }

  void _removeRecord(int index) {
    setState(() {
      _entries.removeAt(index).dispose();
    });
  }

  /// 选中姓名候选后，按人员库自动补全其他字段。
  /// [overwrite] 为 true（名单选择模式）时直接覆盖全部字段。
  void _onPickPerson(
    _RecordEntry entry,
    String name, {
    required bool overwrite,
  }) {
    final AppScope scope = AppScope.of(context);
    final List<Person> matches = scope.storage.persons
        .where((Person p) => p.name == name)
        .toList();
    if (matches.isEmpty) return;
    if (matches.length > 1) {
      // 人员库中有多个同名人员，无法判断该带出谁的信息
      scope.snackbar.showSnackbar(
        '人员库中有 ${matches.length} 个「$name」，无法自动带出信息，请手动填写',
      );
      return;
    }
    final Person person = matches.single;
    void fill(TextEditingController c, String value) {
      if (overwrite || c.text.trim().isEmpty) {
        c.text = value;
      }
    }

    setState(() {
      fill(entry.studentId, person.studentId);
      fill(entry.className, person.className);
      fill(entry.dorm, person.dorm);
      fill(entry.bed, person.bed);
      fill(entry.counselor, person.counselor);
    });
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

  InspectionSession _buildSession() {
    final List<InspectionRecord> records = _entries
        .map(
          (_RecordEntry e) => InspectionRecord(
            id: e.id,
            dorm: e.dorm.text.trim(),
            name: e.name.text.trim(),
            studentId: e.studentId.text.trim(),
            bed: e.bed.text.trim(),
            className: e.className.text.trim(),
            reason: e.reason.text.trim(),
            counselor: e.counselor.text.trim(),
          ),
        )
        .where(
          (InspectionRecord r) =>
              r.name.isNotEmpty || r.dorm.isNotEmpty || r.studentId.isNotEmpty,
        )
        .toList();
    return InspectionSession(
      id: widget.session?.id ?? 's_${DateTime.now().microsecondsSinceEpoch}',
      date: _date,
      title: _titleCtrl.text.trim(),
      dormRange: _rangeCtrl.text.trim(),
      inspector: _inspectorCtrl.text.trim(),
      merged: widget.session?.merged ?? false,
      records: records,
    );
  }

  /// 保存并按模板复制到剪切板（防抖：保存过程中忽略重复点击）
  Future<void> _saveAndCopy() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final AppScope scope = AppScope.of(context);
      final InspectionSession session = _buildSession();
      scope.storage.upsertSession(session);
      await Clipboard.setData(
        ClipboardData(text: scope.excel.buildSessionText(session)),
      );
      scope.snackbar.showSnackbar('已按模板复制，可直接粘贴发送');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final MiuixColors colors = MiuixTheme.of(context).colors;

    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '查寝批次',
        largeTitle: widget.session == null ? '新建查寝' : '编辑查寝',
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
                              '${_date.year}年${_date.month}月${_date.day}日',
                              fontSize: 16,
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                    child: AutocompleteField(
                      controller: _titleCtrl,
                      label: '标题，如 10月20日检查宿舍',
                      suggestions: scope.storage.words('dormRange'),
                      singleLine: true,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                    child: AutocompleteField(
                      controller: _rangeCtrl,
                      label: '检查宿舍范围，如 23#111、222-250',
                      suggestions: scope.storage.suggestionsFor('dormRange'),
                      singleLine: true,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                    child: AutocompleteField(
                      controller: _inspectorCtrl,
                      label: '检查人员，如 张三',
                      suggestions: scope.storage.suggestionsFor('inspector'),
                      singleLine: true,
                    ),
                  ),
                ],
              ),
              const SectionTitle('异常记录'),
              if (_entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: MiuixText(
                    '暂无异常人员，点击下方按钮添加',
                    color: colors.onBackgroundVariant,
                    textAlign: TextAlign.center,
                  ),
                ),
              for (int i = 0; i < _entries.length; i++)
                _RecordCard(
                  key: ValueKey<String>(_entries[i].id),
                  index: i + 1,
                  entry: _entries[i],
                  hasPersons: scope.storage.persons.isNotEmpty,
                  onRemove: () => _removeRecord(i),
                  onPickPerson: (String name, {required bool overwrite}) =>
                      _onPickPerson(_entries[i], name, overwrite: overwrite),
                  onRosterChanged: (bool v) =>
                      setState(() => _entries[i].fromRoster = v),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: MiuixButton(
                    onPressed: _addRecord,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.add, size: 18),
                        SizedBox(width: 8),
                        Text('添加异常人员'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: MiuixButton(
                    onPressed: _saving ? null : _saveAndCopy,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.content_copy_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('保存并复制到剪切板'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: MiuixButton(
                    onPressed: () => Navigator.of(context).pop(),
                    colors: MiuixButtonColors(
                      color: colors.error,
                      disabledColor: colors.error,
                      contentColor: Colors.white,
                      disabledContentColor: Colors.white,
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
                child: MiuixText(
                  '导出预览标题：$_effectiveTitle',
                  fontSize: 12,
                  color: colors.onBackgroundVariant,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 一条异常记录的编辑卡片
class _RecordCard extends StatelessWidget {
  const _RecordCard({
    super.key,
    required this.index,
    required this.entry,
    required this.hasPersons,
    required this.onRemove,
    required this.onPickPerson,
    required this.onRosterChanged,
  });

  final int index;
  final _RecordEntry entry;

  /// 人员库是否有人（为空时禁止切换到名单选择模式）
  final bool hasPersons;
  final VoidCallback onRemove;

  /// 选择姓名后的回调；overwrite=true 时覆盖其他字段（名单模式）
  final void Function(String name, {required bool overwrite}) onPickPerson;
  final ValueChanged<bool> onRosterChanged;

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool roster = entry.fromRoster;
    final List<String> rosterNames = scope.storage.persons
        .map((Person p) => p.name)
        .where((String s) => s.isNotEmpty)
        .toList();

    Widget field(
      TextEditingController c,
      String label,
      String suggestField, {
      ValueChanged<String>? onPick,
      bool enabled = true,
      List<String>? suggestions,
    }) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
        child: AutocompleteField(
          controller: c,
          label: label,
          enabled: enabled,
          suggestions:
              suggestions ?? scope.storage.suggestionsFor(suggestField),
          onPickPerson: onPick,
        ),
      );
    }

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
                    '记录 $index',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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
            // 录入方式单选栏：人员名单 / 自行输入
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: <Widget>[
                  _radioOption(
                    context,
                    '人员名单',
                    roster,
                    enabled: hasPersons,
                    onTap: () => onRosterChanged(true),
                  ),
                  const SizedBox(width: 28),
                  _radioOption(
                    context,
                    '自行输入',
                    !roster,
                    enabled: true,
                    onTap: () => onRosterChanged(false),
                  ),
                  if (!hasPersons)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: MiuixText(
                          '人员库为空',
                          fontSize: 12,
                          color: colors.onBackgroundVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (roster) ...<Widget>[
              // 名单模式：只选人，宿舍/学号/床号/班级/辅导员由人员库自动带出
              field(
                entry.name,
                '从人员名单选择姓名',
                'name',
                suggestions: rosterNames,
                onPick: (String v) => onPickPerson(v, overwrite: true),
              ),
              // 原因人员库中没有，仍需手工填写
              field(entry.reason, '原因，如 请假', 'reason'),
            ] else ...<Widget>[
              field(
                entry.name,
                '姓名，如 李四',
                'name',
                onPick: (String v) => onPickPerson(v, overwrite: false),
              ),
              field(entry.dorm, '宿舍，如 23#111', 'dorm'),
              field(entry.studentId, '学号，如 262010000', 'studentId'),
              field(entry.bed, '床号，如 2号床', 'bed'),
              field(entry.className, '班级，如 机械设计制造及其自动化0班', 'className'),
              field(entry.reason, '原因，如 请假', 'reason'),
              field(entry.counselor, '辅导员，如 王五', 'counselor'),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// 一个单选选项（圆形单选钮 + 文字），整块可点
  Widget _radioOption(
    BuildContext context,
    String label,
    bool selected, {
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MiuixRadioButton(
            selected: selected,
            enabled: enabled,
            onChanged: enabled ? (_) => onTap() : null,
          ),
          const SizedBox(width: 8),
          MiuixText(
            label,
            fontSize: 14,
            color: enabled
                ? colors.onBackground
                : colors.onBackgroundVariant.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

/// 一条记录对应的一组文本控制器
class _RecordEntry {
  _RecordEntry._({
    required this.id,
    required this.dorm,
    required this.name,
    required this.studentId,
    required this.bed,
    required this.className,
    required this.reason,
    required this.counselor,
  });

  factory _RecordEntry.empty() {
    return _RecordEntry._(
      id: 'r_${DateTime.now().microsecondsSinceEpoch}',
      dorm: TextEditingController(),
      name: TextEditingController(),
      studentId: TextEditingController(),
      bed: TextEditingController(),
      className: TextEditingController(),
      reason: TextEditingController(),
      counselor: TextEditingController(),
    );
  }

  factory _RecordEntry.fromRecord(InspectionRecord r) {
    return _RecordEntry._(
      id: r.id,
      dorm: TextEditingController(text: r.dorm),
      name: TextEditingController(text: r.name),
      studentId: TextEditingController(text: r.studentId),
      bed: TextEditingController(text: r.bed),
      className: TextEditingController(text: r.className),
      reason: TextEditingController(text: r.reason),
      counselor: TextEditingController(text: r.counselor),
    );
  }

  /// 是否为“从人员名单选择”模式（不持久化，保存时只取字段值）
  bool fromRoster = false;

  final String id;
  final TextEditingController dorm;
  final TextEditingController name;
  final TextEditingController studentId;
  final TextEditingController bed;
  final TextEditingController className;
  final TextEditingController reason;
  final TextEditingController counselor;

  void dispose() {
    dorm.dispose();
    name.dispose();
    studentId.dispose();
    bed.dispose();
    className.dispose();
    reason.dispose();
    counselor.dispose();
  }
}
