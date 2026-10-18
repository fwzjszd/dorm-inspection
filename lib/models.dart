// 查寝 App 数据模型
// 包含：人员信息、单条查寝异常记录、一次查寝批次、卫生检查评分表

/// 从 Excel 导入的人员信息
class Person {
  Person({
    required this.id,
    this.name = '',
    this.studentId = '',
    this.className = '',
    this.dorm = '',
    this.bed = '',
    this.counselor = '',
  });

  final String id;
  String name; // 姓名
  String studentId; // 学号
  String className; // 班级
  String dorm; // 宿舍号，如 23#604
  String bed; // 床号，如 2号床
  String counselor; // 辅导员

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] as String? ?? 'p_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? '',
      studentId: json['studentId'] as String? ?? '',
      className: json['className'] as String? ?? '',
      dorm: json['dorm'] as String? ?? '',
      bed: json['bed'] as String? ?? '',
      counselor: json['counselor'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'studentId': studentId,
    'className': className,
    'dorm': dorm,
    'bed': bed,
    'counselor': counselor,
  };
}

/// 一条查寝异常记录（对应模板中一个学生的 5 行信息）
class InspectionRecord {
  InspectionRecord({
    required this.id,
    this.dorm = '',
    this.name = '',
    this.studentId = '',
    this.bed = '',
    this.className = '',
    this.reason = '',
    this.counselor = '',
  });

  final String id;
  String dorm; // 宿舍，如 23#604
  String name; // 姓名
  String studentId; // 学号
  String bed; // 床号，如 2号床
  String className; // 班级
  String reason; // 未归原因，如 跑步
  String counselor; // 辅导员

