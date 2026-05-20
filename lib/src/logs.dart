import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:team_logger/team_logger.dart';

import 'ansi_utils.dart';
import 'filter.dart';
import 'log_item.dart';

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
const Color _filterColor = Colors.lightBlue;
const double _logsSeparator = 8;

class Logs extends StatefulWidget {
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
  late final _animation =
      _animationController.drive(CurveTween(curve: widget.scrollToBottomCurve));

  /// Контроллер для управления скроллингом в [ScrollablePositionedList].
  final _itemScrollController = ItemScrollController();

  /// Нотификатор для оповещения об обновлении списка логов.
  ///
  /// Счётчик не используется, нужен только для сигнала об изменении.
  final onListChanged = ValueNotifier<int>(0);

  /// Флаг паузы.
  final paused = ValueNotifier<bool>(false);

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
  /// Удаляем при возобновлении в [_resume].
  var _removedLogs = <Log>[];

  /// Подписка на изменение логов в [LogStorage].
  late StreamSubscription<void> _onChangedSubscription;

  /// Фильтр логов.
  late final filter = Filter(
    logs: () => logs,
    newLogs: () => newLogs,
  );

  int get logsCount => filter.isEnabled ? filter.logs.length : logs.length;

  final Map<int, int> leveledLogsCount = {};

  int get newLogsCount =>
      filter.isEnabled ? filter.newLogs.length : newLogs.length;

  Log logByIndex(int index) => (filter.isEnabled ? filter.logs : logs)[index];

  @override
  void initState() {
    super.initState();

    logs = widget.logStorage.snapshot();
    _adjustValuesDependingOnLogsChanged();
    _subscribe();
    _animationController.addStatusListener(_animationStatusListener);

    filter.addListener(_filterChanged);
  }

