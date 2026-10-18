// 基础单元测试：模型 JSON 序列化往返

import 'package:flutter_test/flutter_test.dart';

import 'package:dorm_inspection/models.dart';

void main() {
  test('InspectionSession JSON 往返', () {
    final InspectionSession session = InspectionSession(
      id: 's1',
      date: DateTime(2026, 10, 11),
      dormRange: '23#524、601-607',
      inspector: '黄子翔',
      records: <InspectionRecord>[
        InspectionRecord(
          id: 'r1',
          dorm: '23#604',
          name: '范杰',
          studentId: '262012522',
          bed: '2号床',
          className: '机械设计制造及其自动化5班',
          reason: '跑步',
          counselor: '曾少奇',
        ),
      ],
    );

    final InspectionSession restored = InspectionSession.fromJson(
      session.toJson(),
    );
    expect(restored.displayTitle, '10月11日检查宿舍');
    expect(restored.dormRange, '23#524、601-607');
    expect(restored.inspector, '黄子翔');
    expect(restored.records.single.studentId, '262012522');
    expect(restored.records.single.reason, '跑步');
  });

  test('Person 自定义标题优先于自动日期标题', () {
    final InspectionSession s = InspectionSession(
      id: 's2',
      date: DateTime(2026, 1, 2),
      title: '  元旦查寝  ',
    );
    expect(s.displayTitle, '元旦查寝');
  });
}
