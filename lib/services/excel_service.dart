// Excel 服务
// 1. 从用户选择的 Excel 智能识别列并导入人员
// 2. 按查寝模板导出 Excel
// 3. 生成空白人员导入模板

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models.dart';
import 'file_io.dart';

/// 人员字段 -> Excel 表头可能出现的关键词
const Map<String, List<String>> _headerKeywords = <String, List<String>>{
  'name': <String>['姓名', '名字', '名称', 'name'],
  'studentId': <String>['学号', '学籍号', 'student', 'id', '编号'],
  'className': <String>['班级', '专业班级', 'class', '专业'],
  'dorm': <String>['宿舍', '寝室', '宿舍号', '寝室号', 'dorm', '房间'],
  'bed': <String>['床号', '床位', '床铺', 'bed'],
  'counselor': <String>['辅导员', '班主任', '导师', 'counselor'],
};

/// 无表头时的默认列顺序（从第 1 列起）
const List<String> _fallbackOrder = <String>[
  'name',
  'studentId',
  'className',
  'dorm',
  'bed',
  'counselor',
];

/// 解析 Excel 字节为人员列表。
/// 顶层函数：交由 [compute] 在后台 isolate 执行，避免大文件卡住界面。
List<Person> parsePersonsFromBytes(List<int> bytes) {
  final Excel excel = Excel.decodeBytes(ExcelService.sanitizeXlsx(bytes));
  final Sheet? sheet = excel.tables.isNotEmpty
      ? excel.tables.values.first
      : null;
  if (sheet == null) return <Person>[];

  final List<List<Data?>> rows = sheet.rows;
  if (rows.isEmpty) return <Person>[];

  // 在前 5 行中寻找表头
  Map<String, int> mapping = <String, int>{};
  int headerRow = -1;
  for (int r = 0; r < math.min(5, rows.length); r++) {
    final Map<String, int> found = ExcelService._matchHeader(rows[r]);
    if (found.length >= 2) {
      mapping = found;
      headerRow = r;
      break;
    }
  }

  // 未识别到表头：按默认列顺序
  final bool hasHeader = headerRow >= 0;
  if (!hasHeader) {
    mapping = <String, int>{};
    for (int i = 0; i < _fallbackOrder.length; i++) {
      mapping[_fallbackOrder[i]] = i;
    }
    headerRow = -1;
  }

  final List<Person> persons = <Person>[];
  int counter = 0;
  for (int r = hasHeader ? headerRow + 1 : 0; r < rows.length; r++) {
    final List<Data?> row = rows[r];
    String get(String field) {
      final int? idx = mapping[field];
      if (idx == null || idx >= row.length) return '';
      return ExcelService._cellText(row[idx]).trim();
    }

    final String name = get('name');
    final String dorm = get('dorm');
    final String studentId = get('studentId');
    // 整行为空则跳过
    if (name.isEmpty && dorm.isEmpty && studentId.isEmpty) continue;

    counter++;
    persons.add(
      Person(
        id: 'p_${DateTime.now().microsecondsSinceEpoch}_$counter',
        name: name,
        studentId: studentId,
        className: get('className'),
        dorm: dorm,
        bed: get('bed'),
        counselor: get('counselor'),
      ),
    );
  }
  return persons;
}

