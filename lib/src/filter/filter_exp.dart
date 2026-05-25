import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:team_logger/team_logger.dart';

import '../utils/stream_notifier.dart';

part 'filter_value.dart';

final class FilterExp extends StreamNotifier {
  // static const orSign = '+';
  static const orSign = '∪';
  // static const orSign = '||';
  static const andSign = '∩';
  // static const andSign = '×';
  // static const andSign = '&&';
  // static const andSign = '→';

  final or = FilterOr._();
  final and = FilterAnd._();

  FilterExp() {
    or._parent = this;
    and._parent = this;
  }

  @override
  Future<void> dispose() async {
    or._parent = null;
    and._parent = null;

    return super.dispose();
  }

  bool get isEnabled => or.isEnabled || and.isEnabled;

  bool call(Log log) => or(log) && and(log);

  void clear() {
    or._clear();
    and._clear();
    notifyListeners();
  }

  bool undo() {
    if (and._values.isNotEmpty) {
      and._values.remove(and._values.last);
      notifyListeners();
      return true;
    }

    if (or._values.isNotEmpty) {
      or._values.remove(or._values.last);
      notifyListeners();
      return true;
    }

    return false;
  }

  void _update() {
    notifyListeners();
  }

  String toColorizedString(LogTheme theme) {
    final or = this.or.toColorizedStringList(theme);
    final and = this.and.toColorizedStringList(theme);
    final signStyle = theme.data.punctuation;
    final andSign = signStyle(FilterExp.andSign);
    final orSign = signStyle(FilterExp.orSign);
    final orStr = or.join(' $orSign ');
    final andStr = and.join(' $andSign ');

    return switch ((or, and)) {
      ([], []) => '',
      ([], [...]) => andStr,
      ([_], []) => orStr,
      ([...], []) => orStr,
      ([_], [...]) => '$orStr $andSign $andStr',
      ([...], [...]) =>
        '${signStyle('(')}$orStr${signStyle(')')} $andSign $andStr',
    };
  }

  @override
  String toString() {
    final or = this.or.toStringList();
    final and = this.and.toStringList();
    final orStr = or.join(' $orSign ');
    final andStr = and.join(' $andSign ');

    return switch ((or, and)) {
      ([], []) => '',
      ([], [...]) => andStr,
      ([_], []) => orStr,
      ([...], []) => orStr,
      ([_], [...]) => '$orStr $andSign $andStr',
      ([...], [...]) => '($orStr) $andSign $andStr',
    };
  }
}

sealed class _FilterOp {
  final Set<FilterValue> _values = {};
  FilterExp? _parent;

  _FilterOp();

  Set<FilterValue> get values => UnmodifiableSetView(_values);

  bool get isEnabled => _values.isNotEmpty;

  FilterExp get _requireParent =>
      _parent ?? (throw StateError('parent is not set'));

  void _clear() {
    _values.clear();
  }

  bool call(Log log);

  List<T> map<T extends Object>({
    required T Function(int level) level,
    required T Function(String logger) logger,
    required T Function(String? group) traceId,
    required T Function(String tag) tag,
  }) =>
      _values
          .map(
            (e) => switch (e) {
              FilterLevel(:final value) => level(value),
              FilterLogger(:final value) => logger(value),
              FilterTraceId(:final value) => traceId(value),
              FilterTag(:final value) => tag(value),
            },
          )
          .toList();

  List<String> toColorizedStringList(LogTheme theme) => map(
        level: (level) => theme.main[level].data.normal(LogLevels.name(level)),
        logger: (logger) => theme.data.pathStyle('[$logger]'),
        traceId: (group) =>
            theme.main.traceIdStyle(group == null ? '{<global>}' : '{$group}'),
        tag: (tag) => theme.main.tagsStyle('#$tag'),
      );