  factory InspectionRecord.fromJson(Map<String, dynamic> json) {
    return InspectionRecord(
      id: json['id'] as String? ?? 'r_${DateTime.now().microsecondsSinceEpoch}',
      dorm: json['dorm'] as String? ?? '',
      name: json['name'] as String? ?? '',
      studentId: json['studentId'] as String? ?? '',
      bed: json['bed'] as String? ?? '',
      className: json['className'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      counselor: json['counselor'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'dorm': dorm,
    'name': name,
    'studentId': studentId,
    'bed': bed,
    'className': className,
    'reason': reason,
    'counselor': counselor,
  };
}

/// 一次查寝批次（对应模板开头的日期标题、宿舍范围、检查人员 + 若干条记录）
class InspectionSession {
  InspectionSession({
    required this.id,
    required this.date,
    this.title = '',
    this.dormRange = '',
    this.inspector = '',
    List<InspectionRecord>? records,
  }) : records = records ?? <InspectionRecord>[];

  final String id;
  DateTime date;
  String title; // 自定义标题，为空时按 “M月d日检查宿舍” 生成
  String dormRange; // 检查宿舍范围，如 23#524、601-607
  String inspector; // 检查人员
  List<InspectionRecord> records;

  /// 模板第一行标题
  String get displayTitle =>
      title.trim().isNotEmpty ? title.trim() : '${date.month}月${date.day}日检查宿舍';

  factory InspectionSession.fromJson(Map<String, dynamic> json) {
    return InspectionSession(
      id: json['id'] as String? ?? 's_${DateTime.now().microsecondsSinceEpoch}',
      date: DateTime.fromMillisecondsSinceEpoch(
        (json['date'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      title: json['title'] as String? ?? '',
      dormRange: json['dormRange'] as String? ?? '',
      inspector: json['inspector'] as String? ?? '',
      records: (json['records'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map(
            (Map e) => InspectionRecord.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'date': date.millisecondsSinceEpoch,
    'title': title,
    'dormRange': dormRange,
    'inspector': inspector,
    'records': records.map((InspectionRecord e) => e.toJson()).toList(),
  };
}

/// 卫生检查评分的一个分项（key 为分项标识，满分为该分项权重）
class HygieneItem {
  const HygieneItem(this.key, this.label, this.max);

  /// 持久化用英文标识
  final String key;

  /// 表头显示名（含权重），如 地面15%
  final String label;

  /// 满分（= 权重）
  final int max;
}

/// 卫生评分表的 8 个固定分项，顺序即表格列顺序
const List<HygieneItem> kHygieneItems = <HygieneItem>[
  HygieneItem('floor', '地面', 15),
  HygieneItem('door', '门面', 10),
  HygieneItem('bed', '床铺', 20),
  HygieneItem('furniture', '室内摆设', 15),
  HygieneItem('wall', '墙壁及断桥窗', 5),
  HygieneItem('balcony', '阳台及窗户', 15),
  HygieneItem('toilet', '卫生间', 15),
  HygieneItem('attitude', '舍员态度', 5),
];

/// 分值显示：整数不带小数点，小数保留原样（如 15、14.5）
String fmtScore(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : '$v';

/// 评定等级
class HygieneGrade {
  static const String excellent = '优秀';
  static const String good = '良好';
  static const String pass = '合格';
  static const String fail = '不合格';

  static const List<String> values = <String>[excellent, good, pass, fail];

  /// 按总分给出建议等级（阈值据填写示例：74/79/84/89 均为良好）
  static String suggest(double score) {
    if (score >= 90) return excellent;
    if (score >= 70) return good;
    if (score >= 60) return pass;
    return fail;
  }
}

/// 卫生评分表中的一行（一个寝室）
class HygieneRow {
  HygieneRow({
    required this.id,
    this.dorm = '',
    this.grade = '',
    this.bonus = 0,
    this.remark = '',
    Map<String, double>? scores,
  }) : scores =
           scores ??
           Map<String, double>.fromEntries(
             kHygieneItems.map(
               (HygieneItem e) => MapEntry<String, double>(e.key, 0.0),
             ),
           );

  final String id;
  String dorm; // 所在寝室号，如 14#101
  String grade; // 评定等级，空表示用得分自动判定
  double bonus; // 奖励分
  String remark; // 备注
  final Map<String, double> scores; // 分项得分（key -> 得分）

  /// 8 项合计（不含奖励分）
  double get subtotal => kHygieneItems.fold<double>(
    0,
    (double a, HygieneItem e) => a + (scores[e.key] ?? 0),
  );

  /// 总分（分项合计 + 奖励分）
  double get total => subtotal + bonus;

  /// 实际导出的等级：手填优先，否则按总分判定
  String get effectiveGrade =>
      grade.trim().isNotEmpty ? grade.trim() : HygieneGrade.suggest(total);

  factory HygieneRow.fromJson(Map<String, dynamic> json) {
    final Map<String, double> scores = <String, double>{};
    final dynamic rawScores = json['scores'];
    if (rawScores is Map) {
      rawScores.forEach((dynamic k, dynamic v) {
        // 保存的 JSON 对 5 / 5.5 分别给出 int / double，统一转 double，
        // 避免旧数据启动时 as double 崩溃。
        if (k is String && v is num) {
          scores[k] = v.toDouble();
        }
      });
    }
    return HygieneRow(
      id:
          json['id'] as String? ??
          'hr_${DateTime.now().microsecondsSinceEpoch}',
      dorm: json['dorm'] as String? ?? '',
      grade: json['grade'] as String? ?? '',
      bonus: (json['bonus'] as num?)?.toDouble() ?? 0,
      remark: json['remark'] as String? ?? '',
      scores: scores,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'dorm': dorm,
    'grade': grade,
    'bonus': bonus,
    'remark': remark,
    'scores': scores,
  };
}

/// 一次卫生检查评分表（对应整份 Word 模板）
class HygieneSession {
  HygieneSession({
    required this.id,
    required this.date,
    this.inspector = '',
    this.building = '',
    this.week = 1,
    this.weekday = 1,
    List<HygieneRow>? rows,
  }) : rows = rows ?? <HygieneRow>[];

  final String id;
  DateTime date;
  String inspector; // 检查人员
  String building; // 检查楼栋，如 14#
  int week; // 第几周
  int weekday; // 星期几（1..7）
  List<HygieneRow> rows;

  String get displayTitle => '${date.month}月${date.day}日卫生检查';

  factory HygieneSession.fromJson(Map<String, dynamic> json) {
    return HygieneSession(
      id: json['id'] as String? ?? 'h_${DateTime.now().microsecondsSinceEpoch}',
      date: DateTime.fromMillisecondsSinceEpoch(
        (json['date'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      inspector: json['inspector'] as String? ?? '',
      building: json['building'] as String? ?? '',
      week: (json['week'] as num?)?.toInt() ?? 1,
      weekday: (json['weekday'] as num?)?.toInt() ?? 1,
      rows: (json['rows'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((Map e) => HygieneRow.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'date': date.millisecondsSinceEpoch,
    'inspector': inspector,
    'building': building,
    'week': week,
    'weekday': weekday,
    'rows': rows.map((HygieneRow e) => e.toJson()).toList(),
  };
}