class ExcelService {
  /// 弹出文件选择器并导入人员。返回导入的人员列表；用户取消返回 null。
  Future<List<Person>?> pickAndImportPersons() async {
    final List<PlatformFile> result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['xlsx'],
    );
    if (result.isEmpty) return null;
    final Uint8List bytes = await result.single.readAsBytes();
    // 解析放到后台 isolate，避免大文件解析时卡住界面
    return compute(parsePersonsFromBytes, bytes);
  }

  /// 对 xlsx 字节做兼容性清洗，解决 excel 4.0.6 解析 openpyxl / WPS
  /// 生成文件时的两个问题：
  /// 1. 工作表关系使用绝对路径 `Target="/xl/worksheets/sheet1.xml"`，
  ///    解析器按 `xl/<target>` 拼接会找不到文件（null check 崩溃）；
  /// 2. styles.xml 的 `numFmts` 中出现内建 numFmtId（小于 164，如 0=General），
  ///    解析器认为自定义格式必须 >=164 而抛异常。
  /// 清洗失败时原样返回，交由上层报错。
  static List<int> sanitizeXlsx(List<int> bytes) {
    try {
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final Archive rebuilt = Archive();
      bool changed = false;

      for (final ArchiveFile entry in archive) {
        if (!entry.isFile) {
          rebuilt.addFile(entry);
          continue;
        }
        final String name = entry.name.replaceAll(r'\', '/');
        final List<int> raw = entry.content as List<int>;
        List<int>? patched;

        if (name.endsWith('.rels')) {
          final String text = utf8.decode(raw);
          // Target="/xl/xxx" -> Target="xxx"
          final String fixed = text.replaceAll('Target="/xl/', 'Target="');
          if (fixed != text) {
            changed = true;
            patched = utf8.encode(fixed);
          }
        } else if (name == 'xl/styles.xml' || name.endsWith('/styles.xml')) {
          final String? fixed = _stripBuiltinNumFmts(utf8.decode(raw));
          if (fixed != null) {
            changed = true;
            patched = utf8.encode(fixed);
          }
        } else if (name.contains('/worksheets/') && name.endsWith('.xml')) {
          final String? fixed = _fixEmptyInlineStrings(utf8.decode(raw));
          if (fixed != null) {
            changed = true;
            patched = utf8.encode(fixed);
          }
        }

        rebuilt.addFile(
          patched != null ? ArchiveFile(name, patched.length, patched) : entry,
        );
      }

      return changed ? ZipEncoder().encode(rebuilt)! : bytes;
    } catch (_) {
      return bytes;
    }
  }

  /// 移除 `numFmts` 中 numFmtId 小于 164 的内建格式节点；
  /// 全部被移除时删除整个 numFmts 块。无需改动返回 null。
  static String? _stripBuiltinNumFmts(String xml) {
    final RegExp blockReg = RegExp(
      r'<numFmts\b[^>]*>.*?</numFmts>',
      dotAll: true,
    );
    final RegExp numFmtReg = RegExp(r'<numFmt\b[^>]*/>');
    final RegExp idReg = RegExp(r'numFmtId="(\d+)"');
    bool changed = false;

    final String result = xml.replaceAllMapped(blockReg, (Match m) {
      final String block = m.group(0)!;
      final List<String> kept = <String>[];
      for (final RegExpMatch fm in numFmtReg.allMatches(block)) {
        final String node = fm.group(0)!;
        final RegExpMatch? idMatch = idReg.firstMatch(node);
        final int id = idMatch != null
            ? int.tryParse(idMatch.group(1)!) ?? 0
            : 0;
        if (id >= 164) {
          kept.add(node);
        } else {
          changed = true;
        }
      }
      if (kept.isEmpty) return '';
      return '<numFmts count="${kept.length}">${kept.join()}</numFmts>';
    });
    return changed ? result : null;
  }

  /// 修复空的 inlineStr 单元格。openpyxl 会把空字符串单元格写成
  /// `<c r="D2" t="inlineStr"></c>`（没有 is/t 子节点），excel 4.0.6
  /// 直接取 `t` 节点的 first 会抛 Bad state: No element。
  /// 去掉这些空单元格的 inlineStr 类型，按普通空单元格解析。
  /// 无需改动返回 null。
  static String? _fixEmptyInlineStrings(String xml) {
    final RegExp emptyCellReg = RegExp(
      r'<c\b([^>]*?)\st="inlineStr"([^>]*?)(/>|>\s*</c>)',
    );
    bool changed = false;
    final String result = xml.replaceAllMapped(emptyCellReg, (Match m) {
      changed = true;
      return '<c${m.group(1)}${m.group(2)}${m.group(3)}';
    });
    return changed ? result : null;
  }

  /// 在一行中匹配各字段所在的列索引，命中 2 个及以上视为表头。
  /// 两轮匹配：第一轮要求表头文字与关键词完全相等，避免「学号」被
  /// 「学籍号」等包含关系抢走列位；第二轮再用 contains 兜底。
  static Map<String, int> _matchHeader(List<Data?> row) {
    final List<String> texts = <String>[
      for (final Data? c in row) _cellText(c).trim().toLowerCase(),
    ];
    final Map<String, int> mapping = <String, int>{};
    // 第一轮：精确相等优先
    for (int c = 0; c < texts.length; c++) {
      final String text = texts[c];
      if (text.isEmpty) continue;
      _headerKeywords.forEach((String field, List<String> keywords) {
        if (mapping.containsKey(field)) return;
        if (keywords.any((String kw) => kw.toLowerCase() == text)) {
          mapping[field] = c;
        }
      });
    }
    // 第二轮：包含匹配兜底
    for (int c = 0; c < texts.length; c++) {
      final String text = texts[c];
      if (text.isEmpty) continue;
      _headerKeywords.forEach((String field, List<String> keywords) {
        if (mapping.containsKey(field)) return;
        if (keywords.any((String kw) => text.contains(kw.toLowerCase()))) {
          mapping[field] = c;
        }
      });
    }
    return mapping;
  }

  static String _cellText(Data? cell) {
    final CellValue? v = cell?.value;
    if (v == null) return '';
    if (v is TextCellValue) return v.value.text ?? '';
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      // 学号等整数列避免出现 .0
      final double d = v.value;
      if (d == d.roundToDouble()) return d.toInt().toString();
      return d.toString();
    }
    if (v is BoolCellValue) return v.value ? '是' : '否';
    if (v is DateCellValue) return '${v.year}-${v.month}-${v.day}';
    return v.toString();
  }

  /// 按纯文本模板生成查寝批次内容（可直接粘贴到聊天窗口）：
  ///   标题
  ///   宿舍范围（检查人员：xxx）
  ///
  ///   有异常人员时，每条：
  ///   宿舍 姓名学号
  ///   床号：…
  ///   班级：…
  ///   原因：…
  ///   辅导员：…
  ///
  ///   一个异常人员都没有时，追加一行：所有人宿舍均正常
  String buildSessionText(InspectionSession session) {
    final StringBuffer sb = StringBuffer();
    sb.writeln(session.displayTitle);
    sb.writeln('${session.dormRange}（检查人员：${session.inspector}）');
    if (session.records.isEmpty) {
      sb.writeln();
      sb.writeln('所有人宿舍均正常');
      return sb.toString();
    }
    for (final InspectionRecord r in session.records) {
      sb.writeln();
      sb.writeln('${r.dorm} ${r.name}${r.studentId}');
      sb.writeln('床号：${r.bed}');
      sb.writeln('班级：${r.className}');
      sb.writeln('原因：${r.reason}');
      sb.writeln('辅导员：${r.counselor}');
    }
    return sb.toString();
  }

  /// 晚归批次导出为 .docx。
  /// 晚归没有学院下发的 Word 模板，这里按文本模板内容从零生成一个简洁的
  /// Word 文档：标题居中加粗，记录逐条排列，正文宋体/Times New Roman 小四。
  Future<ExportedFile> exportSessionWord(InspectionSession session) async {
    String esc(String t) => t
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    String para(
      String text, {
      bool bold = false,
      bool center = false,
      int sz = 24,
    }) {
      final String jc = center ? '<w:jc w:val="center"/>' : '';
      final String b = bold ? '<w:b/><w:bCs/>' : '';
      return '<w:p><w:pPr>$jc</w:pPr>'
          '<w:r><w:rPr>'
          '<w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" w:hint="eastAsia"/>'
          '$b<w:sz w:val="$sz"/><w:szCs w:val="$sz"/>'
          '</w:rPr><w:t xml:space="preserve">${esc(text)}</w:t></w:r></w:p>';
    }

    final StringBuffer body = StringBuffer()
      ..write(para(session.displayTitle, bold: true, center: true, sz: 32))
      ..write(para('${session.dormRange}（检查人员：${session.inspector}）'));
    if (session.records.isEmpty) {
      body
        ..write(para(''))
        ..write(para('所有人宿舍均正常'));
    } else {
      for (final InspectionRecord r in session.records) {
        body
          ..write(para(''))
          ..write(para('${r.dorm} ${r.name}${r.studentId}', bold: true))
          ..write(para('床号：${r.bed}'))
          ..write(para('班级：${r.className}'))
          ..write(para('原因：${r.reason}'))
          ..write(para('辅导员：${r.counselor}'));
      }
    }

    const String contentTypes =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '</Types>';
    const String rels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';
    const String docRels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>';
    const String styles =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" w:hint="eastAsia"/>'
        '<w:sz w:val="24"/><w:szCs w:val="24"/>'
        '</w:rPr></w:rPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="a">'
        '<w:name w:val="Normal"/></w:style>'
        '</w:styles>';
    final String document =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1800" w:bottom="1440" w:left="1800" '
        'w:header="851" w:footer="992" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';

    final Archive archive = Archive();
    void add(String name, String content) {
      final List<int> b = utf8.encode(content);
      archive.addFile(ArchiveFile(name, b.length, b));
    }

    add('[Content_Types].xml', contentTypes);
    add('_rels/.rels', rels);
    add('word/_rels/document.xml.rels', docRels);
    add('word/styles.xml', styles);
    add('word/document.xml', document);
    final List<int> bytes = ZipEncoder().encode(archive)!;

    final String fileName =
        '${session.displayTitle}_${DateTime.now().millisecondsSinceEpoch}.docx';
    return ExportedFile(fileName, bytes);
  }

  // ========== 卫生检查评分表 ==========

  static const List<String> _kWeekdayCn = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  /// 评分表副标题：检查人员 / 时间 / 周次 / 楼栋
  String buildHygieneSubtitle(HygieneSession s) {
    final String weekday = s.weekday >= 1 && s.weekday <= 7
        ? _kWeekdayCn[s.weekday - 1]
        : '一';
    return '检查人员：${s.inspector}　'
        '检查时间：20${s.date.year % 100}年${s.date.month}月${s.date.day}日'
        '第${s.week}周星期$weekday　'
        '检查楼栋：${s.building}';
  }

  /// 卫生评分表的纯文本（可粘贴）：标题 + 表头 + 每个寝室一行
  String buildHygieneText(HygieneSession s) {
    final StringBuffer sb = StringBuffer();
    sb.writeln('光电与机电工程学院学生公寓内务卫生检查评分表');
    sb.writeln(buildHygieneSubtitle(s));
    sb.writeln(
      '序号\t寝室\t等级\t得分\t'
      '${kHygieneItems.map((HygieneItem e) => e.label).join('\t')}'
      '\t奖励分\t备注',
    );
    final List<HygieneRow> rows = _effectiveHygieneRows(s);
    for (int i = 0; i < rows.length; i++) {
      final HygieneRow r = rows[i];
      // 无人宿舍：等级/得分/分项/奖励分全部留空，仅保留寝室号与备注
      if (r.isUnoccupied) {
        sb.writeln(
          '${i + 1}\t${r.dorm}\t\t\t'
          '${List<String>.filled(kHygieneItems.length, '').join('\t')}'
          '\t\t${HygieneGrade.unoccupied}',
        );
        continue;
      }
      sb.writeln(
        '${i + 1}\t${r.dorm}\t${r.effectiveGrade}\t${fmtScore(r.total)}\t'
        '${kHygieneItems.map((HygieneItem e) => fmtScore(r.scores[e.key] ?? 0)).join('\t')}'
        '\t${r.bonus == 0 ? '' : fmtScore(r.bonus)}\t${r.remark}',
      );
    }
    return sb.toString();
  }

  /// 有效行（寝室号非空），若不足 20 行则补空行，与模板一致
  List<HygieneRow> _effectiveHygieneRows(HygieneSession s) {
    final List<HygieneRow> rows = s.rows
        .where((HygieneRow r) => r.dorm.trim().isNotEmpty)
        .toList();
    while (rows.length < 20) {
      rows.add(HygieneRow(id: 'blank_${rows.length}'));
    }
    return rows;
  }

  /// 按学院下发的 Word 模板导出卫生评分表为 .docx
  /// 做法：解压模板 -> 只替换 word/document.xml 中的副标题文字与表格单元格文字，
  /// 其余所有文件、样式、页面设置一字不动 -> 重新打包，保证格式与模板完全一致。
  Future<ExportedFile> exportHygieneWord(HygieneSession s) async {
    final ByteData tpl = await rootBundle.load('assets/hygiene_template.docx');
    final Archive archive = ZipDecoder().decodeBytes(
      tpl.buffer.asUint8List(tpl.offsetInBytes, tpl.lengthInBytes),
    );
    final Archive rebuilt = Archive();
    for (final ArchiveFile entry in archive) {
      if (!entry.isFile) {
        rebuilt.addFile(entry);
        continue;
      }
      final String name = entry.name.replaceAll(r'\', '/');
      List<int> patched;
      if (name == 'word/document.xml') {
        final String xml = utf8.decode(entry.content as List<int>);
        patched = utf8.encode(_fillHygieneDocumentXml(xml, s));
      } else {
        patched = entry.content as List<int>;
      }
      rebuilt.addFile(ArchiveFile(name, patched.length, patched));
    }
    final List<int> bytes = ZipEncoder().encode(rebuilt)!;

    final String fileName =
        '${s.displayTitle}_${DateTime.now().millisecondsSinceEpoch}.docx';
    return ExportedFile(fileName, bytes);
  }

  /// 向 document.xml 填入副标题与表格数据，保留模板全部格式
  String _fillHygieneDocumentXml(String xml, HygieneSession s) {
    String out = xml;
    final String weekday = s.weekday >= 1 && s.weekday <= 7
        ? _kWeekdayCn[s.weekday - 1]
        : '一';

    // ---- 1. 副标题：定位包含“检查人员：”的段落，仅替换其段落内容（保留 pPr）----
    final RegExp subPara = RegExp(
      r'(<w:p\b(?:(?!</w:p>).)*?检查人员：.*?</w:p>)',
      dotAll: true,
    );
    final Match? m = subPara.firstMatch(out);
    if (m != null) {
      final String para = m.group(1)!;
      final String ppr =
          RegExp(
            r'<w:pPr>.*?</w:pPr>',
            dotAll: true,
          ).firstMatch(para)?.group(0) ??
          '';

      // run 构造：与填写示例逐 run 对齐
      // font: 's' 宋体；'v' 填空值（Times New Roman/宋体/en-US）；'t' TNR 填空（楼栋空格/tab）
      String run(
        String text, {
        bool tab = false,
        bool underline = false,
        String font = 's',
        bool en = false,
        bool tighten = false,
      }) {
        final String fonts = switch (font) {
          'v' =>
            '<w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" '
                'w:hint="eastAsia"/>',
          't' =>
            '<w:rFonts w:ascii="Times New Roman" '
                'w:eastAsia="Times New Roman"/>',
          _ => '<w:rFonts w:ascii="宋体" w:eastAsia="宋体" w:hint="eastAsia"/>',
        };
        final String u = underline ? '<w:u w:val="single"/>' : '';
        final String lang = en ? '<w:lang w:val="en-US"/>' : '';
        final String sp = tighten ? '<w:spacing w:val="-1"/>' : '';
        final String body =
            '${tab ? '<w:tab/>' : ''}'
            '${text.isEmpty ? '' : '<w:t xml:space="preserve">${_xmlEscape(text)}</w:t>'}';
        return '<w:r><w:rPr>$fonts$sp<w:sz w:val="24"/>$u$lang</w:rPr>'
            '$body</w:r>';
      }

      // 严格按模板/填写示例的 run 顺序拼接（下划线填空形式）
      final StringBuffer content = StringBuffer();
      content.write(run('检查人员：'));
      content.write(run(' ', underline: true));
      content.write(run(s.inspector, underline: true, en: true));
      content.write(run('检查时间：20', tab: true));
      content.write(run(' ', underline: true));
      content.write(run('${s.date.year % 100}', underline: true, en: true));
      content.write(run('年'));
      content.write(run(' ', underline: true));
      content.write(run('${s.date.month}', underline: true, en: true));
      content.write(run('月'));
      content.write(run(' ', underline: true));
      content.write(run('${s.date.day}', underline: true, en: true));
      content.write(run('', tab: true, underline: true));
      content.write(run('日'));
      content.write(run('第', tab: true));
      content.write(run(' ', underline: true));
      content.write(run('${s.week}', underline: true, en: true));
      content.write(run('周星期'));
      content.write(run(' ', underline: true));
      content.write(run(weekday, underline: true, en: true));
      content.write(run('', tab: true, underline: true));
      content.write(run('', tab: true));
      content.write(run('检', tighten: true));
      content.write(run('查楼栋：'));
      content.write(run(' ', underline: true, font: 't'));
      content.write(run(s.building, underline: true, font: 'v', en: true));
      content.write(run('', tab: true, underline: true, font: 't'));

      final String open = RegExp(r'<w:p\b[^>]*>').firstMatch(para)!.group(0)!;
      out = out.replaceFirst(para, '$open$ppr$content</w:p>');
    }

    // ---- 2. 表格：表头行之后的 20 个数据行，逐单元格填值 ----
    // 真实数据行；不足 20 行的部分保持模板空白（不补 0）。
    final List<HygieneRow> dataRows = s.rows
        .where((HygieneRow r) => r.dorm.trim().isNotEmpty)
        .toList();
    final RegExp rowReg = RegExp(r'<w:tr\b.*?</w:tr>', dotAll: true);
    final List<Match> rowMatches = rowReg.allMatches(out).toList();
    // rowMatches[0] 为表头，其后为模板预留的 20 个数据行
    final StringBuffer sb = StringBuffer();
    int lastEnd = 0;
    for (int i = 0; i < rowMatches.length; i++) {
      final Match rm = rowMatches[i];
      sb.write(out.substring(lastEnd, rm.start));
      if (i >= 1 && i <= dataRows.length) {
        final HygieneRow r = dataRows[i - 1];
        // 13 列填写值（第 0 列序号模板已预填 1..20，原样保留）：
        // 寝室 / 等级 / 总分 / 8 个分项 / 奖励分 / 备注
        // 无人宿舍：等级/总分/分项/奖励分全部留空，仅寝室号 + 备注
        final bool unoccupied = r.isUnoccupied;
        final List<String> values = <String>[
          r.dorm,
          unoccupied ? '' : r.exportGrade,
          unoccupied ? '' : fmtScore(r.total),
          for (final HygieneItem item in kHygieneItems)
            unoccupied ? '' : fmtScore(r.scores[item.key] ?? 0),
          unoccupied || r.bonus == 0 ? '' : fmtScore(r.bonus),
          unoccupied ? HygieneGrade.unoccupied : r.remark,
        ];
        sb.write(_fillHygieneRowXml(rm.group(0)!, values));
      } else {
        sb.write(rm.group(0));
      }
      lastEnd = rm.end;
    }
    sb.write(out.substring(lastEnd));
    return sb.toString();
  }

  /// 替换一行表格中后 13 个单元格（第 0 列序号不动）的段落文字。
  /// 保留单元格 w:tcPr 与段落 w:pPr（模板原格式）。
  String _fillHygieneRowXml(String rowXml, List<String> values) {
    final RegExp cellReg = RegExp(r'<w:tc>.*?</w:tc>', dotAll: true);
    final List<Match> cells = cellReg.allMatches(rowXml).toList();
    final StringBuffer sb = StringBuffer();
    int lastEnd = 0;
    for (int i = 0; i < cells.length; i++) {
      final Match cm = cells[i];
      sb.write(rowXml.substring(lastEnd, cm.start));
      // values[0] 对应第 1 列（寝室），第 0 列序号保持模板原样
      if (i >= 1 && i - 1 < values.length && values[i - 1].trim().isNotEmpty) {
        // 与填写示例一致：第 7 列“室内摆设”为首行缩进 499 + 两端对齐，其余居中；
        // 空值格（如未填奖励分/备注）整格保持模板原样
        final String jcVal = i == 7 ? 'both' : 'center';
        sb.write(
          _fillHygieneCellXml(
            cm.group(0)!,
            values[i - 1],
            jcVal,
            firstLine: i == 7 ? 499 : null,
          ),
        );
      } else {
        sb.write(cm.group(0));
      }
      lastEnd = cm.end;
    }
    sb.write(rowXml.substring(lastEnd));
    return sb.toString();
  }

  /// 填充单个单元格：保留 w:tcPr、段落开标签与 w:pPr，仅替换段落中的 run
  String _fillHygieneCellXml(
    String cellXml,
    String value,
    String jcVal, {
    int? firstLine,
  }) {
    final String tcpr =
        RegExp(
          r'<w:tcPr>.*?</w:tcPr>',
          dotAll: true,
        ).firstMatch(cellXml)?.group(0) ??
        '';
    final RegExp openReg = RegExp(r'<w:p\b[^>]*>');
    final String open = openReg.firstMatch(cellXml)?.group(0) ?? '<w:p>';
    String ppr =
        RegExp(
          r'<w:pPr>.*?</w:pPr>',
          dotAll: true,
        ).firstMatch(cellXml)?.group(0) ??
        '';
    if (ppr.isNotEmpty) {
      // 删除已有 jc/ind，按示例统一；顺序为 ind -> jc，插在 pPr 内 rPr 之前
      ppr = ppr.replaceAll(RegExp(r'<w:jc\b[^>]*/>'), '');
      ppr = ppr.replaceAll(RegExp(r'<w:ind\b[^>]*/>'), '');
      final String ind = firstLine == null
          ? ''
          : '<w:ind w:firstLine="$firstLine"/>';
      final String jc = '<w:jc w:val="$jcVal"/>';
      final String insert = '$ind$jc';
      final int rprAt = ppr.indexOf('<w:rPr>');
      ppr = rprAt >= 0
          ? '${ppr.substring(0, rprAt)}$insert${ppr.substring(rprAt)}'
          : ppr.replaceFirst('</w:pPr>', '$insert</w:pPr>');
    }
    final String text = value.trim();
    // 与填写示例一致：Times New Roman/hint eastAsia、小四(24)、en-US
    final String run = text.isEmpty
        ? ''
        : '<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hint="eastAsia"/>'
              '<w:sz w:val="24"/><w:lang w:val="en-US"/></w:rPr>'
              '<w:t xml:space="preserve">${_xmlEscape(text)}</w:t></w:r>';
    return '<w:tc>$tcpr$open$ppr$run</w:p></w:tc>';
  }

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// 按 Word 模板导出卫生评分表为 .xlsx
  Future<ExportedFile> exportHygiene(HygieneSession s) async {
    final Excel excel = Excel.createExcel();
    final Sheet sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];

    // 列：序号 / 寝室号 / 等级 / 得分 / 8 分项 / 奖励分 / 备注 = 14 列
    const int colCount = 14;
    final Border thin = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.black,
    );
    final CellStyle borderStyle = CellStyle(
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
      textWrapping: TextWrapping.WrapText,
    );
    final CellStyle titleStyle = CellStyle(
      bold: true,
      fontSize: 15,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final CellStyle subStyle = CellStyle(
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
    );
    final CellStyle headerStyle = borderStyle.copyWith(boldVal: true);

    void setCell(int col, int rowIdx, String value, CellStyle style) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx),
        TextCellValue(value),
        cellStyle: style,
      );
    }

    void setNum(int col, int rowIdx, num value, CellStyle style) {
      if (value == 0) return; // 0 / 空奖励分留空，贴合示例
      final CellValue cellValue =
          value is double && value != value.truncateToDouble()
          ? DoubleCellValue(value)
          : IntCellValue(value.toInt());
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx),
        cellValue,
        cellStyle: style,
      );
    }

    // 第 0 行：大标题，跨 14 列
    setCell(0, 0, '光电与机电工程学院学生公寓内务卫生检查评分表', titleStyle);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: colCount - 1, rowIndex: 0),
      customValue: TextCellValue('光电与机电工程学院学生公寓内务卫生检查评分表'),
    );
    // 第 1 行：副标题，跨 14 列
    setCell(0, 1, buildHygieneSubtitle(s), subStyle);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
      CellIndex.indexByColumnRow(columnIndex: colCount - 1, rowIndex: 1),
      customValue: TextCellValue(buildHygieneSubtitle(s)),
    );

    // 第 2 行：表头
    const List<String> headers = <String>[
      '序号',
      '所在寝室号',
      '评定等级',
      '得分',
      '地面15%',
      '门面10%',
      '床铺20%',
      '室内摆设15%',
      '墙壁及断桥窗5%',
      '阳台及窗户15%',
      '卫生间15%',
      '舍员态度5%',
      '奖励分',
      '备注',
    ];
    for (int c = 0; c < headers.length; c++) {
      setCell(c, 2, headers[c], headerStyle);
    }

    // 第 3 行起：数据
    final List<HygieneRow> rows = _effectiveHygieneRows(s);
    for (int i = 0; i < rows.length; i++) {
      final int r = 3 + i;
      final HygieneRow row = rows[i];
      setCell(0, r, '${i + 1}', borderStyle);
      if (row.dorm.trim().isEmpty) {
        // 空白行也要画边框
        for (int c = 1; c < colCount; c++) {
          setCell(c, r, '', borderStyle);
        }
        continue;
      }
      setCell(1, r, row.dorm, borderStyle);
      if (row.isUnoccupied) {
        // 无人宿舍：等级/得分/分项/奖励分留空，备注标注
        for (int c = 2; c <= 12; c++) {
          setCell(c, r, '', borderStyle);
        }
        setCell(13, r, HygieneGrade.unoccupied, borderStyle);
        continue;
      }
      setCell(2, r, row.exportGrade, borderStyle);
      setNum(3, r, row.total, borderStyle);
      for (int j = 0; j < kHygieneItems.length; j++) {
        setNum(4 + j, r, row.scores[kHygieneItems[j].key] ?? 0, borderStyle);
      }
      setNum(12, r, row.bonus, borderStyle);
      setCell(13, r, row.remark, borderStyle);
    }

    // 列宽
    sheet.setColumnWidth(0, 5);
    sheet.setColumnWidth(1, 11);
    sheet.setColumnWidth(2, 8);
    sheet.setColumnWidth(3, 6);
    for (int c = 4; c < 12; c++) {
      sheet.setColumnWidth(c, 7.5);
    }
    sheet.setColumnWidth(12, 7);
    sheet.setColumnWidth(13, 12);
    // 表头行加高
    sheet.setRowHeight(2, 34);

    final String fileName =
        '${s.displayTitle}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    return ExportedFile(fileName, excel.encode()!);
  }

  /// 将整库备份数据打包为 .json 文件（内容由 StorageService.exportBackup 生成）
  ExportedFile exportBackupFile(Map<String, dynamic> data) {
    final String fileName =
        '查寝助手备份_${DateTime.now().millisecondsSinceEpoch}.json';
    return ExportedFile(fileName, utf8.encode(jsonEncode(data)));
  }

  /// 选择并读取备份 .json 文件；用户取消或文件非法时返回 null。
  Future<Map<String, dynamic>?> pickBackupFile() async {
    final List<PlatformFile> result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (result.isEmpty) return null;
    try {
      final Uint8List bytes = await result.single.readAsBytes();
      final String text = utf8.decode(bytes);
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 生成空白人员导入模板
  Future<ExportedFile> exportPersonTemplate() async {
    final Excel excel = Excel.createExcel();
    final Sheet sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];

    const List<String> headers = <String>['姓名', '学号', '班级', '宿舍', '床号', '辅导员'];
    final CellStyle headerStyle = CellStyle(bold: true, fontSize: 11);
    for (int c = 0; c < headers.length; c++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(headers[c]),
        cellStyle: headerStyle,
      );
      sheet.setColumnWidth(c, 18);
    }
    // 一行示例
    const List<String> sample = <String>[
      '张三',
      '20260001',
      '机械设计制造及其自动化1班',
      '23#601',
      '1号床',
      '王五',
    ];
    for (int c = 0; c < sample.length; c++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1),
        TextCellValue(sample[c]),
      );
    }

    return ExportedFile('人员导入模板.xlsx', excel.encode()!);
  }
}
