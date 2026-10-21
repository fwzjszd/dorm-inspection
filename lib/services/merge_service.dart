// 多文档合成服务
// 1. 解析「本软件生成」的导出文档：晚归 .docx、卫生评分表 .docx / .xlsx
// 2. 将多份同类型文档简单拼接，各合成一条新的汇总记录（晚归 / 卫生）
//
// 解析依赖本软件导出时的固定排版（见 excel_service.dart），非本软件生成的
// 文件会抛出 FormatException，由上层提示用户无法识别。

import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import '../models.dart';
import 'excel_service.dart';

/// 导入文档的类型
enum ImportDocType { inspection, hygiene, person }

/// 一份成功解析的文档
class ImportedDoc {
  ImportedDoc({
    required this.fileName,
    required this.type,
    this.path = '',
    this.session,
    this.hygiene,
    this.persons,
  });

  final String fileName;

  /// 来源文件路径（可能为空，仅用于 UI 去重）
  final String path;
  final ImportDocType type;

  /// type == inspection 时的解析结果
  final InspectionSession? session;

  /// type == hygiene 时的解析结果
  final HygieneSession? hygiene;

  /// type == person 时的解析结果
  final List<Person>? persons;
}

/// 合成筛选条件：所有条件之间为「与」关系
class MergeFilter {
  const MergeFilter({
    this.dormKeyword = '',
    this.buildings = const <String>{},
    this.grades = HygieneGrade.summaryDefaults,
  });

  /// 宿舍号关键词（包含匹配，如 111 可命中 23#111）
  final String dormKeyword;

  /// 楼栋前缀集合（如 {23#, 24#}），为空表示不限楼栋
  final Set<String> buildings;

  /// 卫生等级集合（优秀/良好/合格/不合格/无人宿舍），为空表示不限等级
  final Set<String> grades;

  bool get isEmpty =>
      dormKeyword.trim().isEmpty && buildings.isEmpty && grades.isEmpty;
}

/// 筛选后各类型的命中条数
class MergePreview {
  const MergePreview({
    required this.records,
    required this.rows,
    required this.persons,
  });

  final int records;
  final int rows;
  final int persons;
}

/// 可选筛选项
class MergeOptions {
  const MergeOptions({required this.buildings, required this.grades});

  final List<String> buildings;
  final List<String> grades;
}

/// 解析或合成失败
class MergeException implements Exception {
  const MergeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MergeService {
  static const List<String> _kWeekdayCn = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  /// 解析单个文件字节。[fileName] 仅用于扩展名判断与结果展示。
  /// 非本软件生成的文件抛 [FormatException] / [MergeException]。
  ImportedDoc parseBytes(List<int> bytes, String fileName, {String path = ''}) {
    final String ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'docx':
        return _parseDocx(bytes, fileName, path);
      case 'xlsx':
        if (_looksLikePersonXlsx(bytes)) {
          final List<Person> persons = parsePersonsFromBytes(bytes);
          if (persons.isEmpty) {
            throw MergeException('人员名单没有有效数据：$fileName');
          }
          return ImportedDoc(
            fileName: fileName,
            path: path,
            type: ImportDocType.person,
            persons: persons,
          );
        }
        return ImportedDoc(
          fileName: fileName,
          path: path,
          type: ImportDocType.hygiene,
          hygiene: _parseHygieneXlsx(bytes),
        );
      default:
        throw MergeException('仅支持 .docx / .xlsx 文件：$fileName');
    }
  }

  // ============================ docx 通用解析 ============================

