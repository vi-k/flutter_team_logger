import 'package:ansi_escape_codes/style.dart' as ansi;
import 'package:flutter/material.dart';
import 'package:team_logger/team_logger.dart';

import 'ansi_utils.dart';
import 'uikit/border_container.dart';

class LogItem extends StatefulWidget {
  static const _row = LogRow(children: [], maxLength: 10000);

  final Log log;
  final LogTheme theme;
  final bool removed;
  final void Function()? onTap;
  final void Function()? onTapDown;
  final void Function()? onLongPress;

  const LogItem(
    this.log,
    this.theme, {
    this.removed = false,
    this.onTap,
    this.onTapDown,
    this.onLongPress,
    super.key,
  });

  @override
  State<LogItem> createState() => _LogItemState();
}

class _LogItemState extends State<LogItem> {
  static const double _messageFontSize = 12;
  static const double _dataFontSize = 11;

  static const double _borderRadius = 4;
  static const double _sectionSeparator = 6;
  static const double _itemsSeparator = 3;
  static const double _contentLeftPadding = 6;
  static const double _contentRightPadding = 6;
  static const EdgeInsetsGeometry _messagePadding =
      EdgeInsets.only(left: 3, right: 3, top: 3, bottom: 3);

  static const _stackTracerBuilder = LogStackTrace(showIndexes: true);

  late final Widget? _message;
  late final List<Widget> _data;
  late final Widget? _error;
  late final Widget? _stackTrace;
  late final Color _color;
  late Color _borderColor;
  late final Color _messageBorderColor;
  late final Color _messageBackgroundColor;

  @override
  void initState() {
    super.initState();

    _color = ansiColor2Color(widget.theme.data.normal.foregroundColor)!;
    _messageBorderColor = _color.withValues(alpha: borderColorAlpha);
    _messageBackgroundColor = _color.withValues(alpha: 0.1);

    _message = _buildMessage();
    _data = _buildData();
    _error = _buildError();
    _stackTrace = _buildStackTrace();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    _borderColor = Color.lerp(backgroundColor, _color, borderColorAlpha)!;
  }

  Widget? _buildMessage() {
    final log = widget.log;
    final theme = widget.theme;

    return log.message.isEmpty
        ? null
        : RichText(
            maxLines: 3,
            overflow: TextOverflow.fade,
            text: ansiText2TextSpan(
              theme.formatMessage(
                theme.formatValue(
                  log.message,
                  escapeAnsiCodes: LoggableConfig.defaultEscapeAnsiCodes,
                ),
                escapeAnsiCodes: false,
              ),
              defaulStyle: theme.data.normal,
              fontSize: _messageFontSize,
            ),
          );
  }

  List<Widget> _buildData() {
    final log = widget.log;
    final theme = widget.theme;

    return !log.hasData
        ? []
        : switch (log.data) {
            final LoggableMultiData data => data.data.entries.map((e) {
                final value = Loggable.objectToString(
                  e.value,
                  theme: theme,
                  config: data.config,
                );

                return switch (e.key) {
                  '' => value,
                  final key =>
                    '${theme.data.sectionStyle(key)}${theme.styledColon} $value',
                };
              }),
            final data => [Loggable.objectToString(data, theme: theme)],
          }
            .map(
              (line) => RichText(
                maxLines: 8,
                overflow: TextOverflow.fade,
                text: ansiText2TextSpan(
                  line,
                  defaulStyle: theme.data.normal,
                  fontSize: _dataFontSize,
                ),
              ),
            )
            .toList();
  }