  List<String> toStringList() => map(
        level: (level) => 'level:${LogLevels.name(level)}',
        logger: (logger) => 'logger:$logger',
        traceId: (group) => 'trace:${group ?? '<global>'}',
        tag: (tag) => 'tag:$tag',
      );
}

final class FilterOr extends _FilterOp {
  FilterOr._();

  @override
  bool call(Log log) {
    if (_values.isEmpty) return true;

    for (final v in _values) {
      switch (v) {
        case FilterLevel(:final value):
          if (log.level == value) return true;
        case FilterLogger(:final value):
          if (log.path == value) return true;
        case FilterTraceId(:final value):
          if (log.traceIdGroups.contains(value)) return true;
        case FilterTag(:final value):
          if (log.tags.contains(value)) return true;
      }
    }

    return false;
  }

  bool containsLevel(int level) => _values.contains(FilterLevel._(level));

  bool containsLogger(String logger) =>
      _values.contains(FilterLogger._(logger));

  bool containsTraceId(String? traceId) =>
      _values.contains(FilterTraceId._(traceId));

  bool containsTag(String tag) => _values.contains(FilterTag._(tag));

  bool addLevel(int level) {
    if (containsLevel(level)) return false;

    if (_requireParent.and.containsLevel(level)) {
      _clear();
      _values.add(FilterLevel._(level));
      _requireParent.and.resetLevel();
    } else {
      _values.add(FilterLevel._(level));
      _requireParent._update();
    }

    return true;
  }

  bool addLogger(String logger) {
    if (containsLogger(logger)) return false;

    if (_requireParent.and.containsLogger(logger)) {
      _clear();
      _values.add(FilterLogger._(logger));
      _requireParent.and.resetLogger();
    } else {
      _values.add(FilterLogger._(logger));
      _requireParent._update();
    }

    return true;
  }

  bool addTraceId(String? group) {
    if (containsTraceId(group)) return false;

    if (_requireParent.and.containsTraceId(group)) {
      _clear();
      _values.add(FilterTraceId._(group));
      _requireParent.and._values.removeWhere((e) => e is FilterTraceId);
    } else {
      _values.add(FilterTraceId._(group));
    }
    _requireParent._update();

    return true;
  }

  bool addTag(String tag) {
    if (containsTag(tag)) return false;

    if (_requireParent.and.containsTag(tag)) {
      _clear();
      _values.add(FilterTag._(tag));
      _requireParent.and._values.removeWhere((e) => e is FilterTag);
    } else {
      _values.add(FilterTag._(tag));
    }
    _requireParent._update();

    return true;
  }

  bool removeLevel(int level) {
    if (!_values.remove(FilterLevel._(level))) return false;

    _requireParent._update();
    return true;
  }

  bool removeLogger(String logger) {
    if (!_values.remove(FilterLogger._(logger))) return false;

    _requireParent._update();
    return true;
  }

  bool removeTraceId(String? group) {
    if (!_values.remove(FilterTraceId._(group))) return false;

    _requireParent._update();
    return true;
  }

  bool removeTag(String tag) {
    if (!_values.remove(FilterTag._(tag))) return false;

    _requireParent._update();
    return true;
  }

  void toggleLevel(int level) {
    if (containsLevel(level)) {
      removeLevel(level);
    } else {
      addLevel(level);
    }
  }

  void toggleLogger(String logger) {
    if (containsLogger(logger)) {
      removeLogger(logger);
    } else {
      addLogger(logger);
    }
  }

  void toggleTraceId(String group) {
    if (containsTraceId(group)) {
      removeTraceId(group);
    } else {
      addTraceId(group);
    }
  }

  void toggleTag(String tag) {
    if (containsTag(tag)) {
      removeTag(tag);
    } else {
      addTag(tag);
    }
  }
}

final class FilterAnd extends _FilterOp {
  FilterAnd._();