  /// 解压 docx，返回正文全部段落文本与表格（每个表格为行→单元格文本）
  ({List<String> paragraphs, List<List<List<String>>> tables}) _readDocx(
    List<int> bytes,
  ) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? docFile;
    for (final ArchiveFile f in archive) {
      final String name = f.name.replaceAll(r'\', '/');
      if (name == 'word/document.xml') {
        docFile = f;
        break;
      }
    }
    if (docFile == null) {
      throw const FormatException('不是有效的 Word 文档');
    }
    final String xml = utf8.decode(docFile.content as List<int>);

    final List<List<List<String>>> tables = <List<List<String>>>[];
    for (final RegExpMatch tm in RegExp(
      r'<w:tbl>.*?</w:tbl>',
      dotAll: true,
    ).allMatches(xml)) {
      final List<List<String>> rows = <List<String>>[];
      for (final RegExpMatch rm in RegExp(
        r'<w:tr\b.*?</w:tr>',
        dotAll: true,
      ).allMatches(tm.group(0)!)) {
        final List<String> cells = <String>[];
        for (final RegExpMatch cm in RegExp(
          r'<w:tc>.*?</w:tc>',
          dotAll: true,
        ).allMatches(rm.group(0)!)) {
          cells.add(_extractDocxParagraphs(cm.group(0)!).join('\n').trim());
        }
        rows.add(cells);
      }
      tables.add(rows);
    }

    // 段落：取整篇文档中不在表格内的段落较繁琐，直接按顺序提取全部段落，
    // 晚归文档没有表格；卫生文档表格内的段落会混进来，但晚归解析只依赖
    // 「检查人员：」「床号：」等固定行，卫生表格单元格不含这些标记。
    final List<String> paragraphs = _extractDocxParagraphs(xml);
    return (paragraphs: paragraphs, tables: tables);
  }

  /// 提取一段 Word XML 中所有 `w:p` 段落的可见文本（多个 `w:t` 拼接，
  /// `w:br` 与段落分行由调用方决定；这里每个段落合并成一行）。
  List<String> _extractDocxParagraphs(String xml) {
    final List<String> out = <String>[];
    for (final RegExpMatch pm in RegExp(
      r'<w:p\b[^>]*>(.*?)</w:p>',
      dotAll: true,
    ).allMatches(xml)) {
      final String inner = pm.group(1)!;
      // w:tab 转空格，w:br 转换行
      final String normalized = inner
          .replaceAll(RegExp(r'<w:tab\b[^>]*/>'), ' ')
          .replaceAll(RegExp(r'<w:br\b[^>]*/>'), '\n');
      final StringBuffer buf = StringBuffer();
      for (final RegExpMatch tm in RegExp(
        r'<w:t\b[^>]*>(.*?)</w:t>',
        dotAll: true,
      ).allMatches(normalized)) {
        buf.write(_xmlUnescape(tm.group(1)!));
      }
      out.add(buf.toString().trim());
    }
    return out;
  }

  String _xmlUnescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");

  ImportedDoc _parseDocx(List<int> bytes, String fileName, String path) {
    final ({List<String> paragraphs, List<List<List<String>>> tables}) doc;
    try {
      doc = _readDocx(bytes);
    } catch (e) {
      throw MergeException('无法解析（不是有效的 .docx）：$fileName');
    }

    final bool looksHygiene =
        doc.paragraphs.any((String p) => p.contains('内务卫生检查评分表')) ||
        doc.tables.any(
          (List<List<String>> t) =>
              t.isNotEmpty && t.first.any((String c) => c.contains('所在寝室号')),
        );

    if (looksHygiene) {
      return ImportedDoc(
        fileName: fileName,
        path: path,
        type: ImportDocType.hygiene,
        hygiene: _parseHygieneDocx(doc, fileName),
      );
    }
    return ImportedDoc(
      fileName: fileName,
      path: path,
      type: ImportDocType.inspection,
      session: _parseInspectionDocx(doc, fileName),
    );
  }

  // ============================ 晚归 .docx ============================

