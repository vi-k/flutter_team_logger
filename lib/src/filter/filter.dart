import 'dart:async';
import 'dart:collection';

import 'package:team_logger/team_logger.dart';

import '../utils/stream_notifier.dart';
import 'filter_exp.dart';

final class Filter extends StreamNotifier {
  final List<Log> Function() _getAllLogs;
  final List<Log> Function() _getAllNewLogs;

  final List<FilterExp> _filters = [];

  Filter({
    required List<Log> Function() logs,
    required List<Log> Function() newLogs,
  })  : _getAllLogs = logs,
        _getAllNewLogs = newLogs {
    update();
  }

  final List<Log> _filteredLogs = [];
  final List<Log> _filteredNewLogs = [];

  List<Log> get logs => isEnabled ? _filteredLogs : _getAllLogs();
  List<Log> get newLogs => isEnabled ? _filteredNewLogs : _getAllNewLogs();

  bool get isEnabled => _filters.any((e) => e.isEnabled);

  List<FilterExp> get filters => UnmodifiableListView(_filters);

  Map<int, (int, int)> get availableLevels =>
      UnmodifiableMapView(_availableLevels);
  Map<int, (int, int)> _availableLevels = {};

  Map<String, (int, int)> get availableLoggers =>
      UnmodifiableMapView(_availableLoggers);
  Map<String, (int, int)> _availableLoggers = {};

  Map<String?, (int, int)> get availableTraceIds =>
      UnmodifiableMapView(_availableTraceIds);
  Map<String?, (int, int)> _availableTraceIds = {};

  Map<String, (int, int)> get availableTags =>
      UnmodifiableMapView(_availableTags);
  Map<String, (int, int)> _availableTags = {};

  bool call(Log log) =>
      _filters.isEmpty || _filters.any((filter) => filter(log));

  void _clear() {
    for (final e in _filters) {
      e.dispose();
    }
    _filters.clear();
  }

  void disable() {
    _clear();
    update();
  }

  void update() {
    var last = _filters.lastOrNull;
    while (last != null && !last.isEnabled) {
      _filters.remove(last);
      scheduleMicrotask(last.dispose);
      last = _filters.lastOrNull;
    }

    _filteredLogs.clear();
    _filteredNewLogs.clear();
    if (isEnabled) {
      _filteredLogs.addAll(_getAllLogs().where(call));
      _filteredNewLogs.addAll(_getAllNewLogs().where(call));
    } else {
      _filteredLogs.addAll(_getAllLogs());
      _filteredNewLogs.addAll(_getAllNewLogs());
    }

    _calcAvailableLevels();
    _calcAvailableLoggers();
    _calcAvailableTraceIds();
    _calcAvailableTags();

    notifyListeners();
  }

  /// Adds a new log to the pending list.
  ///
  /// Returns true if the displayed logs were updated.
  bool addNewLog(Log log) {
    _getAllNewLogs().add(log);
    if (!isEnabled) return true;

    if (call(log)) {
      _filteredNewLogs.add(log);
      return true;
    }

    return false;
  }

  bool removeLog(Log log) {
    var removed = _getAllLogs().remove(log);
    if (isEnabled) {
      removed = _filteredLogs.remove(log);
    }
    if (removed) update();

    return removed;
  }

  bool removeNewLog(Log log) {
    var removed = _getAllNewLogs().remove(log);
    if (isEnabled) {
      removed = _filteredNewLogs.remove(log);
    }
    if (removed) update();

    return removed;
  }

