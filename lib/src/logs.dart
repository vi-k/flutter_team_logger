import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:team_logger/team_logger.dart';

import 'ansi_utils.dart';
import 'filter.dart';
import 'log_item.dart';
import 'notifier.dart';
import 'uikit/chip.dart' as ui;

final ThemeData _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.lightBlue,
    brightness: Brightness.dark,
  ),
);
const int _maxNewLogs = 100;
const EdgeInsets _listPadding = EdgeInsets.only(left: 6, right: 6);
const Color _pauseColor = Colors.amber;
const Color _onPauseColor = Colors.black;
const Color _filterColor = Colors.cyan;
const double _logsSeparator = 8;

class Logs extends StatefulWidget {
  /// Заголовок экрана.
  final String title;

  /// Тема для отрисовки логов из `team_builder`.
  final LogMainTheme theme;

  /// Хранилище логов из `team_builder`.
  final LogStorage logStorage;

  /// Длительность скроллинга при появлении нового лога.
  ///
  /// В реальности при появлении сразу нескольких логов длительность
  /// экспоненциально уменьшается. При уменьшении очереди накопленных логов
  /// длительность увеличивается до [scrollToBottomDuration]..
  final Duration scrollToBottomDuration;

  /// Кривая анимации скроллинга.
  final Curve scrollToBottomCurve;

  /// Callback при паузе.
  final void Function()? onPaused;

  /// Callback при возобновлении.
  final void Function()? onResumed;

  /// Callback при очистке.
  final void Function()? onCleared;

  const Logs({
    super.key,
    this.title = 'Logs',
    required this.theme,
    required this.logStorage,
    this.scrollToBottomDuration = const Duration(milliseconds: 300),
    this.scrollToBottomCurve = Curves.ease,
    this.onPaused,
    this.onResumed,
    this.onCleared,
  });

  @override
  State<Logs> createState() => LogsState();

  static LogsState of(BuildContext context) =>
      _LogsInheritedWidget.of(context).controller;
}

class LogsState extends State<Logs> with SingleTickerProviderStateMixin {
  /// Анимация скроллинга в [ScrollablePositionedList].
  ///
  /// В реальности нет никакого скроллинга логов. Анимация скроллинга
  /// осуществляется через изменение размера очередного лога.
  late final _animationController = AnimationController(
    vsync: this,
    duration: widget.scrollToBottomDuration,
  );

  /// Добавляем кривую к анимации скроллинга.
  late final animation =
      _animationController.drive(CurveTween(curve: widget.scrollToBottomCurve));

  /// Контроллер для управления скроллингом в [ScrollablePositionedList].
  final itemScrollController = ItemScrollController();

  /// Нотификатор для оповещения об обновлении логов.
  Listenable get onLogsChanged => _onLogsChanged;
  final _onLogsChanged = Notifier();

  /// Нотификатор для оповещения об обновлении видимой части логов.
  Listenable get onViewChanged => _onViewChanged;
  final _onViewChanged = Notifier();

  /// Флаг паузы.
  bool get paused => _paused.value;
  ValueListenable<bool> get onPauseChanged => _paused;
  final _paused = ValueNotifier<bool>(false);

  /// Логи.
  ///
  /// Храним свой собственный список логов, так как логи в [LogStorage] могут
  /// быть удалены.
  ///
  /// Следим за изменениями в [LogStorage] через [LogStorage.onChanged]. На
  /// время паузы не изменяем список: новые логи накапливаем в [newLogs],
  /// удаляемые - в [_removedLogs].
  List<Log> logs = <Log>[];

  /// Новые логи.
  ///
  /// Все новые логи накапливаются в этом списке и постепенно изымаются из
  /// него в [_startAddingAnimation]. Во время паузы не изымаются, только
  /// накапливаются.
  List<Log> newLogs = <Log>[];

  /// Режим новых логов.
  ///
  /// При одновременном появлении большого количества логов в AppBar
  /// показывается индикатор кол-ва новых логов в виде "987 +13", чтобы
  /// пользователь видел, что логи пришли, но ещё не появились.
  ///
  /// В обычном случае, когда логи появляются по одному или небольшим
  /// количеством, этот режим не включается, и в AppBar показывается сразу
  /// сумма текущих и новых логов: "1000".
  bool newLogsMode = false;

  /// Удаляемые логи, добавленные во время паузы
  ///
  /// Удаляем при возобновлении в [resume].
  var _removedLogs = <Log>[];