  InspectionSession _parseInspectionDocx(
    ({List<String> paragraphs, List<List<List<String>>> tables}) doc,
    String fileName,
  ) {
    final List<String> lines = doc.paragraphs
        .where((String p) => p.trim().isNotEmpty)
        .toList();
    if (lines.length < 2 || !lines.any((String l) => l.contains('检查人员'))) {
      throw MergeException('无法识别的晚归文档：$fileName');
    }

    String title = '';
    DateTime date = DateTime.now();
    String dormRange = '';
    String inspector = '';
    final List<InspectionRecord> records = <InspectionRecord>[];

    int idx = 0;
    // 第一行：标题（含日期）
    title = lines.first.trim();
    final RegExpMatch? dm = RegExp(r'(\d{1,2})月(\d{1,2})日').firstMatch(title);
    if (dm != null) {
      date = DateTime(
        DateTime.now().year,
        int.parse(dm.group(1)!),
        int.parse(dm.group(2)!),
      );
    }
    idx = 1;

    String field(String label, String line) {
      final int i = line.indexOf(label);
      if (i < 0) return '';
      return line.substring(i + label.length).trim();
    }

    // 第二行通常为「范围（检查人员：xxx）」
    final String sub = lines.length > 1 ? lines[1] : '';
    if (sub.contains('检查人员')) {
      final RegExpMatch? im = RegExp(r'检查人员[：:]\s*([^）)]*)').firstMatch(sub);
      inspector = im?.group(1)?.trim() ?? '';
      final int bi = sub.indexOf('（');
      final int pi = sub.indexOf('(');
      final int cut = <int>[bi, pi]
          .where((int v) => v >= 0)
          .fold<int>(-1, (int a, int b) => a < 0 ? b : math.min(a, b));
      dormRange = (cut >= 0 ? sub.substring(0, cut) : sub).trim();
      idx = 2;
    }

    while (idx < lines.length) {
      final String line = lines[idx].trim();
      // 记录头：「宿舍 姓名学号」——含空格、且不是「标签：值」行
      final bool isHeader =
          line.contains(' ') &&
          !line.startsWith('床号') &&
          !line.startsWith('班级') &&
          !line.startsWith('原因') &&
          !line.startsWith('辅导员') &&
          line != '所有人宿舍均正常';
      if (isHeader) {
        final List<String> headParts = line.split(RegExp(r'\s+'));
        final String dorm = headParts.isNotEmpty ? headParts.first : '';
        final String rest = headParts.length > 1
            ? headParts.sublist(1).join(' ')
            : '';
        // 尾部连续数字视为学号，其余为姓名
        final RegExpMatch? sid = RegExp(r'(\d[\dA-Za-z]*)$').firstMatch(rest);
        final String studentId = sid?.group(1) ?? '';
        final String name = studentId.isNotEmpty
            ? rest.substring(0, rest.length - studentId.length).trim()
            : rest.trim();

        String bed = '';
        String className = '';
        String reason = '';
        String counselor = '';
        int j = idx + 1;
        while (j < lines.length) {
          final String l2 = lines[j].trim();
          if (l2.contains(' ') &&
              !l2.startsWith('床号') &&
              !l2.startsWith('班级') &&
              !l2.startsWith('原因') &&
              !l2.startsWith('辅导员')) {
            break; // 下一条记录头
          }
          if (l2.startsWith('床号')) {
            bed = field('床号：', l2);
            if (bed.isEmpty) bed = field('床号:', l2);
          }
          if (l2.startsWith('班级')) {
            className = field('班级：', l2);
            if (className.isEmpty) className = field('班级:', l2);
          }
          if (l2.startsWith('原因')) {
            reason = field('原因：', l2);
            if (reason.isEmpty) reason = field('原因:', l2);
          }
          if (l2.startsWith('辅导员')) {
            counselor = field('辅导员：', l2);
            if (counselor.isEmpty) counselor = field('辅导员:', l2);
          }
          j++;
        }
        records.add(
          InspectionRecord(
            id: 'r_merge_${DateTime.now().microsecondsSinceEpoch}_${records.length}',
            dorm: dorm,
            name: name,
            studentId: studentId,
            bed: bed,
            className: className,
            reason: reason,
            counselor: counselor,
          ),
        );
        idx = j;
      } else {
        idx++;
      }
    }

    return InspectionSession(
      id: 's_merge_${DateTime.now().microsecondsSinceEpoch}',
      date: date,
      title: title.contains('检查宿舍') ? '' : title,
      dormRange: dormRange,
      inspector: inspector,
      records: records,
    );
  }

  // ============================ 卫生 .docx ============================

  HygieneSession _parseHygieneDocx(
    ({List<String> paragraphs, List<List<List<String>>> tables}) doc,
    String fileName,
  ) {
    if (doc.tables.isEmpty) {
      throw MergeException('无法识别的卫生评分表（缺少表格）：$fileName');
    }
    final List<List<String>> table = doc.tables.first;
    final String subtitle = doc.paragraphs.firstWhere(
      (String p) => p.contains('检查人员'),
      orElse: () => '',
    );
    return _buildHygiene(subtitle, _hygieneRowsFromTable(table), fileName);
  }

