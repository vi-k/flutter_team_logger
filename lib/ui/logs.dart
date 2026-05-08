import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:team_logger/team_logger.dart';

import '../utils/ansi.dart';

class Logs extends StatefulWidget {
  final LogTheme theme;
  final LogStorage logStorage;
  final Duration minActiveLogDuration;
  final Duration scrollToBottomDuration;
  final void Function()? onPaused;
  final void Function()? onResumed;
  final void Function()? onCleared;
  final void Function(Log log)? onScrollStart;
  final void Function(Log log, Object? error, StackTrace? stackTrace)?
      onScrollEnd;
  final void Function()? onRemovedLogsCleared;

  const Logs({
    super.key,
    required this.theme,
    required this.logStorage,
    this.minActiveLogDuration = const Duration(seconds: 3),
    this.scrollToBottomDuration = const Duration(milliseconds: 1000),
    this.onPaused,
    this.onResumed,
    this.onCleared,
    this.onScrollStart,
    this.onScrollEnd,
    this.onRemovedLogsCleared,
  });

  @override
  State<Logs> createState() => _LogsState();
}

class _LogsState extends State<Logs> {
  static const _listPadding = EdgeInsets.symmetric(horizontal: 8);

  final _updateListNotifier = ValueNotifier<int>(0);
  final _paused = ValueNotifier<bool>(false);
  final _itemScrollController = ItemScrollController();
  Timer? _scrollTimer;
  final _removedLogs = <Log>[];
  late StreamSubscription<void> _onChangedSubscription;
  int? _lastLogThatWasScrolled;

  late final double _keepDimeDilation;

