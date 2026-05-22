import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:team_logger/team_logger.dart';

final class Filter with ChangeNotifier {
  final List<Log> Function() _getLogs;
  final List<Log> Function() _getNewLogs;

  bool isEnabled = false;

  final Set<int> _levels = {};
  Set<int> get levels => UnmodifiableSetView(_levels);

  final Set<String> _loggers = {};
  Set<String> get loggers => UnmodifiableSetView(_loggers);

  final Set<String?> _traceIds = {};
  Set<String?> get traceIds => UnmodifiableSetView(_traceIds);

  final List<Log> logs = [];
  final List<Log> newLogs = [];

  Filter({
    required List<Log> Function() logs,
    required List<Log> Function() newLogs,
  })  : _getLogs = logs,
        _getNewLogs = newLogs;

  bool call(Log log) =>
      (_levels.isEmpty || _levels.contains(log.level)) &&
      (_loggers.isEmpty || _loggers.contains(log.path)) &&
      (_traceIds.isEmpty ||
          log.traceIds.any((traceId) => _traceIds.contains(traceId.group)));

  bool levelEnabled(int level) => _levels.contains(level);

  bool loggerEnabled(String logger) => _loggers.contains(logger);

  bool traceIdEnabled(String? group) => _traceIds.contains(group);

  void disable() {
    _levels.clear();
    _loggers.clear();
    _traceIds.clear();
    _update();
  }

  void _update() {
    isEnabled =
        _levels.isNotEmpty || _loggers.isNotEmpty || _traceIds.isNotEmpty;

    logs.clear();
    newLogs.clear();
    if (isEnabled) {
      logs.addAll(_getLogs().where(call));
      newLogs.addAll(_getNewLogs().where(call));
    }

    notifyListeners();
  }

  void toggleLevel(int level) {
    if (_levels.contains(level)) {
      _levels.remove(level);
    } else {
      _levels.add(level);
    }
    _update();
  }

  void toggleOnlyLevel(int level) {
    disable();
    _levels.add(level);
    _update();
  }

  void toggleLogger(String logger) {
    if (_loggers.contains(logger)) {
      _loggers.remove(logger);
    } else {
      _loggers.add(logger);
    }
    _update();
  }

  void toggleOnlyLogger(String logger) {
    disable();
    _loggers.add(logger);
    _update();
  }

  void toggleTraceId(String? group) {
    if (_traceIds.contains(group)) {
      _traceIds.remove(group);
    } else {
      _traceIds.add(group);
    }
    _update();
  }

  void toggleOnlyTraceId(String? group) {
    disable();
    _traceIds.add(group);
    _update();
  }
}