  /// 从卫生表格提取有效数据行（跳过表头与模板预留空行）。
  /// 列顺序：序号 / 寝室 / 等级 / 总分 / 8 分项 / 奖励分 / 备注
  List<HygieneRow> _hygieneRowsFromTable(List<List<String>> table) {
    final List<HygieneRow> rows = <HygieneRow>[];
    for (int r = 0; r < table.length; r++) {
      final List<String> cells = table[r];
      if (cells.isEmpty) continue;
      // 表头行
      if (cells.any((String c) => c.contains('所在寝室号') || c == '寝室')) {
        continue;
      }
      String at(int i) => i < cells.length ? cells[i].trim() : '';
      final String dorm = at(1);
      if (dorm.isEmpty) continue; // 模板预留空行
      rows.add(_buildHygieneRow(dorm, at(2), at(3), cells, 4, at(12), at(13)));
    }
    return rows;
  }

  // ============================ 人员 .xlsx ============================

  /// 探测 xlsx 是否为人员名单：前 5 行含「姓名」等人员表头，
  /// 且不是卫生评分表（无「所在寝室号」、无评分分项表头）。
  bool _looksLikePersonXlsx(List<int> bytes) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(ExcelService.sanitizeXlsx(bytes));
    } catch (e) {
      return false;
    }
    final Sheet? sheet = excel.tables.isNotEmpty
        ? excel.tables.values.first
        : null;
    if (sheet == null) return false;
    final List<List<Data?>> rawRows = sheet.rows;
    for (int r = 0; r < math.min(5, rawRows.length); r++) {
      final String joined = rawRows[r]
          .map((Data? c) => _xlsxCellText(<Data?>[c], 0))
          .join();
      if (joined.isEmpty) continue;
      if (joined.contains('所在寝室号') ||
          joined.contains('内务卫生') ||
          joined.contains('地面')) {
        return false;
      }
      if (joined.contains('姓名') ||
          joined.contains('学号') ||
          (joined.contains('宿舍') && joined.contains('班级')) ||
          (joined.contains('寝室') && joined.contains('辅导员'))) {
        return true;
      }
    }
    return false;
  }

  // ============================ 卫生 .xlsx ============================

  static String _xlsxCellText(List<Data?> row, int i) {
    if (i >= row.length) return '';
    final CellValue? v = row[i]?.value;
    if (v == null) return '';
    if (v is TextCellValue) return v.value.text ?? '';
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final double d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return v.toString();
  }

  HygieneSession _parseHygieneXlsx(List<int> bytes) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      throw MergeException('无法解析（不是有效的 .xlsx）');
    }
    final Sheet? sheet = excel.tables.isNotEmpty
        ? excel.tables.values.first
        : null;
    if (sheet == null) throw const MergeException('表格内容为空');
    final List<List<Data?>> rawRows = sheet.rows;

    String subtitle = '';
    int headerIdx = -1;
    for (int r = 0; r < math.min(5, rawRows.length); r++) {
      final String joined = rawRows[r]
          .map((Data? c) => _xlsxCellText(<Data?>[c], 0))
          .join();
      if (joined.contains('检查人员')) subtitle = joined;
      if (joined.contains('所在寝室号')) headerIdx = r;
    }
    if (headerIdx < 0) {
      throw const MergeException('无法识别的卫生评分表（缺少表头）');
    }

    final List<HygieneRow> rows = <HygieneRow>[];
    for (int r = headerIdx + 1; r < rawRows.length; r++) {
      final List<Data?> row = rawRows[r];
      final String dorm = _xlsxCellText(row, 1).trim();
      if (dorm.isEmpty) continue;
      final List<String> cells = <String>[
        for (int c = 0; c < 14; c++) _xlsxCellText(row, c).trim(),
      ];
      rows.add(
        _buildHygieneRow(
          dorm,
          cells[2],
          cells[3],
          cells,
          4,
          cells[12],
          cells[13],
        ),
      );
    }
    return _buildHygiene(subtitle, rows, '');
  }

  /// 通用：根据副标题 + 行数据构造卫生批次
  HygieneSession _buildHygiene(
    String subtitle,
    List<HygieneRow> rows,
    String fileName,
  ) {
    final int year = DateTime.now().year;
    int month = DateTime.now().month;
    int day = DateTime.now().day;
    int week = 1;
    int weekday = 1;
    String inspector = '';
    String building = '';

    String grab(String label) {
      final RegExpMatch? m = RegExp(RegExp.escape(label) + r'\s*([^\s，,（(]*)')
          .firstMatch(subtitle);
      return m?.group(1)?.trim() ?? '';
    }

    inspector = grab('检查人员：');
    if (inspector.isEmpty) inspector = grab('检查人员:');
    final RegExpMatch? dm = RegExp(r'(\d{2,4})年(\d{1,2})月(\d{1,2})日')
        .firstMatch(subtitle);
    if (dm != null) {
      int yy = int.parse(dm.group(1)!);
      if (yy < 100) yy += 2000;
      month = int.parse(dm.group(2)!);
      day = int.parse(dm.group(3)!);
    }
    final RegExpMatch? wm = RegExp(r'第\s*(\d+)\s*周').firstMatch(subtitle);
    if (wm != null) week = int.parse(wm.group(1)!);
    final RegExpMatch? wdm = RegExp(r'星期\s*([一二三四五六日])').firstMatch(subtitle);
    if (wdm != null) {
      final int i = _kWeekdayCn.indexOf(wdm.group(1)!);
      if (i >= 0) weekday = i + 1;
    }
    building = grab('检查楼栋：');
    if (building.isEmpty) building = grab('检查楼栋:');
    // 楼栋兜底：取首行寝室的楼栋前缀
    if (building.isEmpty && rows.isNotEmpty) {
      final int h = rows.first.dorm.indexOf('#');
      if (h > 0) building = rows.first.dorm.substring(0, h + 1);
    }

    if (rows.isEmpty && fileName.isNotEmpty) {
      throw MergeException('卫生评分表没有有效寝室行：$fileName');
    }

    return HygieneSession(
      id: 'h_merge_${DateTime.now().microsecondsSinceEpoch}',
      date: DateTime(year, month, day),
      inspector: inspector,
      building: building,
      week: week,
      weekday: weekday,
      rows: rows,
    );
  }

  /// 构造一行卫生评分。[scoreOffset] 为 8 个分项在 [cells] 中的起始列。
  /// 若导出的等级与按总分自动判定一致，则不保存手填等级，交给应用自动判定。
  HygieneRow _buildHygieneRow(
    String dorm,
    String gradeText,
    String totalText,
    List<String> cells,
    int scoreOffset,
    String bonusText,
    String remark,
  ) {
    double parseScore(String s) {
      return double.tryParse(s.trim()) ?? 0;
    }

    final Map<String, double> scores = <String, double>{};
    for (int i = 0; i < kHygieneItems.length; i++) {
      scores[kHygieneItems[i].key] = parseScore(
        scoreOffset + i < cells.length ? cells[scoreOffset + i] : '',
      );
    }
    final double bonus = parseScore(bonusText);
    final HygieneRow row = HygieneRow(
      id: 'hr_merge_${DateTime.now().microsecondsSinceEpoch}_${dorm}_$scoreOffset',
      dorm: dorm,
      bonus: bonus,
      remark: remark,
      scores: scores,
    );
    final String auto = HygieneGrade.suggest(row.subtotal + bonus);
    final String g = gradeText.trim();
    if (g.isNotEmpty && g != auto) {
      row.grade = g;
    }
    return row;
  }

  // ============================ 多文档合成 ============================

  /// 把「姓名A、姓名B，姓名C 姓名D」拆成去重后的姓名列表
  static List<String> _splitNames(String raw) {
    final List<String> out = <String>[];
    for (final String part in raw.split(RegExp(r'[、,，/\s]+'))) {
      final String p = part.trim();
      if (p.isNotEmpty && !out.contains(p)) out.add(p);
    }
    return out;
  }

  /// 取宿舍号的楼栋前缀（含 #），无 # 返回空串
  static String buildingPrefixOf(String dorm) {
    final int h = dorm.indexOf('#');
    return h > 0 ? dorm.substring(0, h + 1) : '';
  }

  bool _dormMatch(String dorm, MergeFilter f) {
    final String kw = f.dormKeyword.trim();
    if (kw.isNotEmpty && !dorm.contains(kw)) return false;
    if (f.buildings.isNotEmpty) {
      final String prefix = buildingPrefixOf(dorm);
      final bool hit = f.buildings.any(
        (String b) => b.isNotEmpty && (dorm.startsWith(b) || prefix == b),
      );
      if (!hit) return false;
    }
    return true;
  }

  /// 卫生行的筛选用分类：无人宿舍单独归类，其余按实际评定等级
  static String _rowCategory(HygieneRow r) =>
      r.isUnoccupied ? HygieneGrade.unoccupied : r.effectiveGrade;

  /// 卫生行是否命中等级筛选；[grades] 为空表示不限等级
  static bool _gradeHit(HygieneRow r, Set<String> grades) {
    if (grades.isEmpty) return true;
    return grades.contains(_rowCategory(r));
  }

  /// 当前文档在给定筛选条件下的可选筛选项（楼栋、等级）
  MergeOptions optionsOf(List<ImportedDoc> docs) {
    final Set<String> buildings = <String>{};
    bool hasHygiene = false;
    for (final ImportedDoc d in docs) {
      if (d.type == ImportDocType.hygiene) {
        hasHygiene = true;
        for (final HygieneRow r in d.hygiene!.rows) {
          final String p = buildingPrefixOf(r.dorm);
          if (p.isNotEmpty) buildings.add(p);
        }
        for (final String part in d.hygiene!.building.split(
          RegExp(r'[、,，/\s]+'),
        )) {
          final String b = part.trim();
          if (b.isNotEmpty) buildings.add(b.endsWith('#') ? b : '$b#');
        }
      } else if (d.type == ImportDocType.person) {
        for (final Person p in d.persons!) {
          final String prefix = buildingPrefixOf(p.dorm);
          if (prefix.isNotEmpty) buildings.add(prefix);
        }
      }
    }
    // 只要导入了卫生文档，就列出全部等级（四个评定等级 + 无人宿舍），
    // 即使当前文档中没有该等级的寝室也允许勾选，便于任意组合筛选。
    final List<String> gradeList = hasHygiene
        ? const <String>[...HygieneGrade.values, HygieneGrade.unoccupied]
        : const <String>[];
    final List<String> buildingList = buildings.toList()..sort();
    return MergeOptions(buildings: buildingList, grades: gradeList);
  }

  /// 预览筛选后各类型命中条数（人员名单不参与筛选）
  MergePreview previewOf(List<ImportedDoc> docs, MergeFilter f) {
    int records = 0;
    int rows = 0;
    int persons = 0;
    for (final ImportedDoc d in docs) {
      if (d.type == ImportDocType.inspection) {
        records += d.session!.records
            .where((InspectionRecord r) => _dormMatch(r.dorm, f))
            .length;
      } else if (d.type == ImportDocType.hygiene) {
        rows += d.hygiene!.rows.where((HygieneRow r) {
          if (!_dormMatch(r.dorm, f)) return false;
          return _gradeHit(r, f.grades);
        }).length;
      } else if (d.type == ImportDocType.person) {
        persons += d.persons!.length;
      }
    }
    return MergePreview(records: records, rows: rows, persons: persons);
  }

  /// 把多份已解析文档按类型分别拼接，合成新的晚归 / 卫生汇总记录，
  /// 并汇总人员名单。[filter] 非空时只保留命中的晚归记录与卫生寝室。
  MergeResult merge(
    List<ImportedDoc> docs, {
    MergeFilter filter = const MergeFilter(),
  }) {
    final List<ImportedDoc> ins = docs
        .where((ImportedDoc d) => d.type == ImportDocType.inspection)
        .toList();
    final List<ImportedDoc> hyg = docs
        .where((ImportedDoc d) => d.type == ImportDocType.hygiene)
        .toList();
    final List<ImportedDoc> people = docs
        .where((ImportedDoc d) => d.type == ImportDocType.person)
        .toList();

    InspectionSession? mergedSession;
    HygieneSession? mergedHygiene;

    if (ins.isNotEmpty) {
      final List<InspectionSession> ss = ins
          .map((ImportedDoc d) => d.session!)
          .toList();
      final DateTime newest = ss
          .map((InspectionSession s) => s.date)
          .reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);
      final List<String> ranges = ss
          .map((InspectionSession s) => s.dormRange.trim())
          .where((String s) => s.isNotEmpty)
          .toSet()
          .toList();
      // 检查人员：跨文档拆分去重后顿号连接
      final List<String> inspectorNames = <String>[];
      for (final InspectionSession s in ss) {
        for (final String name in _splitNames(s.inspector)) {
          if (!inspectorNames.contains(name)) inspectorNames.add(name);
        }
      }
      final List<InspectionRecord> records = <InspectionRecord>[];
      for (final InspectionSession s in ss) {
        for (final InspectionRecord r in s.records) {
          if (!_dormMatch(r.dorm, filter)) continue;
          records.add(
            InspectionRecord(
              id: 'r_merged_${DateTime.now().microsecondsSinceEpoch}_${records.length}',
              dorm: r.dorm,
              name: r.name,
              studentId: r.studentId,
              bed: r.bed,
              className: r.className,
              reason: r.reason,
              counselor: r.counselor,
            ),
          );
        }
      }
      mergedSession = InspectionSession(
        id: 's_merged_${DateTime.now().microsecondsSinceEpoch}',
        date: newest,
        dormRange: ranges.join('、'),
        inspector: inspectorNames.join('、'),
        records: records,
      );
    }

    if (hyg.isNotEmpty) {
      final List<HygieneSession> ss = hyg
          .map((ImportedDoc d) => d.hygiene!)
          .toList();
      final HygieneSession newestSession = ss.reduce(
        (HygieneSession a, HygieneSession b) => a.date.isAfter(b.date) ? a : b,
      );
      // 检查人员：跨文档拆分去重
      final List<String> inspectorNames = <String>[];
      for (final HygieneSession s in ss) {
        for (final String name in _splitNames(s.inspector)) {
          if (!inspectorNames.contains(name)) inspectorNames.add(name);
        }
      }
      // 楼栋：各文档楼栋字段拆分 + 卫生行/人员宿舍前缀，全部去重
      final Set<String> buildingSet = <String>{};
      for (final HygieneSession s in ss) {
        for (final String part in s.building.split(RegExp(r'[、,，/\s]+'))) {
          final String b = part.trim();
          if (b.isNotEmpty) {
            buildingSet.add(b.endsWith('#') ? b : '$b#');
          }
        }
      }
      final List<HygieneRow> rows = <HygieneRow>[];
      for (final HygieneSession s in ss) {
        for (final HygieneRow r in s.rows) {
          final String prefix = buildingPrefixOf(r.dorm);
          if (prefix.isNotEmpty) buildingSet.add(prefix);
          if (!_dormMatch(r.dorm, filter)) continue;
          if (!_gradeHit(r, filter.grades)) continue;
          rows.add(
            HygieneRow(
              id: 'hr_merged_${DateTime.now().microsecondsSinceEpoch}_${rows.length}',
              dorm: r.dorm,
              grade: r.grade,
              bonus: r.bonus,
              remark: r.remark,
              scores: Map<String, double>.from(r.scores),
            ),
          );
        }
      }
      // 人员名单中的楼栋也要归入上方「检查楼栋」
      for (final ImportedDoc d in people) {
        for (final Person p in d.persons!) {
          final String prefix = buildingPrefixOf(p.dorm);
          if (prefix.isNotEmpty) buildingSet.add(prefix);
        }
      }
      final List<String> buildingList = buildingSet.toList()..sort();
      mergedHygiene = HygieneSession(
        id: 'h_merged_${DateTime.now().microsecondsSinceEpoch}',
        date: newestSession.date,
        inspector: inspectorNames.join('、'),
        building: buildingList.join('、'),
        week: newestSession.week,
        weekday: newestSession.weekday,
        rows: rows,
      );
    }

    // 人员名单：跨文档汇总（去重逻辑与 addPersons 一致：学号优先，否则姓名+宿舍）
    final List<Person> persons = <Person>[];
    final Set<String> personKeys = <String>{};
    int personCounter = 0;
    for (final ImportedDoc d in people) {
      for (final Person p in d.persons!) {
        final String key = p.studentId.isNotEmpty
            ? 'sid:${p.studentId}'
            : 'nk:${p.name}:${p.dorm}';
        if (!personKeys.add(key)) continue;
        personCounter++;
        persons.add(
          Person(
            id: 'p_merged_${DateTime.now().microsecondsSinceEpoch}_$personCounter',
            name: p.name,
            studentId: p.studentId,
            className: p.className,
            dorm: p.dorm,
            bed: p.bed,
            counselor: p.counselor,
          ),
        );
      }
    }

    return MergeResult(
      session: mergedSession,
      hygiene: mergedHygiene,
      persons: persons,
    );
  }
}

/// 合成结果：两类各自至多一条，人员为汇总去重后的名单
class MergeResult {
  MergeResult({this.session, this.hygiene, this.persons = const <Person>[]});

  final InspectionSession? session;
  final HygieneSession? hygiene;
  final List<Person> persons;
}
