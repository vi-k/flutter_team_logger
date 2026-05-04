import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_team_logger/utils/ansi.dart';
import 'package:team_logger/team_logger.dart';

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
    _logsCount.value = widget.logStorage.count;

    if (_scrollController.hasClients &&
        _scrollController.position.pixels != 0) {
      _scrollController.animateTo(
        -50,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
                  onPressed: () {
                    _paused ? _resume() : _pause();
                  },
                  icon: Icon(
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
                  if (notification.metrics.pixels > 0) {
                    if (!_paused) {
                      _pause();
                    }
                  } else {
                    if (_paused) {
                      _resume();
                    }
                  }
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

                  return ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(
                      bottom: 4,
                      left: 4,
                      right: 4,
                    ),
                    itemCount: count,
                    itemBuilder: (_, index) {
                      final log = cachedLogs?[count - index - 1] ??
                          widget.logStorage[count - index - 1];
                      return LogItem(widget.theme, log, key: ObjectKey(log));
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                  );
                },
              ),
            ),
          ),
        ),
      );
}

class LogItem extends StatelessWidget {
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

  const LogItem(this.theme, this.log, {super.key});

  @override
  Widget build(BuildContext context) {
    final levelTheme = theme[log.level];
    final color = ansiColor2Color(levelTheme.normal.foregroundColor)!;

    final title = '${levelTheme.levelNameStyle(' ${log.shortLevelName} ')} '
        '${levelTheme.timeStyle(LogTime.timeToString(log.time))}'
        ' ${levelTheme.pathStyle('[${log.path}]')}'
        '${levelTheme.common.traceIdStyle(log.traceIds.map((e) => ' {$e}').join())}';
    final seqNum = levelTheme.sequenceNumStyle('#${log.sequenceNum}');
    final message = switch (log.message) {
      '' => '',
      final message =>
        levelTheme.formatMessage(levelTheme.formatValue(message)),
    };
    final tags = levelTheme.common
        .tagsStyle(levelTheme.allTags(log).map((e) => '#$e').join(' '));
    final error = switch (log.error) {
      null => null,
      final error =>
        '${theme.error.sectionStyle('ERROR')}${theme.error.styledColon}'
            ' ${theme.error.formatMessage(theme.error.formatValue(error.toString()))}',
    };

    String? stackTrace;
    if (log.stackTrace case final s? when s != StackTrace.empty) {
      final stackTraceBox = _stackTracer(log, levelTheme, _row, null);
      stackTrace = stackTraceBox.lines.join('\n');
    }

    return DefaultTextStyle.merge(
      style: TextStyle(color: color),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: boxTopOffset,
              bottom: boxBottomOffset,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color),
                borderRadius: BorderRadius.circular(boxBorderRadius),
              ),
              child: Padding(
                padding: contentPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: sectionSeparator,
                  children: [
                    if (message.isNotEmpty)
                      RichText(
                        text: ansiText2TextSpan(
                          message,
                          defaulStyle: levelTheme.normal,
                          fontSize: messageFontSize,
                        ),
                      ),
                    if (log.hasData)
                      RichText(
                        text: ansiText2TextSpan(
                          Loggable.objectToString(
                            log.data,
                            theme: levelTheme,
                          ),
                          defaulStyle: levelTheme.normal,
                          fontSize: dataFontSize,
                        ),
                      ),
                    if (error != null)
                      RichText(
                        text: ansiText2TextSpan(
                          error,
                          defaulStyle: theme.error.normal,
                          fontSize: dataFontSize,
                        ),
                      ),
                    if (stackTrace != null)
                      RichText(
                        text: ansiText2TextSpan(
                          stackTrace,
                          defaulStyle: levelTheme.normal,
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
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: titleLeftPadding,
                          right: titleHorizontalPadding,
                        ),
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: ansiText2TextSpan(
                            title,
                            defaulStyle: levelTheme.normal,
                            fontSize: titleFontSize,
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
                      horizontal: titleHorizontalPadding,
                    ),
                    child: RichText(
                      text: ansiText2TextSpan(
                        seqNum,
                        defaulStyle: levelTheme.normal,
                        fontSize: titleFontSize,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            right: titleIndent,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: titleHorizontalPadding,
                ),
                child: RichText(
                  text: ansiText2TextSpan(
                    tags,
                    defaulStyle: levelTheme.normal,
                    fontSize: titleFontSize,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