  @override
  void initState() {
    super.initState();

    _keepDimeDilation = timeDilation;
    // timeDilation = 5;

    _subscribe();
    _lastLogThatWasScrolled = widget.logStorage.lastOrNull?.sequenceNum;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (widget.logStorage.isNotEmpty) {
        _itemScrollController.jumpTo(
          index: widget.logStorage.count + 1,
          alignment: 1,
        );
      }
    });
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

  @override
  void dispose() {
    timeDilation = _keepDimeDilation;

    _updateListNotifier.dispose();
    _paused.dispose();
    _onChangedSubscription.cancel();
    super.dispose();
  }

  void _updateList() {
    _updateListNotifier.value++;
  }

  void _pause() {
    _scrollTimer?.cancel();
    _paused.value = true;
    widget.onPaused?.call();
  }

  void _resume() {
    _paused.value = false;
    _lastLogThatWasScrolled = widget.logStorage.lastOrNull?.sequenceNum;

    _cleanRemovedLogsIfNeed();
    _scrollToBottom(delay: Duration.zero, force: true, fast: true);
    widget.onResumed?.call();
  }

  void _clear() {
    widget.logStorage.clear();
    widget.onCleared?.call();
    if (_paused.value) {
      _resume();
    }
  }

  void _scrollToBottom({
    Duration delay = const Duration(milliseconds: 300),
    bool force = false,
    bool fast = false,
  }) {
    _scrollTimer?.cancel();
    _scrollTimer = Timer(delay, () async {
      final lastLog = widget.logStorage.lastOrNull;
      if (lastLog == null) return;

      final lastLogSeq = lastLog.sequenceNum;
      if (!force && _lastLogThatWasScrolled == lastLogSeq) {
        return;
      }
      _lastLogThatWasScrolled = lastLogSeq;

      // Scroll to anchor.
      final anchorIndex = _removedLogs.length + widget.logStorage.count + 1;
      widget.onScrollStart?.call(lastLog);
      try {
        await _itemScrollController.scrollTo(
          index: anchorIndex,
          duration: fast
              ? const Duration(milliseconds: 300)
              : widget.scrollToBottomDuration,
          alignment: 1,
        );
        widget.onScrollEnd?.call(lastLog, null, null);
      } on Object catch (error, stackTrace) {
        widget.onScrollEnd?.call(lastLog, error, stackTrace);
      }
    });
  }

  bool _cleanRemovedLogsIfNeed() {
    if (!_paused.value &&
        _removedLogs.length > widget.logStorage.maxCount ~/ 20) {
      _removedLogs.clear();
      widget.onRemovedLogsCleared?.call();
      _updateList();
      return true;
    }

    return false;
  }

  void _logsChanged(LogStorageEvent event) {
    _updateList();

    switch (event) {
      case LogStorageRemove():
        if (!_cleanRemovedLogsIfNeed()) {
          _removedLogs.add(event.log);
        }

      case LogStorageClear():
        _removedLogs.clear();

      case LogStorageAdd():
        if (!_paused.value) {
          _scrollToBottom();
        }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData.dark(),
        child: Scaffold(
          appBar: AppBar(
            title: ValueListenableBuilder<void>(
              valueListenable: _updateListNotifier,
              builder: (context, _, __) => Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text('Logs'),
                  Text(
                    ' ${_removedLogs.length + widget.logStorage.count} / ${widget.logStorage.maxCount}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                onPressed: _clear,
                icon: const Icon(Icons.delete_rounded),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _paused,
                builder: (context, paused, _) => IconButton(
                  color: paused ? Colors.amber : null,
                  onPressed: paused ? _resume : _pause,
                  icon: paused
                      ? const Icon(
                          Icons.play_circle_outline_rounded,
                          color: Colors.amber,
                        )
                      : const Icon(Icons.pause_circle_outline_rounded),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                switch (notification) {
                  case UserScrollNotification()
                      when !_paused.value &&
                          notification.direction == ScrollDirection.forward:
                    SchedulerBinding.instance.addPostFrameCallback((_) {
                      _pause();
                    });

                  case ScrollUpdateNotification()
                      when _paused.value &&
                          notification.metrics.pixels >=
                              notification.metrics.maxScrollExtent:
                    SchedulerBinding.instance.addPostFrameCallback((_) {
                      _resume();
                    });
                }

                return false;
              },
              child: ValueListenableBuilder<bool>(
                valueListenable: _paused,
                builder: (context, paused, _) => ValueListenableBuilder(
                  valueListenable: _updateListNotifier,
                  builder: (context, _, __) {
                    final removedCount = _removedLogs.length;
                    final totalCount = removedCount + widget.logStorage.count;

                    return Stack(
                      children: [
                        ScrollablePositionedList.builder(
                          itemScrollController: _itemScrollController,
                          padding: _listPadding,
                          itemCount: totalCount + 2,
                          itemBuilder: (_, index) {
                            if (index == totalCount) {
                              // Bottom padding.
                              return const ColoredBox(
                                // color: Colors.blueGrey,
                                color: Colors.transparent,
                                child: SizedBox(height: 10),
                              );
                            }
                            if (index > totalCount) {
                              // Anchor for scroll to bottom.
                              return const SizedBox.shrink();
                            }

                            if (index < removedCount) {
                              return const SizedBox.shrink();
                            }

                            final log = index < removedCount
                                ? _removedLogs[index]
                                : widget.logStorage[index - removedCount];

                            return LogItem(
                              widget.theme,
                              log,
                              state: switch (_lastLogThatWasScrolled) {
                                final lastLogSeq?
                                    when log.sequenceNum > lastLogSeq =>
                                  paused
                                      ? LogItemState.alwaysActive
                                      : LogItemState.temporarilyActive,
                                _ => LogItemState.inactive,
                              },
                              minActiveDuration: widget.minActiveLogDuration,
                              key: ObjectKey(log),
                            );
                          },
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: paused
                                      ? Colors.amber
                                      : Theme.of(context)
                                          .scaffoldBackgroundColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Positioned(
                        //   left: 0,
                        //   right: 0,
                        //   bottom: 0,
                        //   child: _RefreshIndicator(
                        //     scrollController: _itemScrollController,
                        //   ),
                        // ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
}

enum LogItemState {
  alwaysActive,
  temporarilyActive,
  inactive;

  bool get isActive => switch (this) {
        alwaysActive => true,
        temporarilyActive => true,
        inactive => false,
      };
}

class LogItem extends StatefulWidget {
  static const _row = LogRow(children: [], maxLength: 1000000);

  final LogTheme theme;
  final Log log;
  final Duration minActiveDuration;
  final LogItemState state;

  const LogItem(
    this.theme,
    this.log, {
    this.state = LogItemState.inactive,
    this.minActiveDuration = const Duration(seconds: 3),
    super.key,
  });

  @override
  State<LogItem> createState() => _LogItemState();
}

class _LogItemState extends State<LogItem> with TickerProviderStateMixin {
  static const double titleFontSize = 11;
  static const double messageFontSize = 13;
  static const double dataFontSize = 11;

  static const double boxTopOffset = 7;
  static const double boxBottomOffset = 6;
  static const double titleIndent = 6;
  static const EdgeInsetsGeometry titlePadding =
      EdgeInsets.symmetric(vertical: 1, horizontal: 1);
  static const double boxBorderRadius = 4;
  static const double sectionSeparator = 8;
  static const EdgeInsetsGeometry contentPadding =
      EdgeInsets.only(top: 12, bottom: 8, left: 6, right: 6);

  static const _stackTracerBuilder = LogStackTrace(showIndexes: true);

  late final _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  late final LogLevelTheme _theme;
  late final String _title;
  late final String _seqNum;
  late final String _message;
  late final List<String> _data;
  late final String? _error;
  late final String? _stackTrace;
  late final String _tags;
  late final Color _color;

  Timer? _timer;

  @override
  void initState() {
    super.initState();

    final log = widget.log;
    final theme = _theme = widget.theme[log.level];
    _color = ansiColor2Color(theme.normal.foregroundColor)!;
    _title = _buildTitle(log, theme);
    _seqNum = _buildSeqNum(log, theme);
    _data = _buildData(log, theme);
    _error = _buildError(log, theme);
    _stackTrace = _buildStackTrace(log, theme);
    _tags = _buildTags(log, theme);

    _message = switch (_buildMessage(log, theme)) {
      final message
          when message.isNotEmpty &&
              (_data.isNotEmpty || _error != null || _stackTrace != null) =>
        '$message${theme.styledColon}',
      final message => message,
    };

    if (widget.state.isActive) {
      _fadeController.value = 1;
      if (widget.state == LogItemState.temporarilyActive) {
        _timer = Timer(widget.minActiveDuration, () {
          _timer = null;
          _fadeController.reverse();
        });
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LogItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.state.isActive &&
        _fadeController.value == 1 &&
        _timer == null) {
      _fadeController.reverse();
    }
  }

  String _buildTitle(Log log, LogLevelTheme theme) =>
      '${'[${log.shortLevelName}]'} '
      '${theme.timeStyle(LogTime.timeToString(log.time))}'
      ' ${theme.pathStyle('[${log.path}]')}'
      '${theme.common.traceIdStyle(log.traceIds.map((e) => ' {$e}').join())}';

  String _buildSeqNum(Log log, LogLevelTheme theme) =>
      theme.sequenceNumStyle('#${log.sequenceNum}');

  String _buildMessage(Log log, LogLevelTheme theme) => log.message.isEmpty
      ? ''
      : theme.formatMessage(theme.formatValue(log.message));

  List<String> _buildData(Log log, LogLevelTheme theme) => !log.hasData
      ? []
      : switch (log.data) {
          final LoggableMultiData data => _multiDataToString(data, theme),
          _ => [Loggable.objectToString(log.data, theme: theme)],
        };

  String? _buildError(Log log, LogLevelTheme theme) {
    final errorTheme = theme.common.error;

    return switch (log.error) {
      null => null,
      final error => '${errorTheme.sectionStyle(theme.common.errorTitle)}'
          '${errorTheme.styledColon}'
          ' ${errorTheme.formatMessage(errorTheme.formatValue('$error'))}',
    };
  }

  String? _buildStackTrace(Log log, LogLevelTheme theme) {
    final stackTraceBox =
        _stackTracerBuilder(widget.log, theme, LogItem._row, null);

    return stackTraceBox.lines.isEmpty //
        ? null
        : stackTraceBox.lines.join('\n');
  }

  String _buildTags(Log log, LogLevelTheme theme) => theme.common
      .tagsStyle(theme.allTags(widget.log).map((e) => '#$e').join(' '));

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
        style: TextStyle(color: _color),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: boxTopOffset,
                bottom: boxBottomOffset,
              ),
              child: AnimatedBuilder(
                animation: _fadeController,
                builder: (context, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      Colors.transparent,
                      _color.withValues(alpha: 0.2),
                      _fadeController.value,
                    ),
                    border: Border.all(color: _color),
                    borderRadius: BorderRadius.circular(boxBorderRadius),
                  ),
                  child: child,
                ),
                child: Padding(
                  padding: contentPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: sectionSeparator,
                    children: [
                      if (_message.isNotEmpty)
                        RichText(
                          maxLines: 3,
                          overflow: TextOverflow.fade,
                          text: ansiText2TextSpan(
                            _message,
                            defaulStyle: _theme.normal,
                            fontSize: messageFontSize,
                          ),
                        ),
                      for (final line in _data)
                        RichText(
                          maxLines: 8,
                          overflow: TextOverflow.fade,
                          text: ansiText2TextSpan(
                            line,
                            defaulStyle: _theme.normal,
                            fontSize: dataFontSize,
                          ),
                        ),
                      if (_error case final error?)
                        RichText(
                          maxLines: 3,
                          overflow: TextOverflow.fade,
                          text: ansiText2TextSpan(
                            error,
                            defaulStyle: widget.theme.error.normal,
                            fontSize: dataFontSize,
                          ),
                        ),
                      if (_stackTrace case final stackTrace?)
                        RichText(
                          maxLines: 8,
                          overflow: TextOverflow.fade,
                          text: ansiText2TextSpan(
                            stackTrace,
                            defaulStyle: _theme.normal,
                            fontSize: dataFontSize,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: titleIndent,
              right: titleIndent,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedBuilder(
                        animation: _fadeController,
                        builder: (context, child) => Container(
                          padding: titlePadding,
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: ansiText2TextSpan(
                              _title,
                              defaulStyle: _theme.normal,
                              fontSize: titleFontSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Padding(
                      padding: titlePadding,
                      child: RichText(
                        text: ansiText2TextSpan(
                          _seqNum,
                          defaulStyle: _theme.normal,
                          fontSize: titleFontSize,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_tags.isNotEmpty)
              Positioned(
                bottom: 0,
                right: titleIndent,
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  padding: titlePadding,
                  child: RichText(
                    text: ansiText2TextSpan(
                      _tags,
                      defaulStyle: _theme.normal,
                      fontSize: titleFontSize,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  List<String> _multiDataToString(LoggableMultiData obj, LogLevelTheme theme) =>
      obj.data.entries.map((e) {
        final value = Loggable.objectToString(
          e.value,
          theme: theme,
          config: obj.config,
        );

        return switch (e.key) {
          '' => value,
          final key => '${theme.sectionStyle(key)}${theme.styledColon} $value',
        };
      }).toList();
}
