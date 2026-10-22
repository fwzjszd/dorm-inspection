// 多文档合成：检查人员姓名不得粘连后续字段（如「黄子翔检查时间：20…」）

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dorm_inspection/services/merge_service.dart';

/// 构造一个内存中的卫生评分表 .xlsx 字节，[subtitle] 完全自定义，
/// 用于模拟手工删掉字段间空格 / Tab / 全角空格后的文档。
List<int> buildHygieneXlsxBytes(String subtitle) {
  final Excel excel = Excel.createExcel();
  final Sheet sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];

  void setCell(int col, int row, String value) {
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      TextCellValue(value),
    );
  }

  setCell(0, 0, '光电与机电工程学院学生公寓内务卫生检查评分表');
  setCell(0, 1, subtitle);
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
    setCell(c, 2, headers[c]);
  }
  setCell(0, 3, '1');
  setCell(1, 3, '12#301');
  setCell(2, 3, '优秀');
  setCell(3, 3, '95');

  return excel.encode()!;
}

void main() {
  final MergeService service = MergeService();

  test('卫生表：检查人员后紧跟检查时间（无任何分隔符）也能正确截断', () {
    final List<int> bytes = buildHygieneXlsxBytes(
      '检查人员：黄子翔检查时间：2026年10月20日第6周星期一检查楼栋：12#',
    );
    final ImportedDoc doc = service.parseBytes(bytes, 'h.xlsx');
    expect(doc.type, ImportDocType.hygiene);
    expect(doc.hygiene!.inspector, '黄子翔');
    expect(doc.hygiene!.building, '12#');
    expect(doc.hygiene!.date, DateTime(2026, 10, 20));
    expect(doc.hygiene!.week, 6);
  });

  test('卫生表：全角空格 / 半角空格分隔均正常', () {
    final List<int> bytes = buildHygieneXlsxBytes(
      '检查人员：陈伟照　检查时间：2026年10月20日第6周星期一　检查楼栋：23#',
    );
    final ImportedDoc doc = service.parseBytes(bytes, 'h.xlsx');
    expect(doc.hygiene!.inspector, '陈伟照');
    expect(doc.hygiene!.building, '23#');
  });

  test('多文档合成：检查人员按姓名去重，不夹带字段标签', () {
    final ImportedDoc a = service.parseBytes(
      buildHygieneXlsxBytes(
        '检查人员：黄子翔检查时间：2026年10月20日第6周星期一检查楼栋：12#',
      ),
      'a.xlsx',
    );
    final ImportedDoc b = service.parseBytes(
      buildHygieneXlsxBytes(
        '检查人员：黄子翔　检查时间：2026年10月21日第6周星期二　检查楼栋：23#',
      ),
      'b.xlsx',
    );
    final MergeResult result = service.merge(<ImportedDoc>[a, b]);
    expect(result.hygiene!.inspector, '黄子翔');
    expect(result.hygiene!.building, '12#、23#');
    expect(result.hygiene!.rows.length, 2);
  });
}