  @override
  void dispose() {
    onListChanged.dispose();
    paused.dispose();
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
      _subscribe();
    }
  }

  void _subscribe() {
    _onChangedSubscription = widget.logStorage.onChanged.listen(_logsChanged);
  }

  void _updateList() {
    onListChanged.value++;
  }

  void _filterChanged() {
    _stopAddingAnimation();
    _updateList();
    _startAddingAnimation();
  }

  void _pause() {
    if (paused.value) return;

    paused.value = true;
    widget.onPaused?.call();
  }

  void _resume() {
    if (!paused.value) return;

    _removedLogs
      ..forEach(logs.remove)
      ..clear();

    paused.value = false;
    widget.onResumed?.call();
    if (logsCount > 0) {
      _itemScrollController.scrollTo(
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
    if (paused.value) {
      _resume();
    }
  }

  void _logsChanged(LogStorageEvent event) {
    switch (event) {
      case LogStorageRemove(:final log):
        final index = newLogs.indexOf(log);
        if (index != -1) {
          newLogs.removeAt(index);
          if (filter.isEnabled) {
            filter.newLogs.remove(log);
          }
        } else if (paused.value) {
          _removedLogs.add(log);
        } else {
          logs.remove(log);
          if (filter.isEnabled) {
            filter.logs.remove(log);
          }
        }
        _adjustValuesDependingOnLogsChanged();

      case LogStorageClear():
        logs = [];
        newLogs = [];
        newLogsMode = false;
        _adjustValuesDependingOnLogsChanged();

        if (filter.isEnabled) {
          filter.logs.clear();
          filter.newLogs.clear();
        }
        _removedLogs = [];

      case LogStorageAdd(:final log):
        var update = false;
        newLogs.add(log);
        _adjustValuesDependingOnLogsChanged();

        if (filter.isEnabled) {
          if (filter(log)) {
            update = true;
            filter.newLogs.add(log);
          }
        } else {
          update = true;
        }

        if (update) {
          _adjustValuesDependingOnLogsCount();
          _startAddingAnimation();
        }
    }

    _updateList();
  }

  void _adjustValuesDependingOnLogsCount() {
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

  void _adjustValuesDependingOnLogsChanged() {
    for (final level in LogLevels.values) {
      leveledLogsCount[level] = logs.where((log) => log.level == level).length;
    }
  }

  void _startAddingAnimation() {
    if (_animationController.isAnimating || newLogs.isEmpty || paused.value) {
      return;
    }

    if (filter.isEnabled) {
      if (filter.newLogs.isEmpty) {
        logs.insertAll(0, newLogs);
        newLogs.clear();
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

    _adjustValuesDependingOnLogsCount();
    _updateList();
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
            valueListenable: paused,
            builder: (context, paused, _) => Scaffold(
              appBar: AppBar(
                forceMaterialTransparency: true,
                title: const _AppBarTitle(),
                actions: const [
                  Visibility(
                    // visible: false,
                    child: _FilterButton(),
                  ),
                  _ClearButton(),
                ],
              ),
              body: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FilterView(),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          switch (notification) {
                            case UserScrollNotification()
                                when !this.paused.value &&
                                    notification.direction ==
                                        ScrollDirection.reverse:
                              SchedulerBinding.instance
                                  .addPostFrameCallback((_) {
                                _pause();
                              });
                          }

                          return false;
                        },
                        child: ListenableBuilder(
                          listenable: onListChanged,
                          builder: (context, _) => Stack(
                            children: [
                              ScrollConfiguration(
                                behavior:
                                    ScrollConfiguration.of(context).copyWith(
                                  scrollbars: false,
                                ),
                                child: ScrollablePositionedList.builder(
                                  itemScrollController: _itemScrollController,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: _listPadding,
                                  reverse: true,
                                  itemCount: logsCount,
                                  itemBuilder: (_, index) {
                                    final log = logByIndex(index);
                                    final item = Padding(
                                      key: ObjectKey(log),
                                      padding: const EdgeInsets.only(
                                        bottom: _logsSeparator,
                                      ),
                                      child: LogItem(
                                        log,
                                        widget.theme[log.level],
                                        removed: _removedLogs.contains(log),
                                        onTapDown: _pause,
                                      ),
                                    );

                                    if (index != 0 ||
                                        !_animationController.isAnimating) {
                                      return item;
                                    }

                                    return AnimatedBuilder(
                                      animation: _animation,
                                      builder: (context, _) => ClipRect(
                                        child: Align(
                                          heightFactor: _animation.value,
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
                      ),
                    ),
                  ],
                ),
              ),
              floatingActionButton: paused
                  ? FloatingActionButton.small(
                      onPressed: _resume,
                      backgroundColor: _pauseColor,
                      foregroundColor: _onPauseColor,
                      child:
                          const Icon(Icons.keyboard_double_arrow_down_rounded),
                    )
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

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: controller.paused,
      builder: (context, paused, _) => ListenableBuilder(
        listenable: controller.onListChanged,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('Logs'),
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
      listenable: controller.onListChanged,
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

class _FilterView extends StatelessWidget {
  static const double _itemsSeparator = 6;

  const _FilterView({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);
    final filter = controller.filter;

    return DefaultTextStyle(
      style: const TextStyle(fontSize: 12),
      child: ListenableBuilder(
        listenable: controller.filter,
        builder: (context, _) => ListenableBuilder(
          listenable: controller.onListChanged,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: _itemsSeparator,
              runSpacing: _itemsSeparator,
              children: [
                for (final level in LogLevels.values)
                  _LevelChip(
                    level: level,
                    active: filter.levelEnabled(level),
                    onPressed: () {
                      controller.filter.toggleLevel(level);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  static const double _borderRadius = 8;

  final Color color;
  final bool active;
  final Widget text;
  final void Function()? onPressed;

  const _Chip({
    // ignore: unused_element_parameter
    super.key,
    this.active = false,
    required this.color,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onPressed,
        focusColor: color.withValues(alpha: 0.2),
        highlightColor: color.withValues(alpha: 0.3),
        splashColor: color.withValues(alpha: 0.4),
        hoverColor: color.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.all(
          Radius.circular(_borderRadius),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            borderRadius: const BorderRadius.all(
              Radius.circular(_borderRadius),
            ),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: text,
        ),
      );
}

class _LevelChip extends StatelessWidget {
  final int level;
  final bool active;
  final void Function()? onPressed;

  const _LevelChip({
    // ignore: unused_element_parameter
    super.key,
    required this.level,
    this.active = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);
    final color = ansiColor2Color(
          controller.widget.theme[level].data.normal.foregroundColor,
        ) ??
        _filterColor;
    final count = controller.leveledLogsCount[level];

    return _Chip(
      color: color,
      active: active,
      text: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            text: TextSpan(
              text: LogLevels.name(level),
              style: TextStyle(
                color: active ? Color.lerp(color, Colors.black, 0.9) : color,
                fontSize: 12,
              ),
            ),
          ),
          if (count != null)
            RichText(
              text: TextSpan(
                text: '($count)',
                style: TextStyle(
                  color: active ? Color.lerp(color, Colors.black, 0.9) : color,
                  fontSize: 8,
                ),
              ),
            ),
        ],
      ),
      onPressed: onPressed,
    );
  }
}
