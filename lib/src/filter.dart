import 'package:flutter/foundation.dart';
import 'package:team_logger/team_logger.dart';

final class Filter with ChangeNotifier {
  final List<Log> Function() _getLogs;
  final List<Log> Function() _getNewLogs;

  bool isEnabled = false;

  final Set<int> _levels = {};

  final List<Log> logs = [];
  final List<Log> newLogs = [];

  Filter({
    required List<Log> Function() logs,
    required List<Log> Function() newLogs,
  })  : _getLogs = logs,
        _getNewLogs = newLogs;

  bool call(Log log) => _levels.isEmpty || _levels.contains(log.level);

  bool levelEnabled(int level) => _levels.contains(level);

  void disable() {
    _levels.clear();
    _update();
  }

  void _update() {
    isEnabled = _levels.isNotEmpty;

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
}
