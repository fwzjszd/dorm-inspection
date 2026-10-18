// 本地持久化服务：人员库、查寝批次、历史输入词库
// 使用 shared_preferences 以 JSON 字符串形式存储

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class StorageService extends ChangeNotifier {
  StorageService._(this._prefs);

  static const String _kPersons = 'persons_v1';
  static const String _kSessions = 'sessions_v1';
  static const String _kHygiene = 'hygiene_sessions_v1';
  static const String _kWords = 'words_v1';
  static const String _kDarkMode = 'settings_dark_mode_v1';
  static const String _kLiquidGlass = 'settings_liquid_glass_v1';
  static const String _kInspectors = 'settings_inspectors_v1';
  static const String _kDefaultInspector = 'settings_default_inspector_v1';

  final SharedPreferences _prefs;

  /// 默认深色模式（液态玻璃锁定深色；保留 bool? 兼容旧备份恢复）
  bool? _darkMode = true;

  bool? get darkMode => _darkMode;

  /// 液态玻璃：默认开启；锁定深色主题
  bool _liquidGlass = true;

  bool get liquidGlass => _liquidGlass;

  /// 设置页维护的查寝人员名单；[defaultInspector] 为新建批次时预填的人名
  List<String> _inspectors = <String>[];
  String _defaultInspector = '';

  List<String> get inspectors => List<String>.unmodifiable(_inspectors);
  String get defaultInspector => _defaultInspector;

  List<Person> _persons = <Person>[];
  List<InspectionSession> _sessions = <InspectionSession>[];
  List<HygieneSession> _hygiene = <HygieneSession>[];

  /// 各字段的历史输入词库：字段名 -> 去重后的输入集合
  Map<String, List<String>> _words = <String, List<String>>{};

  List<Person> get persons => List<Person>.unmodifiable(_persons);
  List<InspectionSession> get sessions =>
      List<InspectionSession>.unmodifiable(_sessions);
  List<HygieneSession> get hygieneSessions =>
      List<HygieneSession>.unmodifiable(_hygiene);

  /// 人员库中出现过的楼栋前缀（如 14#），用于卫生检查按楼栋筛选
  List<String> get buildings {
    final Set<String> out = <String>{};
    for (final Person p in _persons) {
      final int hash = p.dorm.indexOf('#');
      if (hash > 0) out.add(p.dorm.substring(0, hash + 1));
    }
    return out.toList();
  }

  /// 人员库中去重后的宿舍号；[buildingPrefix] 非空时只返回该楼栋
  List<String> dormsInBuilding(String buildingPrefix) {
    final Set<String> out = <String>{};
    for (final Person p in _persons) {
      if (p.dorm.isNotEmpty &&
          (buildingPrefix.isEmpty || p.dorm.startsWith(buildingPrefix))) {
        out.add(p.dorm);
      }
    }
    final List<String> list = out.toList()..sort();
    return list;
  }

  static Future<StorageService> create() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final StorageService svc = StorageService._(prefs);
    svc._load();
    return svc;
  }

  void _load() {
    // 强制默认：液态玻璃 + 深色模式，不再读旧值
    _darkMode = _prefs.getBool(_kDarkMode) ?? true;
    _liquidGlass = _prefs.getBool(_kLiquidGlass) ?? true;
    // 液态玻璃开启时强制深色
    if (_liquidGlass) _darkMode = true;
    _inspectors = _prefs.getStringList(_kInspectors) ?? <String>[];
    _defaultInspector = _prefs.getString(_kDefaultInspector) ?? '';
    _persons = _decodeList(_prefs.getString(_kPersons), Person.fromJson);
    _sessions = _decodeList(
      _prefs.getString(_kSessions),
      InspectionSession.fromJson,
    );
    _hygiene = _decodeList(
      _prefs.getString(_kHygiene),
      HygieneSession.fromJson,
    );
    _words = _decodeWords(_prefs.getString(_kWords));
  }

  /// 逐条解析，单条坏数据只跳过该条，不阻断应用启动
  List<T> _decodeList<T>(
    String? src,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (src == null || src.isEmpty) return <T>[];
    dynamic decoded;
    try {
      decoded = jsonDecode(src);
    } catch (_) {
      return <T>[];
    }
    return _parseList<T>(decoded, fromJson);
  }

  /// 从已解码的 JSON 值解析列表：非 List 返回空；逐条 try/catch 跳过坏数据
  List<T> _parseList<T>(
    dynamic src,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (src is! List) return <T>[];
    final List<T> out = <T>[];
    for (final dynamic e in src) {
      if (e is! Map) continue;
      try {
        out.add(fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        // 跳过损坏条目
      }
    }
    return out;
  }

  Map<String, List<String>> _decodeWords(String? src) {
    if (src == null || src.isEmpty) return <String, List<String>>{};
    dynamic raw;
    try {
      raw = jsonDecode(src);
    } catch (_) {
      return <String, List<String>>{};
    }
    if (raw is! Map) return <String, List<String>>{};
    final Map<String, List<String>> out = <String, List<String>>{};
    raw.forEach((dynamic key, dynamic value) {
      if (key is! String || value is! List) return;
      out[key] = value.whereType<String>().toList();
    });
    return out;
  }

  // ========== 设置 ==========

  /// 设置夜间模式：null=跟随系统，true=深色，false=浅色
  Future<void> setDarkMode(bool? value) async {
    _darkMode = value;
    if (value == null) {
      await _prefs.remove(_kDarkMode);
    } else {
      await _prefs.setBool(_kDarkMode, value);
    }
    notifyListeners();
  }

  /// 切换液态玻璃。开启时强制深色主题（与 BiliMax 行为一致）。
  Future<void> setLiquidGlass(bool value) async {
    _liquidGlass = value;
    await _prefs.setBool(_kLiquidGlass, value);
    if (value && _darkMode != true) {
      _darkMode = true;
      await _prefs.setBool(_kDarkMode, true);
    }
    notifyListeners();
  }

  // ========== 查寝人员名单 ==========

  /// 添加查寝人员；空值或重名不处理。名单从空变非空时自动设为默认。
  bool addInspector(String name) {
    final String v = name.trim();
    if (v.isEmpty || _inspectors.contains(v)) return false;
    _inspectors.add(v);
    if (_defaultInspector.isEmpty) _defaultInspector = v;
    _prefs.setStringList(_kInspectors, _inspectors);
    _prefs.setString(_kDefaultInspector, _defaultInspector);
    notifyListeners();
    return true;
  }

  void removeInspector(String name) {
    if (!_inspectors.remove(name)) return;
    if (_defaultInspector == name) {
      _defaultInspector = _inspectors.isEmpty ? '' : _inspectors.first;
    }
    _prefs.setStringList(_kInspectors, _inspectors);
    _prefs.setString(_kDefaultInspector, _defaultInspector);
    notifyListeners();
  }

  void setDefaultInspector(String name) {
    if (_defaultInspector == name) return;
    _defaultInspector = name;
    _prefs.setString(_kDefaultInspector, name);
    notifyListeners();
  }

  /// 批量导入人员。按学号（优先）或 姓名+宿舍 去重合并，返回新增条数。
  int addPersons(List<Person> incoming) {
    int added = 0;
    for (final Person p in incoming) {
      final bool exists = _persons.any((Person e) {
        if (p.studentId.isNotEmpty && e.studentId == p.studentId) return true;
        return p.name.isNotEmpty && e.name == p.name && e.dorm == p.dorm;
      });
      if (!exists) {
        _persons.add(p);
        added++;
      }
    }
    _persistPersons();
    notifyListeners();
    return added;
  }

  void addPerson(Person p) {
    _persons.add(p);
    _persistPersons();
    notifyListeners();
  }

  void updatePerson(Person p) {
    final int i = _persons.indexWhere((Person e) => e.id == p.id);
    if (i >= 0) {
      _persons[i] = p;
      _persistPersons();
      notifyListeners();
    }
  }

  void deletePerson(String id) {
    _persons.removeWhere((Person e) => e.id == id);
    _persistPersons();
    notifyListeners();
  }

  void clearPersons() {
    _persons.clear();
    _persistPersons();
    notifyListeners();
  }

  void _persistPersons() {
    _prefs.setString(
      _kPersons,
      jsonEncode(_persons.map((Person e) => e.toJson()).toList()),
    );
  }

  // ========== 查寝批次 ==========

  void upsertSession(InspectionSession session) {
    final int i = _sessions.indexWhere(
      (InspectionSession e) => e.id == session.id,
    );
    if (i >= 0) {
      _sessions[i] = session;
    } else {
      _sessions.insert(0, session);
    }
    _persistSessions();
    // 记录里出现的内容沉淀为历史词库
    for (final InspectionRecord r in session.records) {
      addWords('reason', <String>[r.reason]);
    }
    addWords('inspector', <String>[session.inspector]);
    addWords('dormRange', <String>[session.dormRange]);
    notifyListeners();
  }

  void deleteSession(String id) {
    _sessions.removeWhere((InspectionSession e) => e.id == id);
    _persistSessions();
    notifyListeners();
  }

  void _persistSessions() {
    _prefs.setString(
      _kSessions,
      jsonEncode(_sessions.map((InspectionSession e) => e.toJson()).toList()),
    );
  }

  // ========== 卫生检查批次 ==========

  void upsertHygiene(HygieneSession session) {
    final int i = _hygiene.indexWhere((HygieneSession e) => e.id == session.id);
    if (i >= 0) {
      _hygiene[i] = session;
    } else {
      _hygiene.insert(0, session);
    }
    _persistHygiene();
    addWords('inspector', <String>[session.inspector]);
    addWords('building', <String>[session.building]);
    notifyListeners();
  }

  void deleteHygiene(String id) {
    _hygiene.removeWhere((HygieneSession e) => e.id == id);
    _persistHygiene();
    notifyListeners();
  }

  void _persistHygiene() {
    _prefs.setString(
      _kHygiene,
      jsonEncode(_hygiene.map((HygieneSession e) => e.toJson()).toList()),
    );
  }

  // ========== 历史输入词库 ==========

  /// 合并一批输入到指定字段的历史词库（去空、去重）。
  void addWords(String field, Iterable<String> values) {
    final List<String> list = _words.putIfAbsent(field, () => <String>[]);
    bool changed = false;
    for (String v in values) {
      v = v.trim();
      if (v.isNotEmpty && !list.contains(v)) {
        list.add(v);
        changed = true;
      }
    }
    if (changed) {
      _prefs.setString(_kWords, jsonEncode(_words));
      notifyListeners();
    }
  }

  List<String> words(String field) =>
      List<String>.unmodifiable(_words[field] ?? const <String>[]);

  /// 某字段的全部候选：人员库取值 + 历史词库
  List<String> suggestionsFor(String field) {
    final Set<String> out = <String>{};
    for (final Person p in _persons) {
      switch (field) {
        case 'name':
          if (p.name.isNotEmpty) out.add(p.name);
          break;
        case 'studentId':
          if (p.studentId.isNotEmpty) out.add(p.studentId);
          break;
        case 'className':
          if (p.className.isNotEmpty) out.add(p.className);
          break;
        case 'dorm':
          if (p.dorm.isNotEmpty) out.add(p.dorm);
          break;
        case 'bed':
          if (p.bed.isNotEmpty) out.add(p.bed);
          break;
        case 'counselor':
          if (p.counselor.isNotEmpty) out.add(p.counselor);
          break;
      }
    }
    out.addAll(_words[field] ?? const <String>[]);
    // 设置页维护的查寝人员名单也作为候选
    if (field == 'inspector') out.addAll(_inspectors);
    return out.toList();
  }

  // ========== 数据备份与恢复 ==========

  /// 导出整库数据为可序列化 Map，交给 ExcelService 写成备份文件
  Map<String, dynamic> exportBackup() => <String, dynamic>{
    'version': 1,
    'persons': <Map<String, dynamic>>[
      for (final Person e in _persons) e.toJson(),
    ],
    'sessions': <Map<String, dynamic>>[
      for (final InspectionSession e in _sessions) e.toJson(),
    ],
    'hygiene': <Map<String, dynamic>>[
      for (final HygieneSession e in _hygiene) e.toJson(),
    ],
    'words': _words,
    'inspectors': _inspectors,
    'defaultInspector': _defaultInspector,
    'darkMode': _darkMode,
    'liquidGlass': _liquidGlass,
  };

  /// 用备份数据覆盖当前整库并落盘。
  /// 与 [_parseList] 一致地跳过损坏条目，避免一份坏备份导致应用无法启动。
  Future<void> restoreBackup(Map<String, dynamic> data) async {
    _persons = _parseList<Person>(data['persons'], Person.fromJson);
    _sessions = _parseList<InspectionSession>(
      data['sessions'],
      InspectionSession.fromJson,
    );
    _hygiene = _parseList<HygieneSession>(
      data['hygiene'],
      HygieneSession.fromJson,
    );

    final dynamic words = data['words'];
    _words = words is Map
        ? <String, List<String>>{
            for (final MapEntry<dynamic, dynamic> e in words.entries)
              if (e.key is String && e.value is List)
                e.key as String: (e.value as List).whereType<String>().toList(),
          }
        : <String, List<String>>{};

    _inspectors =
        (data['inspectors'] as List?)?.whereType<String>().toList() ??
        <String>[];
    _defaultInspector = data['defaultInspector'] as String? ?? '';
    if (_inspectors.isNotEmpty && !_inspectors.contains(_defaultInspector)) {
      _defaultInspector = _inspectors.first;
    }

    final bool liquid = data['liquidGlass'] as bool? ?? _liquidGlass;
    final bool? dark = data['darkMode'] as bool?;
    _liquidGlass = liquid;
    // 与 setLiquidGlass 保持一致：液态玻璃开启时锁定深色主题
    _darkMode = liquid ? true : dark;

    await _persistAll();
    notifyListeners();
  }

  /// 把内存中的全部数据写回 SharedPreferences（恢复备份后调用）
  Future<void> _persistAll() async {
    await _prefs.setString(
      _kPersons,
      jsonEncode(_persons.map((Person e) => e.toJson()).toList()),
    );
    await _prefs.setString(
      _kSessions,
      jsonEncode(_sessions.map((InspectionSession e) => e.toJson()).toList()),
    );
    await _prefs.setString(
      _kHygiene,
      jsonEncode(_hygiene.map((HygieneSession e) => e.toJson()).toList()),
    );
    await _prefs.setString(_kWords, jsonEncode(_words));
    await _prefs.setStringList(_kInspectors, _inspectors);
    await _prefs.setString(_kDefaultInspector, _defaultInspector);
    final bool? dark = _darkMode;
    if (dark == null) {
      await _prefs.remove(_kDarkMode);
    } else {
      await _prefs.setBool(_kDarkMode, dark);
    }
    await _prefs.setBool(_kLiquidGlass, _liquidGlass);
  }
}
