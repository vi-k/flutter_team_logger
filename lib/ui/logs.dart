import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:team_logger/team_logger.dart';

import '../utils/ansi.dart';

class Logs extends StatefulWidget {
  final LogTheme theme;
  final LogStorage logStorage;

  const Logs({
    super.key,
    required this.theme,
    required this.logStorage,
  });

  @override
  State<Logs> createState() => _LogsState();
}

class _LogsState extends State<Logs> {
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
                    _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
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

                      assert(index != -1);

                      return index == -1 ? null : count - index - 1;
                    },
                    padding: const EdgeInsets.only(
                      bottom: 4,
                      left: 4,
                      right: 4,
                    ),
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

  static const double titleFontSize = 10;
  static const double messageFontSize = 12;
  static const double dataFontSize = 10;

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
  final bool isNew;

  const LogItem(this.theme, this.log, {super.key, this.isNew = false});

  @override
  State<LogItem> createState() => _LogItemState();
}

class _LogItemState extends State<LogItem> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isNew) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final levelTheme = widget.theme[widget.log.level];
    final color = ansiColor2Color(levelTheme.normal.foregroundColor)!;

    final title =
        '${levelTheme.levelNameStyle(' ${widget.log.shortLevelName} ')} '
        '${levelTheme.timeStyle(LogTime.timeToString(widget.log.time))}'
        ' ${levelTheme.pathStyle('[${widget.log.path}]')}'
        '${levelTheme.common.traceIdStyle(widget.log.traceIds.map((e) => ' {$e}').join())}';
    final seqNum = levelTheme.sequenceNumStyle('#${widget.log.sequenceNum}');
    final message = switch (widget.log.message) {
      '' => '',
      final message =>
        levelTheme.formatMessage(levelTheme.formatValue(message)),
    };
    var data = <String>[];
    if (widget.log.hasData) {
      data = switch (widget.log.data) {
        final LoggableMultiData data => _multiDataToSting(data, levelTheme),
        _ => [Loggable.objectToString(widget.log.data, theme: levelTheme)],
      };
    }
    final tags = levelTheme.common
        .tagsStyle(levelTheme.allTags(widget.log).map((e) => '#$e').join(' '));
    final error = switch (widget.log.error) {
      null => null,
      final error =>
        '${widget.theme.error.sectionStyle('ERROR')}${widget.theme.error.styledColon}'
            ' ${widget.theme.error.formatMessage(widget.theme.error.formatValue(error.toString()))}',
    };

    String? stackTrace;
    if (widget.log.stackTrace case final s? when s != StackTrace.empty) {
      final stackTraceBox =
          LogItem._stackTracer(widget.log, levelTheme, LogItem._row, null);
      stackTrace = stackTraceBox.lines.join('\n');
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ClipRect(
        clipBehavior: Clip.antiAlias,
        child: Align(
          heightFactor: _controller.value,
          alignment: Alignment.bottomCenter,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: color),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: LogItem.boxTopOffset,
                    bottom: LogItem.boxBottomOffset,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: color),
                      borderRadius:
                          BorderRadius.circular(LogItem.boxBorderRadius),
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
                                defaulStyle: levelTheme.normal,
                                fontSize: LogItem.messageFontSize,
                              ),
                            ),
                          for (final line in data)
                            RichText(
                              text: ansiText2TextSpan(
                                line,
                                defaulStyle: levelTheme.normal,
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
                                defaulStyle: levelTheme.normal,
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
                          child: ColoredBox(
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
                                  defaulStyle: levelTheme.normal,
                                  fontSize: LogItem.titleFontSize,
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
                              defaulStyle: levelTheme.normal,
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
                          defaulStyle: levelTheme.normal,
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

  List<String> _multiDataToSting(LoggableMultiData obj, LogLevelTheme theme) =>
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
