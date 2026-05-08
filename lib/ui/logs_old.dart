import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:team_logger/team_logger.dart';

import '../utils/ansi.dart';

class LogsOld extends StatefulWidget {
  final LogTheme theme;
  final LogStorage logStorage;
  final Duration slidingDuration;
  final Duration blinkingDuration;

  const LogsOld({
    super.key,
    required this.theme,
    required this.logStorage,
    this.slidingDuration = const Duration(milliseconds: 200),
    this.blinkingDuration = const Duration(milliseconds: 500),
  });

  @override
  State<LogsOld> createState() => _LogsOldState();
}

class _LogsOldState extends State<LogsOld> {
  static const _listPadding = EdgeInsets.only(bottom: 4, left: 7, right: 7);

  final _scrollController = ScrollController();
  final _logsSnapshot = ValueNotifier<List<Log>?>(null);
  final _logsCount = ValueNotifier<int>(0);
  final _stopwatch = Stopwatch();
  late StreamSubscription<void> _subscription;
  int? _lastLogSeq;

  bool get _paused => _logsSnapshot.value != null;

  @override
  void initState() {
    super.initState();

    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      _stopwatch
        ..stop()
        ..reset();
    });

    _subscribe();
    if (widget.logStorage.isNotEmpty) {
      _lastLogSeq = widget.logStorage[0].sequenceNum;
    }
    _logsUpdated();
  }

  @override
  void didUpdateWidget(covariant LogsOld oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.logStorage, widget.logStorage)) {
      _subscription.cancel();
      _logsSnapshot.value = null;
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.logStorage.onChanged.listen((_) => _logsUpdated());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _subscription.cancel();
    _logsSnapshot.dispose();
    super.dispose();
  }

  void _pause() {
    final snapshot = widget.logStorage.snapshot();
    _logsSnapshot.value = snapshot;
    _logsCount.value = snapshot.length;
  }

  Future<void> _resume() async {
    if (_scrollController.hasClients && _scrollController.position.pixels > 0) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    if (!mounted) return;

    _logsSnapshot.value = null;
    _logsUpdated();
  }

  void _logsUpdated() {
    if (_paused) {
      return;
    }

    _logsSnapshot.value = [];
    _logsSnapshot.value = null;
    final count = widget.logStorage.count;
    _logsCount.value = count;
    if (count == 0) {
      return;
    }

    final lastLogSeq = widget.logStorage[0].sequenceNum;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _lastLogSeq = lastLogSeq;
    });
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData.dark(),
        child: Scaffold(
          appBar: AppBar(
            title: ValueListenableBuilder(
              valueListenable: _logsCount,
              builder: (_, count, __) => Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text('Logs'),
                  Text(
                    ' ($count / ${widget.logStorage.maxCount})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                onPressed: () {
                  widget.logStorage.clear();
                  if (_paused) {
                    _resume();
                  }
                },
                icon: const Icon(Icons.delete_rounded),
              ),
              ValueListenableBuilder<List<Log>?>(
                valueListenable: _logsSnapshot,
                builder: (context, cachedLogs, __) => IconButton(
                  color: _paused ? Colors.amber : null,
                  onPressed: () {
                    _paused ? _resume() : _pause();
                  },
                  icon: Icon(
                    color: _paused ? Colors.amber : null,
                    _paused
                        ? Icons.play_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification) {
                  if (notification.direction == ScrollDirection.reverse &&
                      !_paused) {
                    _pause();
                  }
                }

                if (notification is ScrollUpdateNotification &&
                    notification.metrics.pixels < -120 &&
                    _paused) {
                  _resume();
                }

                return false;
              },
              child: ValueListenableBuilder<List<Log>?>(
                valueListenable: _logsSnapshot,
                builder: (context, cachedLogs, _) {
                  final count = cachedLogs?.length ?? widget.logStorage.count;
                  if (count == 0) {
                    return const Center(child: Text('No logs'));
                  }

                  return ColoredBox(
                    color: _paused ? Colors.amber : Colors.transparent,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: _paused ? 1 : 0,
                        right: 1,
                        left: 1,
                        bottom: 1,
                      ),
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: _listPadding,
                          reverse: true,
                          physics: const BouncingScrollPhysics(),
                          findChildIndexCallback: (key) {
                            final log = (key as ObjectKey).value! as Log;
                            final index = cachedLogs != null
                                ? cachedLogs.indexOf(log)
                                : widget.logStorage.indexOf(log);
                            if (index == -1) return null;

                            assert(
                              identical(
                                cachedLogs?[index] ?? widget.logStorage[index],
                                log,
                              ),
                            );

                            return index;
                          },
                          itemBuilder: (_, index) {
                            if (!_stopwatch.isRunning) {
                              _stopwatch.start();
                            }

                            if (index >= count ||
                                _stopwatch.elapsed >
                                    const Duration(milliseconds: 300)) {
                              return null;
                            }

                            final log =
                                cachedLogs?[index] ?? widget.logStorage[index];
                            return LogItemOld(
                              key: ObjectKey(log),
                              isNew: !_paused &&
                                  switch (_lastLogSeq) {
                                    null => true,
                                    final seq => log.sequenceNum > seq,
                                  },
                              widget.theme,
                              log,
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
}

class LogItemOld extends StatefulWidget {
  static const _row = LogRow(children: [], maxLength: 1000000);

  final LogTheme theme;
  final Log log;
  final Duration slidingDuration;
  final Duration blinkingDuration;

  const LogItemOld(
    this.theme,
    this.log, {
    bool isNew = false,
    Duration slidingDuration = const Duration(milliseconds: 200),
    Duration blinkingDuration = const Duration(seconds: 5),
    super.key,
  })  : slidingDuration = isNew ? slidingDuration : Duration.zero,
        blinkingDuration = isNew ? blinkingDuration : Duration.zero;

  @override
  State<LogItemOld> createState() => _LogItemOldState();
}

class _LogItemOldState extends State<LogItemOld> with TickerProviderStateMixin {
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

  late final _slidingController = AnimationController(vsync: this);
  late final _blinkingController = AnimationController(vsync: this);

  late final LogLevelTheme _theme;
  late final String _title;
  late final String _seqNum;
  late final String _message;
  late final List<String> _data;
  late final String? _error;
  late final String? _stackTrace;
  late final String _tags;
  late final Color _color;

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

    if (widget.slidingDuration != Duration.zero) {
      _slidingController
        ..duration = widget.slidingDuration
        ..value = 1
        ..reverse();
    }

    if (widget.blinkingDuration != Duration.zero) {
      _blinkingController
        ..duration = widget.blinkingDuration
        ..value = 1
        ..reverse();
    }
  }

  @override
  void dispose() {
    _slidingController.dispose();
    _blinkingController.dispose();
    super.dispose();
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
        _stackTracerBuilder(widget.log, theme, LogItemOld._row, null);

    return stackTraceBox.lines.isEmpty //
        ? null
        : stackTraceBox.lines.join('\n');
  }

  String _buildTags(Log log, LogLevelTheme theme) => theme.common
      .tagsStyle(theme.allTags(widget.log).map((e) => '#$e').join(' '));

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
        style: TextStyle(color: _color),
        child: AnimatedBuilder(
          animation: _slidingController,
          builder: (context, child) => ClipRect(
            clipBehavior: Clip.antiAlias,
            child: Align(
              heightFactor: 1.0 - _slidingController.value,
              alignment: Alignment.topCenter,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: boxTopOffset,
                      bottom: boxBottomOffset,
                    ),
                    child: AnimatedBuilder(
                      animation: _blinkingController,
                      builder: (context, child) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: _blinkingController.value <= 0.05
                              ? Color.lerp(
                                  Colors.transparent,
                                  _color.withAlpha(48),
                                  _blinkingController.value * 20,
                                )
                              : _color.withAlpha(48),
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
                              animation: _blinkingController,
                              builder: (context, child) => Container(
                                padding: titlePadding,
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
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
            ),
          ),
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