  bool moveNextNewLogToLogs() {
    const maxNewLogs = 100;

    final allLogs = _getAllLogs();
    final allNewLogs = _getAllNewLogs();
    if (allNewLogs.isEmpty) {
      return false;
    }

    if (isEnabled) {
      // If there are no filtered new logs at all, move all new logs over.
      if (_filteredNewLogs.isEmpty) {
        allLogs.insertAll(0, allNewLogs);
        allNewLogs.clear();
        update();
        return true;
      }

      final extraLogsCount = _filteredNewLogs.length - maxNewLogs;
      Log lastNewLog;
      if (extraLogsCount > 0) {
        // Move as a batch.
        final extraLogs = _filteredNewLogs.take(extraLogsCount).toList();
        _filteredLogs.insertAll(0, extraLogs);
        _filteredNewLogs.removeRange(0, extraLogsCount);
        lastNewLog = extraLogs.last;
      } else {
        // Move one at a time.
        final log = _filteredNewLogs.removeAt(0);
        _filteredLogs.insert(0, log);
        lastNewLog = log;
      }
      // From the shared lists, move over every log that came before the one
      // just moved.
      final index = allNewLogs.indexOf(lastNewLog);
      allLogs.insertAll(0, allNewLogs.take(index + 1));
      allNewLogs.removeRange(0, index + 1);
    } else {
      final extraLogsCount = allNewLogs.length - maxNewLogs;
      if (extraLogsCount > 0) {
        // Move as a batch.
        final extraLogs = allNewLogs.take(extraLogsCount);
        allLogs.insertAll(0, extraLogs);
        allNewLogs.removeRange(0, extraLogsCount);
      } else {
        // Move one at a time.
        final log = allNewLogs.removeAt(0);
        allLogs.insert(0, log);
      }
    }

    update();
    return true;
  }

  void orLevel(int level) => _or(
        level,
        (f) => f.or.containsLevel(level),
        (f) => f.or.addLevel(level),
        (f) => f.or.removeLevel(level),
      );

  void orLogger(String logger) => _or(
        logger,
        (f) => f.or.containsLogger(logger),
        (f) => f.or.addLogger(logger),
        (f) => f.or.removeLogger(logger),
      );

  void orTraceId(String? traceId) => _or(
        traceId,
        (f) => f.or.containsTraceId(traceId),
        (f) => f.or.addTraceId(traceId),
        (f) => f.or.removeTraceId(traceId),
      );

  void orTag(String tag) => _or(
        tag,
        (f) => f.or.containsTag(tag),
        (f) => f.or.addTag(tag),
        (f) => f.or.removeTag(tag),
      );

  void andLevel(int level) => _and(
        level,
        (f) => f.and.containsLevel(level),
        (f) => f.and.addLevel(level),
        (f) => f.and.resetLevel(),
      );

  void andLogger(String logger) => _and(
        logger,
        (f) => f.and.containsLogger(logger),
        (f) => f.and.addLogger(logger),
        (f) => f.and.resetLogger(),
      );

  void andTraceId(String? traceId) => _and(
        traceId,
        (f) => f.and.containsTraceId(traceId),
        (f) => f.and.addTraceId(traceId),
        (f) => f.and.removeTraceId(traceId),
      );

  void andTag(String tag) => _and(
        tag,
        (f) => f.and.containsTag(tag),
        (f) => f.and.addTag(tag),
        (f) => f.and.removeTag(tag),
      );

  void undo() {
    if (_filters.isEmpty) return;

    if (!_filters.last.undo()) {
      _filters.removeLast();
      update();
    }
  }

  void _addFilter(FilterExp filter) {
    _filters.add(filter);
    filter.addListener(update);
  }

  void _calcAvailableLevels() {
    _availableLevels = _calcAvailableValues((log) => log.level);
    for (final FilterExp(:or, :and) in _filters) {
      for (final FilterLevel(:value) in or.values.whereType<FilterLevel>()) {
        _availableLevels[value] ??= (0, 0);
      }
      for (final FilterLevel(:value) in and.values.whereType<FilterLevel>()) {
        _availableLevels[value] ??= (0, 0);
      }
    }
  }

  void _calcAvailableLoggers() {
    _availableLoggers = _calcAvailableValues((log) => log.path);
    for (final FilterExp(:or, :and) in _filters) {
      for (final FilterLogger(:value) in or.values.whereType<FilterLogger>()) {
        _availableLoggers[value] ??= (0, 0);
      }
      for (final FilterLogger(:value) in and.values.whereType<FilterLogger>()) {
        _availableLoggers[value] ??= (0, 0);
      }
    }
  }

