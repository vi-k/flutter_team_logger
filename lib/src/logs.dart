import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_team_logger/src/utils/stream_notifier_ext.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:team_logger/team_logger.dart';

import 'ansi_utils.dart';
import 'filter/filter.dart';
import 'log_item.dart';
import 'notifier.dart';
import 'uikit/chip.dart' as ui;

final ThemeData _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.lightBlue,
    brightness: Brightness.dark,
  ),
);
const double _logsSeparator = 8;
const double _listHorizontalPadding = 6;
const EdgeInsets _listPadding = EdgeInsets.only(
  left: _listHorizontalPadding,
  right: _listHorizontalPadding,
  top: _logsSeparator,
);
const EdgeInsetsGeometry _filterPadding =
    EdgeInsets.symmetric(horizontal: _listHorizontalPadding, vertical: 4);
const Color _pauseColor = Colors.deepOrangeAccent;
const Color _onPauseColor = Colors.black;
const Color _filterColor = Colors.lightGreen;

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

  static Filter filterOf(
    BuildContext context, {
    bool listen = true,
  }) =>
      _FilterInheritedWidget.of(context, listen: listen).filter;
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

  /// Флаг паузы.
  bool get paused => _paused.value;
  ValueListenable<bool> get onPauseChanged => _paused;
  final _paused = ValueNotifier<bool>(false);

  bool get filterIsVisible => _filterIsVisible.value;
  ValueListenable<bool> get onFilterVisibilityChanged => _filterIsVisible;
  final _filterIsVisible = ValueNotifier<bool>(false);

  /// Логи.
  ///
  /// Храним свой собственный список логов, так как логи в [LogStorage] могут
  /// быть удалены.
  ///
  /// Следим за изменениями в [LogStorage] через [LogStorage.onChanged]. На
  /// время паузы не изменяем список: новые логи накапливаем в [_newLogs],
  /// удаляемые - в [_removedLogs].
  final _logs = <Log>[];

  /// Новые логи.
  ///
  /// Все новые логи накапливаются в этом списке и постепенно изымаются из
  /// него в [_startAddingAnimation]. Во время паузы не изымаются, только
  /// накапливаются.
  final _newLogs = <Log>[];

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

  bool get newLogsSeparately => paused || _newLogsMode;

  /// Удаляемые логи, добавленные во время паузы
  ///
  /// Удаляем при возобновлении в [resume].
  var _removedLogs = <Log>[];

  /// Подписка на изменение логов в [LogStorage].
  late StreamSubscription<void> _onChangedSubscription;

  /// Фильтр логов.
  late final filter = Filter(
    logs: () => _logs,
    newLogs: () => _newLogs,
  );

  @override
  void initState() {
    super.initState();

    _logs.addAll(widget.logStorage.snapshot());
    _subscribeToLogStorage();

    _onLogsChanged
      ..addListener(_handleLogsChanged)
      ..update();

    _animationController.addStatusListener(_animationStatusListener);

    filter.addListener(_filterChanged);
  }

  @override
  void dispose() {
    _onLogsChanged.dispose();
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
    _startAddingAnimation();
  }

  void toggleFilterVisibility() {
    _filterIsVisible.value = !_filterIsVisible.value;
  }

  void pause() {
    if (paused) return;

    _paused.value = true;
    widget.onPaused?.call();
  }

  void resume() {
    if (!paused) return;

    _removedLogs
      ..forEach(filter.removeLog)
      ..clear();
    _onLogsChanged.update();

    _paused.value = false;
    widget.onResumed?.call();
    if (filter.logs.isNotEmpty) {
      itemScrollController.scrollTo(
        index: 0,
        duration: widget.scrollToBottomDuration,
        curve: widget.scrollToBottomCurve,
      );
    }
    _newLogsMode = true;
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
    switch (event) {
      case LogStorageRemove(:final log):
        if (!filter.removeNewLog(log)) {
          if (paused) {
            _removedLogs.add(log);
            filter.update();
          } else {
            filter.removeLog(log);
          }
        }

      case LogStorageClear():
        _logs.clear();
        _newLogs.clear();
        _newLogsMode = false;
        _removedLogs = [];
        filter.update();

      case LogStorageAdd(:final log):
        if (filter.addNewLog(log)) {
          _startAddingAnimation();
        }
    }

    _onLogsChanged.update();
  }

  void _handleLogsChanged() {
    // Adjust values depending on logs count
    final newLogsCount = filter.newLogs.length;
    final normalDuration = widget.scrollToBottomDuration.inMilliseconds;
    final duration = newLogsCount == 0
        ? normalDuration
        : (normalDuration / math.exp((newLogsCount - 1) / 5)).round();
    _animationController.duration = Duration(milliseconds: duration);

    if (newLogsCount >= 10) {
      _newLogsMode = true;
    } else if (newLogsCount == 0) {
      _newLogsMode = false;
    }
  }

  void _startAddingAnimation() {
    if (_animationController.isAnimating || paused) {
      return;
    }

    if (filter.moveNextNewLogToLogs()) {
      _onLogsChanged.update();
      _animationController
        ..reset()
        ..forward();
    }
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
        child: _FilterInheritedWidget(
          filter: filter,
          child: Theme(
            data: _theme,
            child: ValueListenableBuilder<bool>(
              valueListenable: onPauseChanged,
              builder: (context, paused, _) => Scaffold(
                appBar: AppBar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.05),
                  surfaceTintColor: Colors.transparent,
                  title: const _LogsAppBarTitle(),
                  actions: const [
                    _FilterButton(),
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

class _FilterInheritedWidget extends InheritedNotifier {
  final Filter filter;

  _FilterInheritedWidget({
    required this.filter,
    required super.child,
  }) : super(notifier: filter.asListenable());

  static _FilterInheritedWidget of(
    BuildContext context, {
    required bool listen,
  }) =>
      maybeOf(context, listen: listen) ??
      (throw Exception('$_FilterInheritedWidget not found in the context.'));

  static _FilterInheritedWidget? maybeOf(
    BuildContext context, {
    required bool listen,
  }) =>
      listen
          ? context.dependOnInheritedWidgetOfExactType<_FilterInheritedWidget>()
          : context.getInheritedWidgetOfExactType<_FilterInheritedWidget>();
}

class _LogsAppBarTitle extends StatelessWidget {
  const _LogsAppBarTitle({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);
    final filter = Logs.filterOf(context);

    return ValueListenableBuilder<bool>(
      valueListenable: controller.onPauseChanged,
      builder: (context, paused, _) => ListenableBuilder(
        listenable: controller.onLogsChanged,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(controller.widget.title),
            if (controller.newLogsSeparately) ...[
              Text(
                ' ${filter.logs.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: controller.filter.isEnabled ? _filterColor : null,
                ),
              ),
              if (filter.newLogs.isNotEmpty)
                Text(
                  ' +${filter.newLogs.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _pauseColor,
                  ),
                ),
            ] else
              Text(
                ' ${filter.logs.length + filter.newLogs.length}',
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
    final filter = Logs.filterOf(context);

    return IconButton(
      onPressed: controller.toggleFilterVisibility,
      icon: const Icon(Icons.filter_alt),
      color: filter.isEnabled ? _filterColor : null,
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

class _FilterViewState extends State<_FilterView>
    with SingleTickerProviderStateMixin {
  late final LogsState _controller;

  late final _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  late final _animation =
      _animationController.drive(CurveTween(curve: Curves.ease));

  @override
  void initState() {
    super.initState();

    _controller = Logs.of(context)
      ..onFilterVisibilityChanged.addListener(_onFilterVisibilityChanged);
  }

  @override
  void dispose() {
    _controller.onFilterVisibilityChanged
        .removeListener(_onFilterVisibilityChanged);
    super.dispose();
  }

  void _onFilterVisibilityChanged() {
    if (_controller.filterIsVisible) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterEdit(animation: _animation),
            _FilterResult(showFilterAnimation: _animation),
          ],
        ),
      );
}

class _FilterEdit extends StatefulWidget {
  final Animation<double> animation;

  const _FilterEdit({
    required this.animation,
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  State<_FilterEdit> createState() => _FilterEditState();
}

class _FilterEditState extends State<_FilterEdit> {
  static const double _itemsSeparator = 2;

  late final LogsState _controller;
  late final Color _levelColor;
  late final Color _loggerColor;
  late final Color _traceIdColor;
  late final Color _tagsColor;

  @override
  void initState() {
    super.initState();

    _controller = Logs.of(context);

    _levelColor = ansiColor2Color(
          _controller.widget.theme.debug.data.normal.foregroundColor,
        ) ??
        _filterColor;
    _loggerColor = ansiColor2Color(
          _controller.widget.theme.info.data.pathStyle.foregroundColor,
        ) ??
        _filterColor;
    _traceIdColor = ansiColor2Color(
          _controller.widget.theme.traceIdStyle.foregroundColor,
        ) ??
        _filterColor;
    _tagsColor = ansiColor2Color(
          _controller.widget.theme.tagsStyle.foregroundColor,
        ) ??
        _filterColor;
  }

  Widget _buildLevelChip(
    int level, {
    String keyPrefix = '',
    bool showCount = true,
  }) {
    final name = LogLevels.name(level);
    final color = ansiColor2Color(
          _controller.widget.theme[level].data.normal.foregroundColor,
        ) ??
        _filterColor;
    final filter = _controller.filter;

    return ui.FilterChip(
      key: Key('${keyPrefix}level:$name'),
      color: color,
      inactiveBackgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: name,
      logsCount: showCount ? filter.availableLevels[level] : null,
      onPressed: () {
        filter.orLevel(level);
      },
      onLongPress: () {
        filter.andLevel(level);
      },
    );
  }

  Widget _buildLoggerChip(
    String logger, {
    String keyPrefix = '',
    bool showCount = true,
  }) {
    final filter = _controller.filter;

    return ui.FilterChip(
      key: Key('${keyPrefix}logger:$logger'),
      color: _loggerColor,
      inactiveBackgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: logger,
      logsCount: showCount ? filter.availableLoggers[logger] : null,
      onPressed: () {
        filter.orLogger(logger);
      },
      onLongPress: () {
        filter.andLogger(logger);
      },
    );
  }

  Widget _buildTraceIdChip(
    String? group, {
    String keyPrefix = '',
    bool showCount = true,
  }) {
    final filter = _controller.filter;

    return ui.FilterChip(
      key: Key(
        group == null
            ? '${keyPrefix}global_traceId'
            : '${keyPrefix}traceId:$group',
      ),
      color: _traceIdColor,
      inactiveBackgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: group ?? '<global>',
      logsCount: showCount ? filter.availableTraceIds[group] : null,
      onPressed: () {
        filter.orTraceId(group);
      },
      onLongPress: () {
        filter.andTraceId(group);
      },
    );
  }

  Widget _buildTagChip(
    String tag, {
    String keyPrefix = '',
    bool showCount = true,
  }) {
    final filter = _controller.filter;

    return ui.FilterChip(
      key: Key('${keyPrefix}tag:$tag'),
      color: _tagsColor,
      inactiveBackgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: tag,
      logsCount: showCount ? filter.availableTags[tag] : null,
      onPressed: () {
        filter.orTag(tag);
      },
      onLongPress: () {
        filter.andTag(tag);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = Logs.filterOf(context);

    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) => ClipRect(
        child: Align(
          heightFactor: widget.animation.value,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          left: _itemsSeparator,
          right: _itemsSeparator,
          bottom: _itemsSeparator,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterEditRow(
              label: 'level',
              color: _levelColor,
              children:
                  filter.availableLevels.keys.map(_buildLevelChip).toList(),
            ),
            _FilterEditRow(
              label: 'logger',
              color: _loggerColor,
              children:
                  filter.availableLoggers.keys.map(_buildLoggerChip).toList(),
            ),
            _FilterEditRow(
              label: 'trace',
              color: _traceIdColor,
              children:
                  filter.availableTraceIds.keys.map(_buildTraceIdChip).toList(),
            ),
            _FilterEditRow(
              label: 'tags',
              color: _tagsColor,
              children: filter.availableTags.keys.map(_buildTagChip).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterEditRow extends StatelessWidget {
  static const double _itemsSeparator = 2;

  final Color color;
  final String label;
  final List<Widget> children;

  const _FilterEditRow({
    // ignore: unused_element_parameter
    super.key,
    required this.color,
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => children.isEmpty
      ? const SizedBox.shrink()
      : Row(
          children: [
            _Starter(
              label: label,
              color: color,
              padding: const EdgeInsets.only(right: _itemsSeparator),
            ),
            Expanded(
              child: Wrap(
                spacing: _itemsSeparator,
                runSpacing: _itemsSeparator,
                children: children,
              ),
            ),
          ],
        );
}

class _FilterResult extends StatefulWidget {
  final Animation<double> showFilterAnimation;

  const _FilterResult({
    required this.showFilterAnimation,
  });

  @override
  State<_FilterResult> createState() => _FilterResultState();
}

class _FilterResultState extends State<_FilterResult>
    with SingleTickerProviderStateMixin {
  late final _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  late final _animation =
      _animationController.drive(CurveTween(curve: Curves.ease));

  late Filter _filter;
  late bool _isFilterEnabled;

  @override
  void initState() {
    super.initState();

    _filter = Logs.filterOf(context, listen: false)
      ..addListener(_onFilterChanged);
    _isFilterEnabled = _filter.isEnabled;
  }

  @override
  void dispose() {
    _filter.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onFilterChanged() {
    if (_filter.isEnabled != _isFilterEnabled) {
      _isFilterEnabled = _filter.isEnabled;
      if (_isFilterEnabled) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);
    final filter = Logs.filterOf(context);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: _animation.value,
          child: Material(
            clipBehavior: Clip.antiAlias,
            color: _filterColor.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: _filterColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: InkWell(
              onTap: controller.toggleFilterVisibility,
              focusColor: _filterColor.withValues(alpha: 0.2),
              highlightColor: _filterColor.withValues(alpha: 0.3),
              splashColor: _filterColor.withValues(alpha: 0.4),
              hoverColor: _filterColor.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: _filterPadding,
                      child: RichText(
                        text: ansiText2TextSpan(
                          filter
                              .toColorizedString(controller.widget.theme.info),
                          defaulStyle: controller.widget.theme.info.data.normal,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: widget.showFilterAnimation,
                    builder: (context, child) => ClipRect(
                      child: Align(
                        widthFactor: widget.showFilterAnimation.value,
                        heightFactor: widget.showFilterAnimation.value,
                        alignment: Alignment.centerLeft,
                        child: child,
                      ),
                    ),
                    child: IconButton(
                      onPressed: filter.undo,
                      iconSize: 16,
                      icon: const Icon(Icons.backspace),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogsList extends StatelessWidget {
  const _LogsList({
    // ignore: unused_element_parameter
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Logs.of(context);
    final filter = Logs.filterOf(context);

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
      child: Stack(
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
              itemCount: filter.logs.length,
              itemBuilder: (_, index) {
                final log = filter.logs[index];
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
        child: Text(
          '$label:',
          style: TextStyle(
            fontSize: 9,
            color: color,
          ),
        ),
      );
}
