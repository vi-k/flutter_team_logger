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
import 'details/log_details.dart';
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

final Color _appBarColor = Colors.lightBlue.withValues(alpha: 0.05);
final Color _appBarPausedColor = Colors.white.withValues(alpha: 0.05);
const Color _pauseColor = Colors.deepOrange;
final Color _onPauseColor = Color.lerp(_pauseColor, Colors.white, 0.8)!;
const Color _filterColor = Colors.lightGreen;

const double _logsSeparator = 8;
const double _listHorizontalPadding = 6;
const EdgeInsets _listPadding = EdgeInsets.only(
  left: _listHorizontalPadding,
  right: _listHorizontalPadding,
  top: _logsSeparator,
);
const EdgeInsetsGeometry _filterPadding =
    EdgeInsets.symmetric(horizontal: _listHorizontalPadding, vertical: 4);

class Logs extends StatefulWidget {
  /// Screen title.
  final String title;

  /// Theme for rendering logs from `team_logger`.
  final LogMainTheme theme;

  /// Log storage from `team_logger`.
  final LogStorage logStorage;

  /// Duration of the scroll animation when a new log appears.
  ///
  /// In practice, when several logs appear at once, the duration decreases
  /// exponentially. As the queue of accumulated logs shrinks, the duration
  /// increases back up to [scrollToBottomDuration].
  final Duration scrollToBottomDuration;

  /// Curve of the scroll animation.
  final Curve scrollToBottomCurve;

  /// Callback fired on pause.
  final void Function()? onPaused;

  /// Callback fired on resume.
  final void Function()? onResumed;

  /// Callback fired on clear.
  final void Function()? onCleared;

  Logs({
    super.key,
    this.title = 'Logs',
    required this.theme,
    required LogStorage logStorage,
    this.scrollToBottomDuration = const Duration(milliseconds: 300),
    this.scrollToBottomCurve = Curves.ease,
    this.onPaused,
    this.onResumed,
    this.onCleared,
  }) : logStorage = logStorage.reversed;

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
  /// Scroll animation in [ScrollablePositionedList].
  ///
  /// In practice there is no actual scrolling of logs. The scroll animation
  /// is achieved by resizing the incoming log item.
  late final _animationController = AnimationController(
    vsync: this,
    duration: widget.scrollToBottomDuration,
  );

  /// Attaches a curve to the scroll animation.
  late final animation =
      _animationController.drive(CurveTween(curve: widget.scrollToBottomCurve));

  /// Controller for managing scrolling in [ScrollablePositionedList].
  final itemScrollController = ItemScrollController();

  /// Notifier for log update notifications.
  Listenable get onLogsChanged => _onLogsChanged;
  final _onLogsChanged = Notifier();

  /// Pause flag.
  ValueListenable<bool> get paused => _pausedNotifier;
  final _pausedNotifier = ValueNotifier<bool>(false);

  // AppBar color.
  ValueListenable<Color> get appBarColor => _appBarColorNotifier;
  final _appBarColorNotifier = ValueNotifier<Color>(_appBarColor);

  // Filter visibility flag.
  ValueListenable<bool> get filterIsVisible => _filterIsVisibleNotifier;
  final _filterIsVisibleNotifier = ValueNotifier<bool>(false);

  /// Logs.
  ///
  /// We keep our own list of logs, because logs in [LogStorage] can be
  /// removed.
  ///
  /// We track changes in [LogStorage] via [LogStorage.onChanged]. While
  /// paused, the list is left unchanged: new logs accumulate in [_newLogs],
  /// removed ones in [_removedLogs].
  final _logs = <Log>[];

  /// New logs.
  ///
  /// All new logs accumulate in this list and are gradually drained from
  /// it in [_startAddingAnimation]. While paused, they are not drained,
  /// only accumulated.
  final _newLogs = <Log>[];

  /// New-logs mode.
  ///
  /// When a large number of logs arrive at once, the AppBar shows a count
  /// of new logs like "987 +13", so the user can see that logs have
  /// arrived even though they have not appeared yet.
  ///
  /// Normally, when logs appear one at a time or in small numbers, this
  /// mode does not switch on, and the AppBar shows the combined total of
  /// current and new logs right away: "1000".
  bool _newLogsMode = false;

  bool get newLogsSeparately => paused.value || _newLogsMode;

  /// Logs pending removal, added while paused.
  ///
  /// Removed on resume in [resume].
  var _removedLogs = <Log>[];

  /// Subscription to log changes in [LogStorage].
  late StreamSubscription<void> _onChangedSubscription;

  /// Log filter.
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
    _pausedNotifier.dispose();
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
    _filterIsVisibleNotifier.value = !_filterIsVisibleNotifier.value;
  }

  void pause() {
    if (paused.value) return;

    _pausedNotifier.value = true;
    _appBarColorNotifier.value = _appBarPausedColor;
    widget.onPaused?.call();
  }

  void resume() {
    if (!paused.value) return;

    _removedLogs
      ..forEach(filter.removeLog)
      ..clear();
    _onLogsChanged.update();

    _pausedNotifier.value = false;
    _appBarColorNotifier.value = _appBarColor;
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
    if (paused.value) {
      resume();
    }
  }

  bool isLogRemoved(Log log) => _removedLogs.contains(log);

  void _logStorageChanged(LogStorageEvent event) {
    switch (event) {
      case LogStorageRemove(:final log):
        if (!filter.removeNewLog(log)) {
          if (paused.value) {
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
    if (_animationController.isAnimating || paused.value) {
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
            child: ValueListenableBuilder(
              valueListenable: paused,
              builder: (context, paused, _) => ValueListenableBuilder(
                valueListenable: appBarColor,
                builder: (context, appBarColor, _) => Scaffold(
                  appBar: AppBar(
                    backgroundColor: appBarColor,
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
      valueListenable: controller.paused,
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
                  '+${filter.newLogs.length}',
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
                ' of ${controller.widget.logStorage.count}',
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

    return ValueListenableBuilder(
      valueListenable: controller.filterIsVisible,
      builder: (context, filterIsVisible, _) => IconButton(
        onPressed: controller.toggleFilterVisibility,
        icon: const Icon(Icons.filter_alt),
        color: filter.isEnabled ? _filterColor : null,
        style: IconButton.styleFrom(
          backgroundColor:
              filterIsVisible ? _filterColor.withValues(alpha: 0.1) : null,
        ),
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
      ..filterIsVisible.addListener(_onFilterVisibilityChanged);
  }

  @override
  void dispose() {
    _controller.filterIsVisible.removeListener(_onFilterVisibilityChanged);
    super.dispose();
  }

  void _onFilterVisibilityChanged() {
    if (_controller.filterIsVisible.value) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: _controller.appBarColor,
        builder: (context, appBarColor, _) => Container(
          color: appBarColor,
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilterEdit(animation: _animation),
              _FilterResult(showFilterAnimation: _animation),
            ],
          ),
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
            shape: RoundedRectangleBorder(
              side: BorderSide(color: _filterColor.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: InkWell(
              onTap: controller.toggleFilterVisibility,
              overlayColor: WidgetStatePropertyAll(
                _filterColor.withValues(alpha: 0.05),
              ),
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
              when !controller.paused.value &&
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
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LogDetails(
                          log,
                          controller.widget.theme[log.level],
                        ),
                      ),
                    ),
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