  /// Подписка на изменение логов в [LogStorage].
  late StreamSubscription<void> _onChangedSubscription;

  /// Фильтр логов.
  late final filter = Filter(
    logs: () => logs,
    newLogs: () => newLogs,
  );

  int get logsCount => filter.isEnabled ? filter.logs.length : logs.length;

  int get newLogsCount =>
      filter.isEnabled ? filter.newLogs.length : newLogs.length;

  Log logByIndex(int index) => (filter.isEnabled ? filter.logs : logs)[index];

  @override
  void initState() {
    super.initState();

    logs = widget.logStorage.snapshot();
    _subscribeToLogStorage();

    _onLogsChanged
      ..addListener(_handleLogsChanged)
      ..update();
    _onViewChanged
      ..addListener(_handleViewChanged)
      ..update();

    _animationController.addStatusListener(_animationStatusListener);

    filter.addListener(_filterChanged);
  }

  @override
  void dispose() {
    _onLogsChanged.dispose();
    _onViewChanged.dispose();
    _paused.dispose();
    filter.dispose();
    _onChangedSubscription.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant Logs oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.logStorage, widget.logStorage)) {
      _onChangedSubscription.cancel();
      _subscribeToLogStorage();
    }
  }

  void _subscribeToLogStorage() {
    _onChangedSubscription =
        widget.logStorage.onChanged.listen(_logStorageChanged);
  }

  void _filterChanged() {
    _stopAddingAnimation();
    _onViewChanged.update();
    _startAddingAnimation();
  }

  void pause() {
    if (paused) return;

    _paused.value = true;
    widget.onPaused?.call();
  }

  void resume() {
    if (!paused) return;

    _removedLogs.forEach(logs.remove);
    if (filter.isEnabled) {
      _removedLogs.forEach(filter.logs.remove);
    }
    _removedLogs.clear();
    _onLogsChanged.update();
    _onViewChanged.update();

    _paused.value = false;
    widget.onResumed?.call();
    if (logsCount > 0) {
      itemScrollController.scrollTo(
        index: 0,
        duration: widget.scrollToBottomDuration,
        curve: widget.scrollToBottomCurve,
      );
    }
    newLogsMode = true;
    _startAddingAnimation();
  }

  void clear() {
    widget.logStorage.clear();
    widget.onCleared?.call();
    if (paused) {
      resume();
    }
  }

  bool isLogRemoved(Log log) => _removedLogs.contains(log);

  void _logStorageChanged(LogStorageEvent event) {
    var viewUpdated = false;

    switch (event) {
      case LogStorageRemove(:final log):
        final index = newLogs.indexOf(log);
        if (index != -1) {
          newLogs.removeAt(index);
          if (filter.isEnabled) {
            filter.newLogs.remove(log);
          }
        } else if (paused) {
          _removedLogs.add(log);
          viewUpdated = true;
        } else {
          final updated = logs.remove(log);
          if (filter.isEnabled) {
            viewUpdated = filter.logs.remove(log);
          } else {
            viewUpdated = updated;
          }
        }

      case LogStorageClear():
        logs.clear();
        newLogs.clear();
        newLogsMode = false;
        viewUpdated = true;

        if (filter.isEnabled) {
          filter.logs.clear();
          filter.newLogs.clear();
        }
        _removedLogs = [];

      case LogStorageAdd(:final log):
        newLogs.add(log);

        if (filter.isEnabled) {
          if (filter(log)) {
            viewUpdated = true;
            filter.newLogs.add(log);
          }
        } else {
          viewUpdated = true;
        }

        if (viewUpdated) {
          _startAddingAnimation();
        }
    }

    _onLogsChanged.update();

    if (viewUpdated) {
      _onViewChanged.update();
    }
  }

  void _handleLogsChanged() {
    // Adjust values depending on logs count
    final newLogsCount = this.newLogsCount;
    final normalDuration = widget.scrollToBottomDuration.inMilliseconds;
    final duration = newLogsCount == 0
        ? normalDuration
        : (normalDuration / math.exp((newLogsCount - 1) / 10)).round();
    _animationController.duration = Duration(milliseconds: duration);

    if (newLogsCount >= 10) {
      newLogsMode = true;
    } else if (newLogsCount == 0) {
      newLogsMode = false;
    }
  }

  void _handleViewChanged() {
    //
  }

  void _startAddingAnimation() {
    if (_animationController.isAnimating || newLogs.isEmpty || paused) {
      return;
    }

    if (filter.isEnabled) {
      if (filter.newLogs.isEmpty) {
        logs.insertAll(0, newLogs);
        newLogs.clear();
        _onLogsChanged.update();
        return;
      }

      final newLogsCount = filter.newLogs.length;
      Log lastNewLog;
      if (newLogsCount > _maxNewLogs) {
        final extraLogsCount = newLogsCount - _maxNewLogs;
        final extraLogs = filter.newLogs.take(extraLogsCount).toList();
        filter.logs.insertAll(0, extraLogs);
        filter.newLogs.removeRange(0, extraLogsCount);
        lastNewLog = extraLogs.last;
      } else {
        final log = filter.newLogs.removeAt(0);
        filter.logs.insert(0, log);
        lastNewLog = log;
      }
      final index = newLogs.indexOf(lastNewLog);
      if (index != -1) {
        logs.insertAll(0, newLogs.take(index + 1));
        newLogs.removeRange(0, index + 1);
      }
    } else {
      final newLogsCount = newLogs.length;
      if (newLogsCount > _maxNewLogs) {
        final extraLogsCount = newLogsCount - _maxNewLogs;
        final extraLogs = newLogs.take(extraLogsCount);
        logs.insertAll(0, extraLogs);
        newLogs.removeRange(0, extraLogsCount);
      } else {
        final log = newLogs.removeAt(0);
        logs.insert(0, log);
      }
    }

    _onLogsChanged.update();
    _onViewChanged.update();

    _animationController
      ..reset()
      ..forward();
  }

  void _stopAddingAnimation() {
    if (_animationController.isAnimating) {
      _animationController.reset();
    }
  }

  void _animationStatusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _startAddingAnimation();
    }
  }

  @override
  Widget build(BuildContext context) => _LogsInheritedWidget(
        controller: this,
        child: Theme(
          data: _theme,
          child: ValueListenableBuilder<bool>(
            valueListenable: onPauseChanged,
            builder: (context, paused, _) => Scaffold(
              appBar: AppBar(
                forceMaterialTransparency: true,
                title: const _LogsAppBarTitle(),
                actions: const [
                  Visibility(
                    visible: false,
                    child: _FilterButton(),
                  ),
                  _ClearButton(),
                ],
              ),
              body: const SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FilterView(),
                    Expanded(child: _LogsList()),
                  ],
                ),
              ),
              floatingActionButton: paused //
                  ? const _ResumeButton()
                  : null,
            ),
          ),
        ),
      );
}

