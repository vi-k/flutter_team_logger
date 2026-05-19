import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:team_logger/team_logger.dart';

import 'log_item.dart';

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
  State<Logs> createState() => _LogsState();
}

class _LogsState extends State<Logs> with SingleTickerProviderStateMixin {
  static const _maxNewLogs = 100;
  static const _listPadding = EdgeInsets.only(left: 6, right: 6);
  static const _pauseColor = Colors.amber;
  static const _onPauseColor = Colors.black;
  static const _filterColor = Colors.lightBlue;
  static const _itemsSeparator = 8.0;

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
  final _updateListNotifier = ValueNotifier<int>(0);

  /// Флаг паузы.
  final _paused = ValueNotifier<bool>(false);

  /// Логи.
  ///
  /// Храним свой собственный список логов, так как логи в [LogStorage] могут
  /// быть удалены.
  ///
  /// Следим за изменениями в [LogStorage] через [LogStorage.onChanged]. На
  /// время паузы не изменяем список: новые логи накапливаем в [_newLogs],
  /// удаляемые - в [_removedLogs].
  var _logs = <Log>[];

  /// Новые логи.
  ///
  /// Все новые логи накапливаются в этом списке и постепенно изымаются из
  /// него в [_startAddingAnimation]. Во время паузы не изымаются, только
  /// накапливаются.
  var _newLogs = <Log>[];

  /// Режим новых логов.
  ///
  /// При одновременном появлении большого количества логов в AppBar
  /// показывается индикатор кол-ва новых логов в виде "987 +13", чтобы
  /// пользователь видел, что логи пришли, но ещё не появились.
  ///
  /// В обычном случае, когда логи появляются по одному или небольшим
  /// количеством, этот режим не включается, и в AppBar показывается сразу
  /// сумма текущих и новых логов: "1000".
  bool _newLogsMode = false;

  /// Удаляемые логи, добавленные во время паузы
  ///
  /// Удаляем при возобновлении в [_resume].
  var _removedLogs = <Log>[];

  /// Подписка на изменение логов в [LogStorage].
  late StreamSubscription<void> _onChangedSubscription;

  /// Фильтр логов.
  _Filter? _filter;

  /// Включен ли фильтр.
  bool get _filtered => _filter != null;

  int get _logsCount => _filter?.logs.length ?? _logs.length;

  int get _newLogsCount => _filter?.newLogs.length ?? _newLogs.length;

  Log _logByIndex(int index) => (_filter?.logs ?? _logs)[index];

  @override
  void initState() {
    super.initState();

    _logs = widget.logStorage.snapshot();
    _subscribe();
    _animationController.addStatusListener(_animationStatusListener);
  }

  @override
  void dispose() {
    _updateListNotifier.dispose();
    _paused.dispose();
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
    _updateListNotifier.value++;
  }

  void _pause() {
    if (_paused.value) return;

    _paused.value = true;
    widget.onPaused?.call();
  }

  void _resume() {
    if (!_paused.value) return;

    _removedLogs
      ..forEach(_logs.remove)
      ..clear();

    _paused.value = false;
    widget.onResumed?.call();
    if (_logsCount > 0) {
      _itemScrollController.scrollTo(
        index: 0,
        duration: widget.scrollToBottomDuration,
        curve: widget.scrollToBottomCurve,
      );
    }
    _newLogsMode = true;
    _startAddingAnimation();
  }

  void _clear() {
    widget.logStorage.clear();
    widget.onCleared?.call();
    if (_paused.value) {
      _resume();
    }
  }

