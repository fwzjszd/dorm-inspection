// 人员库管理页
// 导入 Excel 批量添加人员、下载导入模板、查看 / 编辑 / 删除人员

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../main.dart';
import '../models.dart';
import '../widgets/common.dart';

class PersonPage extends StatefulWidget {
  const PersonPage({super.key});

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  bool _busy = false;
  String _keyword = '';

  /// 当前展开滑动按钮的条目 id（同时只允许一个展开）
  final ValueNotifier<String?> _activeTile = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _activeTile.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final AppScope scope = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final List<Person>? incoming = await scope.excel.pickAndImportPersons();
      if (incoming == null) {
        // 用户取消文件选择
        return;
      }
      if (incoming.isEmpty) {
        scope.snackbar.showSnackbar('未在 Excel 中识别到人员');
        return;
      }
      final int added = scope.storage.addPersons(incoming);
      scope.snackbar.showSnackbar(
        '识别到 ${incoming.length} 人，新增 $added 人（已自动去重）',
      );
    } catch (e) {
      scope.snackbar.showSnackbar('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadTemplate() async {
    final AppScope scope = AppScope.of(context);
    try {
      final file = await scope.excel.exportPersonTemplate();
      await scope.excel.shareFile(file);
    } catch (e) {
      scope.snackbar.showSnackbar('模板生成失败：$e');
    }
  }

  Future<void> _clearAll() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空人员库'),
        content: const Text('将删除全部已导入人员，确定继续吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      AppScope.of(context).storage.clearPersons();
      AppScope.of(context).snackbar.showSnackbar('已清空人员库');
    }
  }

  Future<void> _deletePerson(Person p) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除人员'),
        content: Text('确定删除「${p.name.isEmpty ? '未命名' : p.name}」吗？'),
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
    if (ok == true && mounted) {
      AppScope.of(context).storage.deletePerson(p.id);
      AppScope.of(context).snackbar.showSnackbar('已删除');
    }
  }

  /// 弹出人员信息对话框：传入人员为编辑，不传为手动添加
  Future<void> _showPersonDialog([Person? p]) async {
    final List<TextEditingController> ctrls = <TextEditingController>[
      TextEditingController(text: p?.name ?? ''),
      TextEditingController(text: p?.studentId ?? ''),
      TextEditingController(text: p?.className ?? ''),
      TextEditingController(text: p?.dorm ?? ''),
      TextEditingController(text: p?.bed ?? ''),
      TextEditingController(text: p?.counselor ?? ''),
    ];
    final List<({String label, String hint})> fields =
        <({String label, String hint})>[
          (label: '姓名', hint: '如 李四'),
          (label: '学号', hint: '如 262010000'),
          (label: '班级', hint: '如 机械设计制造及其自动化0班'),
          (label: '宿舍', hint: '如 23#111'),
          (label: '床号', hint: '如 2号床'),
          (label: '辅导员', hint: '如 王五'),
        ];

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AlertDialog(
          title: Text(p == null ? '添加人员' : '编辑人员'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: MiuixTextField(
                      controller: ctrls[i],
                      label: '${fields[i].label}（${fields[i].hint}）',
                      singleLine: true,
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      final AppScope scope = AppScope.of(context);
      final String name = ctrls[0].text.trim();
      if (name.isEmpty) {
        scope.snackbar.showSnackbar('姓名不能为空');
      } else {
        // 用副本承载编辑结果，确认后才写回 store，避免中途取消污染原对象
        final Person draft = Person(
          id: p?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          studentId: ctrls[1].text.trim(),
          className: ctrls[2].text.trim(),
          dorm: ctrls[3].text.trim(),
          bed: ctrls[4].text.trim(),
          counselor: ctrls[5].text.trim(),
        );
        if (p == null) {
          scope.storage.addPerson(draft);
          scope.snackbar.showSnackbar('已添加');
        } else {
          scope.storage.updatePerson(draft);
          scope.snackbar.showSnackbar('已保存');
        }
      }
    }
    for (final TextEditingController c in ctrls) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final List<Person> all = scope.storage.persons;
    final String kw = _keyword.trim().toLowerCase();
    final List<Person> persons = kw.isEmpty
        ? all
        : all
              .where(
                (Person p) =>
                    p.name.toLowerCase().contains(kw) ||
                    p.studentId.toLowerCase().contains(kw) ||
                    p.dorm.toLowerCase().contains(kw) ||
                    p.className.toLowerCase().contains(kw),
              )
              .toList();
    final MiuixColors colors = MiuixTheme.of(context).colors;

    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '人员库',
        largeTitle: '人员库（${all.length}）',
        navigationIcon: MiuixIconButton(
          minWidth: 48,
          minHeight: 48,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        actions: <Widget>[
          MiuixIconButton(
            minWidth: 48,
            minHeight: 48,
            onPressed: () => _showPersonDialog(),
            child: const Icon(Icons.person_add_alt_1_rounded, size: 22),
          ),
          if (all.isNotEmpty)
            MiuixIconButton(
              minWidth: 48,
              minHeight: 48,
              onPressed: _clearAll,
              child: Icon(Icons.delete_sweep_outlined, color: colors.error),
            ),
        ],
      ),
      content: (EdgeInsets padding) {
        return MiuixPageContent(
          child: Column(
            children: <Widget>[
              Padding(
                padding: padding.copyWith(bottom: 0),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: MiuixButton(
                              onPressed: _busy ? null : _import,
                              colors: MiuixButtonDefaults.buttonColorsPrimary(
                                context,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  if (_busy)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.file_upload_outlined,
                                      size: 18,
                                    ),
                                  const SizedBox(width: 8),
                                  Text(_busy ? '导入中…' : '导入人员 Excel'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          MiuixButton(
                            onPressed: _downloadTemplate,
                            child: const Text('下载模板'),
                          ),
                        ],
                      ),
                    ),
                    if (all.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                        // 胶囊形搜索框，与液态玻璃底栏风格统一
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: MiuixTextField(
                            label: '搜索姓名 / 学号 / 宿舍 / 班级',
                            leadingIcon: const Icon(Icons.search, size: 20),
                            onChanged: (String v) =>
                                setState(() => _keyword = v),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.table_chart_outlined,
                                size: 64,
                                color: colors.onBackgroundVariant,
                              ),
                              const SizedBox(height: 12),
                              MiuixText(
                                '人员库为空',
                                color: colors.onBackgroundVariant,
                              ),
                              const SizedBox(height: 6),
                              MiuixText(
                                '点右上角添加单个人员，或用 Excel 批量导入',
                                fontSize: 13,
                                color: colors.onBackgroundVariant,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : persons.isEmpty
                    ? Center(
                        child: MiuixText(
                          '没有匹配「$_keyword」的人员',
                          color: colors.onBackgroundVariant,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 2, 0, 24),
                        itemCount: persons.length,
                        itemBuilder: (BuildContext context, int i) {
                          final Person p = persons[i];
                          return SlideActionTile(
                            tag: p.id,
                            activeNotifier: _activeTile,
                            onTap: () => _showPersonDialog(p),
                            actions: <SlideTileAction>[
                              SlideTileAction(
                                icon: Icons.edit_rounded,
                                color: colors.primary,
                                onTap: () => _showPersonDialog(p),
                              ),
                              SlideTileAction(
                                icon: Icons.delete_rounded,
                                color: colors.error,
                                onTap: () => _deletePerson(p),
                              ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: MiuixCard(
                                cornerRadius: 18,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            MiuixText(
                                              p.name.isEmpty ? '(未命名)' : p.name,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            const SizedBox(height: 4),
                                            MiuixText(
                                              <String>[
                                                if (p.studentId.isNotEmpty)
                                                  p.studentId,
                                                if (p.dorm.isNotEmpty) p.dorm,
                                                if (p.bed.isNotEmpty) p.bed,
                                                if (p.className.isNotEmpty)
                                                  p.className,
                                                if (p.counselor.isNotEmpty)
                                                  '辅导员：${p.counselor}',
                                              ].join('  ·  '),
                                              fontSize: 12,
                                              color: colors.onBackgroundVariant,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