  @override
  bool call(Log log) {
    for (final v in _values) {
      switch (v) {
        case FilterLevel(:final value):
          if (log.level != value) return false;
        case FilterLogger(:final value):
          if (log.path != value) return false;
        case FilterTraceId(:final value):
          if (!log.traceIdGroups.contains(value)) return false;
        case FilterTag(:final value):
          if (!log.tags.contains(value)) return false;
      }
    }

    return true;
  }

  bool hasLevel() => _values.contains(FilterSingleLevel.any);

  bool containsLevel(int level) => _values.contains(FilterLevel._(level));

  bool hasLogger() => _values.contains(FilterSingleLogger.any);

  bool containsLogger(String logger) =>
      _values.contains(FilterLogger._(logger));

  bool containsTraceId(String? traceId) =>
      _values.contains(FilterTraceId._(traceId));

  bool containsTag(String tag) => _values.contains(FilterTag._(tag));

  bool addLevel(int level) {
    if (!_requireParent.or.isEnabled) {
      return _requireParent.or.addLevel(level);
    }

    if (containsLevel(level)) return false;

    if (_requireParent.or.containsLevel(level)) {
      _requireParent.or._clear();
      _requireParent.or._values.add(FilterLevel._(level));
    } else {
      final v = FilterSingleLevel._(level);
      _values
        ..remove(v)
        ..add(v);
    }
    _requireParent._update();

    return true;
  }

  bool addLogger(String logger) {
    if (!_requireParent.or.isEnabled) {
      return _requireParent.or.addLogger(logger);
    }

    if (containsLogger(logger)) return false;

    if (_requireParent.or.containsLogger(logger)) {
      _requireParent.or._clear();
      _requireParent.or._values.add(FilterLogger._(logger));
    } else {
      final v = FilterSingleLogger._(logger);
      _values
        ..remove(v)
        ..add(v);
    }
    _requireParent._update();

    return true;
  }

  bool addTraceId(String? group) {
    if (!_requireParent.or.isEnabled) {
      return _requireParent.or.addTraceId(group);
    }

    if (containsTraceId(group)) return false;

    if (_requireParent.or.containsTraceId(group)) {
      _requireParent.or._clear();
      _requireParent.or._values.add(FilterTraceId._(group));
    } else {
      final v = FilterTraceId._(group);
      _values
        ..remove(v)
        ..add(v);
    }
    _requireParent._update();

    return true;
  }

  bool addTag(String tag) {
    if (!_requireParent.or.isEnabled) {
      return _requireParent.or.addTag(tag);
    }

    if (containsTag(tag)) return false;

    if (_requireParent.or.containsTag(tag)) {
      _requireParent.or._clear();
      _requireParent.or._values.add(FilterTag._(tag));
    } else {
      final v = FilterTag._(tag);
      _values
        ..remove(v)
        ..add(v);
    }
    _requireParent._update();

    return true;
  }

  bool resetLevel() {
    if (!_values.remove(FilterSingleLevel.any)) return false;

    _requireParent._update();

    return true;
  }

  bool resetLogger() {
    if (!_values.remove(FilterSingleLogger.any)) return false;

    _requireParent._update();

    return true;
  }

  bool removeTraceId(String? group) {
    if (!_values.remove(FilterTraceId._(group))) return false;

    _requireParent._update();

    return true;
  }

  bool removeTag(String tag) {
    if (!_values.remove(FilterTag._(tag))) return false;

    _requireParent._update();

    return true;
  }

  void toggleLevel(int level) {
    if (containsLevel(level)) {
      resetLevel();
    } else {
      addLevel(level);
    }
  }

  void toggleLogger(String logger) {
    if (containsLogger(logger)) {
      resetLogger();
    } else {
      addLogger(logger);
    }
  }

  void toggleTraceId(String group) {
    if (containsTraceId(group)) {
      removeTraceId(group);
    } else {
      addTraceId(group);
    }
  }

  void toggleTag(String tag) {
    if (containsTag(tag)) {
      removeTag(tag);
    } else {
      addTag(tag);
    }
  }
}
