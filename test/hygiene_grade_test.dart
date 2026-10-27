import 'package:dorm_inspection/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('等级阈值（优秀≥85；75≤良好＜85；60≤合格＜75；不合格＜60）', () {
    test('边界值', () {
      expect(HygieneGrade.suggest(100), HygieneGrade.excellent);
      expect(HygieneGrade.suggest(85), HygieneGrade.excellent);
      expect(HygieneGrade.suggest(84.9), HygieneGrade.good);
      expect(HygieneGrade.suggest(75), HygieneGrade.good);
      expect(HygieneGrade.suggest(74.9), HygieneGrade.pass);
      expect(HygieneGrade.suggest(60), HygieneGrade.pass);
      expect(HygieneGrade.suggest(59.9), HygieneGrade.fail);
    });

    test('总分含奖励分后参与判定', () {
      final HygieneRow row = HygieneRow(id: 'r1', dorm: '14#101', bonus: 8)
        ..scores.addAll(<String, double>{
          'floor': 15,
          'door': 10,
          'bed': 20,
          'furniture': 15,
          'wall': 5,
          'balcony': 15,
          'toilet': 15,
          'attitude': 5,
        });
      expect(row.total, 108);
      expect(row.effectiveGrade, HygieneGrade.excellent);
    });
  });
}
