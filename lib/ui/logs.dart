import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:team_logger/team_logger.dart';

import '../utils/ansi.dart';

class Logs extends StatefulWidget {
  final LogTheme theme;
  final LogStorage logStorage;
  final Duration slidingDuration;
  final Duration blinkingDuration;

  const Logs({
    super.key,
    required this.theme,
    required this.logStorage,
    this.slidingDuration = const Duration(milliseconds: 200),
    this.blinkingDuration = const Duration(milliseconds: 500),
  });

  @override
  State<Logs> createState() => _LogsState();
}

class _LogsState extends State<Logs> {
  static const _listPadding = EdgeInsets.only(
    bottom: 8,
    left: 8,
    right: 8,
  );

  final _scrollController = ScrollController();
  final _logsSnapshot = ValueNotifier<List<Log>?>(null);
  final _logsCount = ValueNotifier<int>(0);
  late StreamSubscription<void> _subscription;
  int? _lastLogSeq;

  bool get _paused => _logsSnapshot.value != null;

  @override
  void initState() {
    super.initState();

    _subscribe();
  }

  @override
  void didUpdateWidget(covariant Logs oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.logStorage, widget.logStorage)) {
      _subscription.cancel();
      _logsSnapshot.value = null;
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.logStorage.onUpdate.listen((_) => _logsUpdated());
    _logsUpdated();
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

  void _resume() {
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

    final lastLogSeq = widget.logStorage[count - 1].sequenceNum;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _lastLogSeq = lastLogSeq;
      if (_scrollController.hasClients &&
          _scrollController.position.pixels != 0) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
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
                  // else if (notification.direction == ScrollDirection.idle &&
                  //     notification.metrics.pixels == 0 &&
                  //     _paused) {
                  //   _resume();
                  // }
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

                  return ListView.builder(
                    controller: _scrollController,
                    findChildIndexCallback: (key) {
                      final log = (key as ObjectKey).value! as Log;
                      final index = cachedLogs != null
                          ? cachedLogs.indexOf(log)
                          : widget.logStorage.indexOf(log);

                      return index == -1 ? null : count - index - 1;
                    },
                    padding: _listPadding,
                    itemCount: count,
                    itemBuilder: (_, index) {
                      final log = cachedLogs?[count - index - 1] ??
                          widget.logStorage[count - index - 1];
                      return LogItem(
                        key: ObjectKey(log),
                        isNew: switch (_lastLogSeq) {
                          null => true,
                          final seq => log.sequenceNum > seq,
                        },
                        widget.theme,
                        log,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
}

class LogItem extends StatefulWidget {
  static const _stackTracer = LogStackTrace(
    showIndexes: true,
  );
  static const _row = LogRow(children: [], maxLength: 1000000);

  static const double titleFontSize = 11;
  static const double messageFontSize = 13;
  static const double dataFontSize = 11;

  static const double boxTopOffset = 7;
  static const double boxBottomOffset = 4;
  static const double titleIndent = 6;
  static const double titleLeftPadding = 2;
  static const double titleRightPadding = 6;
  static const double titleHorizontalPadding = 2;
  static const double boxBorderRadius = 4;
  static const double sectionSeparator = 8;
  static const EdgeInsetsGeometry contentPadding =
      EdgeInsets.only(top: 8, bottom: 8, left: 6, right: 6);

  final LogTheme theme;
  final Log log;
  final Duration slidingDuration;
  final Duration blinkingDuration;

  const LogItem(
    this.theme,
    this.log, {
    bool isNew = false,
    Duration slidingDuration = const Duration(milliseconds: 200),
    Duration blinkingDuration = const Duration(milliseconds: 1000),
    super.key,
  })  : slidingDuration = isNew ? slidingDuration : Duration.zero,
        blinkingDuration = isNew ? blinkingDuration : Duration.zero;

  @override
  State<LogItem> createState() => _LogItemState();
}

class _LogItemState extends State<LogItem> with TickerProviderStateMixin {
  late final _slidingController = AnimationController(
    vsync: this,
    duration: widget.slidingDuration,
  );
  late final _blinkingController = AnimationController(
    vsync: this,
    duration: widget.blinkingDuration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.slidingDuration == Duration.zero) {
      _slidingController.value = 1;
    } else {
      _slidingController.forward();
    }

    if (widget.blinkingDuration == Duration.zero) {
      _blinkingController.value = 1;
    } else {
      _blinkingController.forward();
    }
  }

  @override
  void dispose() {
    _slidingController.dispose();
    _blinkingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme[widget.log.level];
    final color = ansiColor2Color(theme.normal.foregroundColor)!;

    final title = '${theme.levelNameStyle(' ${widget.log.shortLevelName} ')} '
        '${theme.timeStyle(LogTime.timeToString(widget.log.time))}'
        ' ${theme.pathStyle('[${widget.log.path}]')}'
        '${theme.common.traceIdStyle(widget.log.traceIds.map((e) => ' {$e}').join())}';

    final seqNum = theme.sequenceNumStyle('#${widget.log.sequenceNum}');

    var message = switch (widget.log.message) {
      '' => '',
      final message => theme.formatMessage(theme.formatValue(message)),
    };

    var data = <String>[];
    if (widget.log.hasData) {
      data = switch (widget.log.data) {
        final LoggableMultiData data => _multiDataToString(data, theme),
        _ => [Loggable.objectToString(widget.log.data, theme: theme)],
      };
    }

    final tags = theme.common
        .tagsStyle(theme.allTags(widget.log).map((e) => '#$e').join(' '));

    final errorTheme = theme.common.error;
    final error = switch (widget.log.error) {
      null => null,
      final error => '${errorTheme.sectionStyle(theme.common.errorTitle)}'
          '${errorTheme.styledColon}'
          ' ${errorTheme.formatMessage(errorTheme.formatValue(error.toString()))}',
    };

    String? stackTrace;
    if (widget.log.stackTrace case final s? when s != StackTrace.empty) {
      final stackTraceBox =
          LogItem._stackTracer(widget.log, theme, LogItem._row, null);
      stackTrace = stackTraceBox.lines.join('\n');
    }

    if (message.isNotEmpty &&
        (data.isNotEmpty || error != null || stackTrace != null)) {
      message = '$message${theme.styledColon}';
    }

    return DefaultTextStyle.merge(
      style: TextStyle(color: color),
      child: AnimatedBuilder(
        animation: _slidingController,
        builder: (context, child) => ClipRect(
          clipBehavior: Clip.antiAlias,
          child: Align(
            heightFactor: _slidingController.value,
            alignment: Alignment.bottomCenter,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: LogItem.boxTopOffset,
                    bottom: LogItem.boxBottomOffset,
                  ),
                  child: AnimatedBuilder(
                    animation: _blinkingController,
                    builder: (context, child) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          color,
                          Colors.transparent,
                          _blinkingController.value,
                        ),
                        border: Border.all(color: color),
                        borderRadius:
                            BorderRadius.circular(LogItem.boxBorderRadius),
                      ),
                      child: child,
                    ),
                    child: Padding(
                      padding: LogItem.contentPadding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: LogItem.sectionSeparator,
                        children: [
                          if (message.isNotEmpty)
                            RichText(
                              text: ansiText2TextSpan(
                                message,
                                defaulStyle: theme.normal,
                                fontSize: LogItem.messageFontSize,
                              ),
                            ),
                          for (final line in data)
                            RichText(
                              text: ansiText2TextSpan(
                                line,
                                defaulStyle: theme.normal,
                                fontSize: LogItem.dataFontSize,
                              ),
                            ),
                          if (error != null)
                            RichText(
                              text: ansiText2TextSpan(
                                error,
                                defaulStyle: widget.theme.error.normal,
                                fontSize: LogItem.dataFontSize,
                              ),
                            ),
                          if (stackTrace != null)
                            RichText(
                              text: ansiText2TextSpan(
                                stackTrace,
                                defaulStyle: theme.normal,
                                fontSize: LogItem.dataFontSize,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: LogItem.titleIndent,
                  right: LogItem.titleIndent,
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedBuilder(
                            animation: _blinkingController,
                            builder: (context, child) => ColoredBox(
                              color: Theme.of(context).colorScheme.surface,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: LogItem.titleLeftPadding,
                                  right: LogItem.titleHorizontalPadding,
                                ),
                                child: RichText(
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  text: ansiText2TextSpan(
                                    title,
                                    defaulStyle: theme.normal,
                                    fontSize: LogItem.titleFontSize,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: LogItem.titleHorizontalPadding,
                          ),
                          child: RichText(
                            text: ansiText2TextSpan(
                              seqNum,
                              defaulStyle: theme.normal,
                              fontSize: LogItem.titleFontSize,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: LogItem.titleIndent,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LogItem.titleHorizontalPadding,
                      ),
                      child: RichText(
                        text: ansiText2TextSpan(
                          tags,
                          defaulStyle: theme.normal,
                          fontSize: LogItem.titleFontSize,
                        ),
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
  }

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