  void _calcAvailableTraceIds() {
    _availableTraceIds = _calcAvailableListValues(
      (log) => log.traceIds.map((e) => e.group),
      _compareNullableStrings,
    );
    for (final FilterExp(:or, :and) in _filters) {
      for (final FilterTraceId(:value)
          in or.values.whereType<FilterTraceId>()) {
        _availableTraceIds[value] ??= (0, 0);
      }
      for (final FilterTraceId(:value)
          in and.values.whereType<FilterTraceId>()) {
        _availableTraceIds[value] ??= (0, 0);
      }
    }
  }

  void _calcAvailableTags() {
    _availableTags = _calcAvailableListValues((log) => log.tags);
    for (final FilterExp(:or, :and) in _filters) {
      for (final FilterTag(:value) in or.values.whereType<FilterTag>()) {
        _availableTags[value] ??= (0, 0);
      }
      for (final FilterTag(:value) in and.values.whereType<FilterTag>()) {
        _availableTags[value] ??= (0, 0);
      }
    }
  }

  int _compareNullableStrings(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return a.compareTo(b);
  }

  Map<T, (int, int)> _calcAvailableValues<T>(T Function(Log log) value) {
    final result = SplayTreeMap<T, (int, int)>();

    // All available values.
    for (final log in _getAllLogs()) {
      final v = value(log);
      final (filtered, total) = result[v] ?? (0, 0);
      result[v] = (filtered, total + 1);
    }

    // Count among the visible logs.
    for (final log in logs) {
      final v = value(log);
      final (filtered, total) = result[v] ?? (0, 0);
      result[v] = (filtered + 1, total);
    }

    return result;
  }

  Map<T, (int, int)> _calcAvailableListValues<T>(
    Iterable<T> Function(Log log) list, [
    int Function(T a, T b)? compare,
  ]) {
    final result = SplayTreeMap<T, (int, int)>(compare);

    // All available values.
    for (final log in _getAllLogs()) {
      for (final v in list(log)) {
        final (filtered, total) = result[v] ?? (0, 0);
        result[v] = (filtered, total + 1);
      }
    }

    // Count among the visible logs.
    for (final log in logs) {
      for (final v in list(log)) {
        final (filtered, total) = result[v] ?? (0, 0);
        result[v] = (filtered + 1, total);
      }
    }

    return result;
  }

  void _or<T>(
    T value,
    bool Function(FilterExp filter) contains,
    void Function(FilterExp filter) add,
    void Function(FilterExp filter) remove,
  ) {
    if (_filters.isEmpty || _filters.last.and.isEnabled) {
      final filter = FilterExp();
      _addFilter(filter);
      add(filter);
    } else {
      final filter = _filters.last;
      if (contains(filter)) {
        remove(filter);
      } else {
        add(filter);
      }
    }
  }

  void _and<T>(
    T value,
    bool Function(FilterExp filter) contains,
    void Function(FilterExp filter) add,
    void Function(FilterExp filter) remove,
  ) {
    if (_filters.isEmpty) {
      final filter = FilterExp();
      _addFilter(filter);
      add(filter);
    } else {
      final filter = _filters.last;
      if (contains(filter)) {
        remove(filter);
      } else {
        add(filter);
      }
    }
  }

  String toColorizedString(LogTheme theme) => switch (_filters) {
        [] => '',
        [final f] => f.toColorizedString(theme),
        [...final filters] => filters
            .map(
              (f) => '${theme.data.punctuation('[')}'
                  '${f.toColorizedString(theme)}'
                  '${theme.data.punctuation(']')}',
            )
            .join('  ${theme.data.punctuation(FilterExp.orSign)}  '),
      };

  @override
  String toString() => switch (_filters) {
        [] => '',
        [final f] => '$f',
        [...final filters] =>
          filters.map((f) => '[ $f ]').join(' ${FilterExp.orSign} '),
      };
}