  Widget? _buildError() {
    final log = widget.log;
    final theme = widget.theme.main.error;
    final error = log.error;
    if (error == null) return null;

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.fade,
      text: ansiText2TextSpan(
        '${theme.data.sectionStyle(theme.main.errorTitle)}'
        '${theme.styledColon}'
        ' ${theme.formatMessage(
          theme.formatValue(
            '$error',
            escapeAnsiCodes: LoggableConfig.defaultEscapeAnsiCodes,
          ),
          escapeAnsiCodes: false,
        )}',
        defaulStyle: theme.data.normal,
        fontSize: _dataFontSize,
      ),
    );
  }

  Widget? _buildStackTrace() {
    final log = widget.log;
    final theme = widget.theme.main.error;
    final stackTraceBox = _stackTracerBuilder(log, theme, LogItem._row, null);
    if (stackTraceBox.lines.isEmpty) return null;

    return RichText(
      maxLines: 8,
      overflow: TextOverflow.fade,
      text: ansiText2TextSpan(
        stackTraceBox.lines.join('\n'),
        defaulStyle: theme.data.normal,
        fontSize: _dataFontSize,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final theme = widget.theme;

    return DefaultTextStyle.merge(
      style: TextStyle(color: _color),
      child: Stack(
        children: [
          // box with content
          Material(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_borderRadius),
              side: BorderSide(color: _borderColor),
            ),
            child: InkWell(
              onTap: widget.onTap,
              onTapDown: switch (widget.onTapDown) {
                null => null,
                final fn => (_) => fn(),
              },
              onLongPress: widget.onLongPress,
              focusColor: _color.withValues(alpha: 0.2),
              highlightColor: _color.withValues(alpha: 0.3),
              splashColor: _color.withValues(alpha: 0.4),
              hoverColor: _color.withValues(alpha: 0.1),
              canRequestFocus: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // top row
                  Row(
                    children: [
                      BorderContainer(
                        text: log.levelName,
                        style: theme.data.levelNameStyle,
                        defaultStyle: theme.data.normal,
                        borderColor: _borderColor,
                        borderRightRounded: true,
                      ),
                      const SizedBox(width: _itemsSeparator),
                      BorderContainer(
                        text: LogTime.timeToString(log.time),
                        style: theme.data.timeStyle,
                        defaultStyle: theme.data.normal,
                        borderColor: _borderColor,
                        borderLeftRounded: true,
                        borderRightRounded: true,
                      ),
                      const SizedBox(width: _itemsSeparator),
                      BorderContainer(
                        text: log.path,
                        style: theme.data.pathStyle,
                        defaultStyle: theme.data.normal,
                        borderColor: _borderColor,
                        borderLeftRounded: true,
                        borderRightRounded: true,
                      ),
                      const Spacer(),
                      BorderContainer(
                        text: log.num.toString(),
                        style: theme.data.numStyle,
                        defaultStyle: theme.data.normal,
                        borderColor: _borderColor,
                        borderLeftRounded: true,
                      ),
                    ],
                  ),
                  // trace ids
                  if (log.traceIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: _itemsSeparator,
                        right: _itemsSeparator,
                        top: _itemsSeparator,
                      ),
                      child: Wrap(
                        spacing: _itemsSeparator,
                        runSpacing: _itemsSeparator,
                        children: [
                          for (final traceId in log.traceIds)
                            BorderContainer(
                              text: traceId.toString(),
                              style: theme.main.traceIdStyle,
                              defaultStyle: theme.data.normal,
                              topLeftRounded: true,
                              topRightRounded: true,
                              borderLeftRounded: true,
                              borderRightRounded: true,
                            ),
                        ],
                      ),
                    ),
                  // message
                  if (_message case final message?)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: _itemsSeparator,
                        right: _itemsSeparator,
                        top: _sectionSeparator,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(_borderRadius),
                          ),
                          border: Border.all(
                            color: _messageBorderColor,
                          ),
                          color: _messageBackgroundColor,
                        ),
                        padding: _messagePadding,
                        child: message,
                      ),
                    ),
                  // data + error + stacktrace
                  Padding(
                    padding: const EdgeInsets.only(
                      left: _contentLeftPadding,
                      right: _contentRightPadding,
                      top: _sectionSeparator,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: _sectionSeparator,
                      children: [
                        ..._data,
                        if (_error case final error?) error,
                        if (_stackTrace case final stackTrace?) stackTrace,
                        const SizedBox.shrink(),
                      ],
                    ),
                  ),
                  // bottom row
                  Row(
                    spacing: _itemsSeparator,
                    children: [
                      if (widget.removed)
                        BorderContainer(
                          text: 'REMOVED',
                          style: ansi.Style(
                            background:
                                theme.main.error.data.normal.foregroundColor,
                            foreground: ansi.Color256.rgb555,
                          ),
                          defaultStyle: theme.data.normal,
                          borderColor: _borderColor,
                          topRightRounded: true,
                        ),
                      const Spacer(),
                      for (final (index, tag) in log.tags.indexed)
                        BorderContainer(
                          text: '#$tag',
                          style: theme.main.tagsStyle,
                          defaultStyle: theme.data.normal,
                          topLeftRounded: true,
                          topRightRounded: index != log.tags.length - 1,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