class _LogsInheritedWidget extends InheritedWidget {
  final LogsState controller;

  const _LogsInheritedWidget({
    required this.controller,
    required super.child,
  });

  static _LogsInheritedWidget of(BuildContext context) =>
      maybeOf(context) ??
      (throw Exception('$_LogsInheritedWidget not found in the context.'));

  static _LogsInheritedWidget? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_LogsInheritedWidget>();

  @override
  bool updateShouldNotify(_LogsInheritedWidget oldWidget) => false;
}

class _LogsAppBarTitle extends StatelessWidget {
  const _LogsAppBarTitle({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: controller.onPauseChanged,
      builder: (context, paused, _) => ListenableBuilder(
        listenable: controller.onLogsChanged,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(controller.widget.title),
            if (paused || controller.newLogsMode) ...[
              Text(
                ' ${controller.logsCount}',
                style: TextStyle(
                  fontSize: 12,
                  color: controller.filter.isEnabled ? _filterColor : null,
                ),
              ),
              if (controller.newLogsCount > 0)
                Text(
                  ' +${controller.newLogsCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _pauseColor,
                  ),
                ),
            ] else
              Text(
                ' ${controller.logsCount + controller.newLogsCount}',
                style: TextStyle(
                  fontSize: 12,
                  color: controller.filter.isEnabled ? _filterColor : null,
                ),
              ),
            if (controller.filter.isEnabled)
              Text(
                ' / ${controller.widget.logStorage.count}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);

    return ListenableBuilder(
      listenable: controller.onViewChanged,
      builder: (context, _) => IconButton(
        onPressed: controller.filter.disable,
        icon: const Icon(Icons.filter_alt),
        color: controller.filter.isEnabled ? _filterColor : null,
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);

    return IconButton(
      onPressed: controller.clear,
      icon: const Icon(Icons.delete_rounded),
    );
  }
}

class _FilterView extends StatefulWidget {
  const _FilterView({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  State<_FilterView> createState() => _FilterViewState();
}

class _FilterViewState extends State<_FilterView> {
  static const double _itemsSeparator = 6;

  late final LogsState _controller;

  final Map<int, int> _levelsLogsCount = {};
  final Map<int, int> _newLevelsLogsCount = {};
  List<int> _sortedLevels = [];

  final Map<String, int> _loggersLogsCount = {};
  final Map<String, int> _newLoggersLogsCount = {};
  List<String> _sortedLoggers = [];

  final Map<String?, int> _traceIdsLogsCount = {};
  final Map<String?, int> _newTraceIdsLogsCount = {};
  List<String?> _sortedTraceIds = [];
  late final Color _traceIdColor;

  @override
  void initState() {
    super.initState();

    _controller = Logs.of(context);

    _traceIdColor = ansiColor2Color(
          _controller.widget.theme.traceIdStyle.foregroundColor,
        ) ??
        _filterColor;

    _controller.onLogsChanged.addListener(_onLogsChanged);
    _onLogsChanged();
  }

  @override
  void dispose() {
    _controller.onLogsChanged.removeListener(_onLogsChanged);

    super.dispose();
  }

  void _onLogsChanged() {
    setState(() {
      _levelsLogsCount.clear();
      _newLevelsLogsCount.clear();
      _loggersLogsCount.clear();
      _newLoggersLogsCount.clear();
      _traceIdsLogsCount.clear();
      _newTraceIdsLogsCount.clear();

      final logs = _controller.logs;
      final newLogs = _controller.newLogs;

      _calcLevelsLogsCount(logs, _levelsLogsCount);
      _calcLoggersLogsCount(logs, _loggersLogsCount);
      _calcTraceIdsLogsCount(logs, _traceIdsLogsCount);
      if (_controller.paused || _controller.newLogsMode) {
        _calcLevelsLogsCount(newLogs, _newLevelsLogsCount);
        _calcLoggersLogsCount(newLogs, _newLoggersLogsCount);
        _calcTraceIdsLogsCount(newLogs, _newTraceIdsLogsCount);
      } else {
        _calcLevelsLogsCount(newLogs, _levelsLogsCount);
        _calcLoggersLogsCount(newLogs, _loggersLogsCount);
        _calcTraceIdsLogsCount(newLogs, _traceIdsLogsCount);
      }

      final levels = _levelsLogsCount.keys.toSet();
      final loggers = _loggersLogsCount.keys.toSet();
      final traceIds = _traceIdsLogsCount.keys.toSet();

      final filter = _controller.filter;
      if (filter.isEnabled) {
        levels.addAll(filter.levels);
        loggers.addAll(filter.loggers);
        traceIds.addAll(filter.traceIds);
      }

      _sortedLevels = levels.toList()..sort();
      _sortedLoggers = loggers.toList()..sort();
      _sortedTraceIds = traceIds.toList()..sort(_sortNullableStrings);
    });
  }

  int _sortNullableStrings(String? a, String? b) => a == null
      ? -1
      : b == null
          ? 1
          : a.compareTo(b);

  void _calcLevelsLogsCount(List<Log> logs, Map<int, int> to) {
    for (final log in logs) {
      final level = log.level;
      to[level] = (to[level] ?? 0) + 1;
    }
  }

  void _calcLoggersLogsCount(List<Log> logs, Map<String, int> to) {
    for (final log in logs) {
      final path = log.path;
      to[path] = (to[path] ?? 0) + 1;
    }
  }

  void _calcTraceIdsLogsCount(List<Log> logs, Map<String?, int> to) {
    for (final log in logs) {
      for (final traceId in log.traceIds) {
        final group = traceId.group;
        to[group] = (to[group] ?? 0) + 1;
      }
    }
  }

  Widget _buildLevelChip(int level, {bool first = false}) {
    final name = LogLevels.name(level);
    final color = ansiColor2Color(
          _controller.widget.theme[level].data.normal.foregroundColor,
        ) ??
        _filterColor;

    return _wrapWithStarter(
      label: 'level',
      color: color,
      first: first,
      child: ui.FilterChip(
        key: Key('level:$name'),
        color: color,
        title: name,
        logsCount: _levelsLogsCount[level] ?? 0,
        newLogsCount: _newLevelsLogsCount[level] ?? 0,
        active: _controller.filter.levelEnabled(level),
        onPressed: () {
          _controller.filter.toggleLevel(level);
        },
        onLongPress: () {
          _controller.filter.toggleOnlyLevel(level);
        },
      ),
    );
  }

  Widget _buildLoggerChip(String logger, {bool first = false}) =>
      _wrapWithStarter(
        label: 'logger',
        color: _filterColor,
        first: first,
        child: ui.FilterChip(
          key: Key('logger:$logger'),
          color: _filterColor,
          title: logger,
          logsCount: _loggersLogsCount[logger] ?? 0,
          newLogsCount: _newLoggersLogsCount[logger] ?? 0,
          active: _controller.filter.loggerEnabled(logger),
          onPressed: () {
            _controller.filter.toggleLogger(logger);
          },
          onLongPress: () {
            _controller.filter.toggleOnlyLogger(logger);
          },
        ),
      );

  Widget _buildTraceIdChip(String? group, {bool first = false}) =>
      _wrapWithStarter(
        label: 'trace id',
        color: _traceIdColor,
        first: first,
        child: ui.FilterChip(
          color: _traceIdColor,
          title: group ?? 'global',
          logsCount: _traceIdsLogsCount[group] ?? 0,
          newLogsCount: _newTraceIdsLogsCount[group] ?? 0,
          active: _controller.filter.traceIdEnabled(group),
          onPressed: () {
            _controller.filter.toggleTraceId(group);
          },
          onLongPress: () {
            _controller.filter.toggleOnlyTraceId(group);
          },
        ),
      );

  Widget _wrapWithStarter({
    required String label,
    required Color color,
    required bool first,
    required Widget child,
  }) {
    if (!first) return child;

    return Row(
      key: child.key,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Starter(
          label: label,
          color: color,
          padding: const EdgeInsets.only(right: _itemsSeparator),
        ),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _controller.filter,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.only(
            left: _itemsSeparator,
            right: _itemsSeparator,
            bottom: _itemsSeparator,
          ),
          child: Wrap(
            spacing: _itemsSeparator,
            runSpacing: _itemsSeparator,
            children: [
              for (final (index, level) in _sortedLevels.indexed)
                _buildLevelChip(level, first: index == 0),
              for (final (index, logger) in _sortedLoggers.indexed)
                _buildLoggerChip(logger, first: index == 0),
              for (final (index, group) in _sortedTraceIds.indexed)
                _buildTraceIdChip(group, first: index == 0),
            ],
          ),
        ),
      );
}

class _LogsList extends StatelessWidget {
  const _LogsList({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        switch (notification) {
          case UserScrollNotification()
              when !controller.paused &&
                  notification.direction == ScrollDirection.reverse:
            SchedulerBinding.instance.addPostFrameCallback((_) {
              controller.pause();
            });
        }

        return false;
      },
      child: ListenableBuilder(
        listenable: controller.onViewChanged,
        builder: (context, _) => Stack(
          children: [
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
              ),
              child: ScrollablePositionedList.builder(
                itemScrollController: controller.itemScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: _listPadding,
                reverse: true,
                itemCount: controller.logsCount,
                itemBuilder: (_, index) {
                  final log = controller.logByIndex(index);
                  final item = Padding(
                    key: ObjectKey(log),
                    padding: const EdgeInsets.only(
                      bottom: _logsSeparator,
                    ),
                    child: LogItem(
                      log,
                      controller.widget.theme[log.level],
                      removed: controller.isLogRemoved(log),
                      onTapDown: controller.pause,
                    ),
                  );

                  if (index != 0 || !controller.animation.isAnimating) {
                    return item;
                  }

                  return AnimatedBuilder(
                    animation: controller.animation,
                    builder: (context, _) => ClipRect(
                      child: Align(
                        heightFactor: controller.animation.value,
                        alignment: Alignment.topCenter,
                        child: item,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeButton extends StatelessWidget {
  const _ResumeButton({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);

    return FloatingActionButton.small(
      onPressed: controller.resume,
      backgroundColor: _pauseColor,
      foregroundColor: _onPauseColor,
      child: const Icon(Icons.keyboard_double_arrow_down_rounded),
    );
  }
}

class _Starter extends StatelessWidget {
  final Color color;
  final String label;
  final EdgeInsetsGeometry padding;

  const _Starter({
    // ignore: unused_element_parameter
    super.key,
    required this.color,
    required this.padding,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Container(
            //   width: 4,
            //   height: 6,
            //   decoration: BoxDecoration(
            //     borderRadius: BorderRadius.circular(100),
            //     color: color,
            //   ),
            // ),
            Text(
              '$label:',
              style: TextStyle(
                fontSize: 9,
                color: color,
              ),
            ),
          ],
        ),
      );
}