  void _logsChanged(LogStorageEvent event) {
    _updateList();

    switch (event) {
      case LogStorageRemove(:final log):
        final index = _newLogs.indexOf(log);
        if (index != -1) {
          _newLogs.removeAt(index);
          _filter?.newLogs.remove(log);
        } else if (_paused.value) {
          _removedLogs.add(log);
        } else {
          _logs.remove(log);
          _filter?.logs.remove(log);
        }

      case LogStorageClear():
        _logs = [];
        _newLogs = [];
        _filter?.logs.clear();
        _filter?.newLogs.clear();
        _removedLogs = [];
        _newLogsMode = false;

      case LogStorageAdd(:final log):
        var update = false;
        _newLogs.add(log);
        if (_filter case final filter?) {
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
  }

  void _adjustValuesDependingOnLogsCount() {
    final newLogsCount = _newLogsCount;
    final normalDuration = widget.scrollToBottomDuration.inMilliseconds;
    final duration = newLogsCount == 0
        ? normalDuration
        : (normalDuration / math.exp((newLogsCount - 1) / 10)).round();
    _animationController.duration = Duration(milliseconds: duration);

    if (newLogsCount >= 10) {
      _newLogsMode = true;
    } else if (newLogsCount == 0) {
      _newLogsMode = false;
    }
  }

  void _startAddingAnimation() {
    if (_animationController.isAnimating || _newLogs.isEmpty || _paused.value) {
      return;
    }

    if (_filter case final filter?) {
      if (filter.newLogs.isEmpty) {
        _logs.insertAll(0, _newLogs);
        _newLogs.clear();
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
      final index = _newLogs.indexOf(lastNewLog);
      if (index != -1) {
        _logs.insertAll(0, _newLogs.take(index + 1));
        _newLogs.removeRange(0, index + 1);
      }
    } else {
      final newLogsCount = _newLogs.length;
      if (newLogsCount > _maxNewLogs) {
        final extraLogsCount = newLogsCount - _maxNewLogs;
        final extraLogs = _newLogs.take(extraLogsCount);
        _logs.insertAll(0, extraLogs);
        _newLogs.removeRange(0, extraLogsCount);
      } else {
        final log = _newLogs.removeAt(0);
        _logs.insert(0, log);
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

  void _setFilter(bool Function(Log log)? filter) {
    if (filter == null) {
      _filter = null;
    } else {
      _filter = _Filter(filter)
        ..logs.addAll(_logs.where(filter))
        ..newLogs.addAll(_newLogs.where(filter));
    }
    _stopAddingAnimation();
    _updateList();
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.lightBlue,
            brightness: Brightness.dark,
          ),
        ),
        child: ValueListenableBuilder<bool>(
          valueListenable: _paused,
          builder: (context, paused, _) => Scaffold(
            appBar: AppBar(
              forceMaterialTransparency: true,
              title: ListenableBuilder(
                listenable: _updateListNotifier,
                builder: (context, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Logs'),
                    if (paused || _newLogsMode) ...[
                      Text(
                        ' $_logsCount',
                        style: TextStyle(
                          fontSize: 12,
                          color: _filtered ? _filterColor : null,
                        ),
                      ),
                      if (_newLogsCount > 0)
                        Text(
                          ' +$_newLogsCount',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _pauseColor,
                          ),
                        ),
                    ] else
                      Text(
                        ' ${_logsCount + _newLogsCount}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _filtered ? _filterColor : null,
                        ),
                      ),
                    if (_filtered)
                      Text(
                        ' / ${widget.logStorage.count}',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
              actions: [
                Visibility(
                  // visible: false,
                  child: ListenableBuilder(
                    listenable: _updateListNotifier,
                    builder: (context, _) => IconButton(
                      onPressed: () {
                        _setFilter(
                          _filter == null
                              ? (log) => log.level >= LogLevels.error
                              : null,
                        );
                      },
                      icon: const Icon(Icons.filter_alt),
                      color: _filter == null ? null : _filterColor,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_rounded),
                ),
              ],
            ),
            body: SafeArea(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  switch (notification) {
                    case UserScrollNotification()
                        when !_paused.value &&
                            notification.direction == ScrollDirection.reverse:
                      SchedulerBinding.instance.addPostFrameCallback((_) {
                        _pause();
                      });
                  }

                  return false;
                },
                child: ListenableBuilder(
                  listenable: _updateListNotifier,
                  builder: (context, _) => Stack(
                    children: [
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          scrollbars: false,
                        ),
                        child: ScrollablePositionedList.builder(
                          itemScrollController: _itemScrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: _listPadding,
                          reverse: true,
                          itemCount: _logsCount,
                          itemBuilder: (_, index) {
                            final log = _logByIndex(index);
                            final item = Padding(
                              key: ObjectKey(log),
                              padding: const EdgeInsets.only(
                                bottom: _itemsSeparator,
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
            floatingActionButton: paused
                ? FloatingActionButton.small(
                    onPressed: _resume,
                    backgroundColor: _pauseColor,
                    foregroundColor: _onPauseColor,
                    child: const Icon(Icons.keyboard_double_arrow_down_rounded),
                  )
                : null,
          ),
        ),
      );
}

final class _Filter {
  final bool Function(Log log) filter;

  final logs = <Log>[];
  final newLogs = <Log>[];

  _Filter(this.filter);

  bool call(Log log) => filter(log);
}
