import 'package:flutter/material.dart';
import 'package:team_logger/team_logger.dart';

import 'ansi_utils.dart';

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
  static final Color _removedColor = Colors.redAccent.shade700;
  static const double _borderItemsFontSize = 11;
  static const double _messageFontSize = 12;
  static const double _dataFontSize = 11;
  static const double _removedFontSize = 10;

  static const double _borderRadius = 4;
  static const double _sectionSeparator = 6;
  static const double _itemsSeparator = 3;
  static const EdgeInsetsGeometry _borderItemsPadding =
      EdgeInsets.only(left: 3, right: 3, top: 1, bottom: 1);
  static const double _contentLeftPadding = 6;
  static const double _contentRightPadding = 6;
  static const EdgeInsetsGeometry _messagePadding =
      EdgeInsets.only(left: 3, right: 3, top: 3, bottom: 3);

  static const _stackTracerBuilder = LogStackTrace(showIndexes: true);

  late final Widget _levelName;
  late final Widget _time;
  late final Widget _name;
  late final List<Widget> _traceIds;
  late final Widget _seqNum;
  late final Widget? _message;
  late final List<Widget> _data;
  late final Widget? _error;
  late final Widget? _stackTrace;
  late final Widget? _tags;
  late final Color _color;
  late final Color _borderColor;
  late final Color _messageBorderColor;
  late final Color _messageBackgroundColor;
  late final Color _activeItemsTextColor;
  late final Color _inactiveItemsTextColor;
  late final Color _traceIdTextColor;
  late final Color _traceIdBorderColor;

  @override
  void initState() {
    super.initState();

    _color = ansiColor2Color(widget.theme.data.normal.foregroundColor)!;
    _messageBorderColor = _color.withValues(alpha: 0.4);
    _messageBackgroundColor = _color.withValues(alpha: 0.1);
    _activeItemsTextColor = _color;
    _inactiveItemsTextColor = _color.withValues(alpha: 0.7);
    _traceIdTextColor =
        ansiColor2Color(widget.theme.main.traceIdStyle.foregroundColor) ??
            _color;
    _traceIdBorderColor = _traceIdTextColor.withValues(alpha: 0.4);

    _levelName = _buildLevelName();
    _time = _buildTime();
    _name = _buildName();
    _traceIds = _buildTraceIds();
    _message = _buildMessage();
    _data = _buildData();
    _seqNum = _buildSeqNum();
    _error = _buildError();
    _stackTrace = _buildStackTrace();
    _tags = _buildTags();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    _borderColor = Color.lerp(backgroundColor, _color, 0.4)!;
  }

  Widget _buildLevelName() {
    final log = widget.log;

    return RichText(
      maxLines: 1,
      text: TextSpan(
        text: log.levelName,
        style: TextStyle(
          fontSize: _borderItemsFontSize,
          color: log.level < LogLevels.warning
              ? _inactiveItemsTextColor
              : _activeItemsTextColor,
          fontWeight: log.level < LogLevels.warning
              ? FontWeight.normal
              : FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTime() {
    final log = widget.log;

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        text: LogTime.timeToString(log.time),
        style: TextStyle(
          fontSize: _borderItemsFontSize,
          color: _inactiveItemsTextColor,
        ),
      ),
    );
  }

  Widget _buildName() {
    final log = widget.log;

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        text: log.path,
        style: TextStyle(
          fontSize: _borderItemsFontSize,
          color: _activeItemsTextColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Widget> _buildTraceIds() {
    final log = widget.log;
    // final theme = widget.theme;

    return log.traceIds.isEmpty
        ? []
        : log.traceIds
            .map(
              (e) => RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  text: '$e',
                  style: TextStyle(
                    fontSize: _borderItemsFontSize,
                    color: _traceIdTextColor,
                  ),
                ),
              ),
            )
            .toList();
  }

  Widget _buildSeqNum() {
    final log = widget.log;
    // final theme = widget.theme;

    return RichText(
      text: TextSpan(
        text: '${log.sequenceNum}',
        style: TextStyle(
          fontSize: _borderItemsFontSize,
          color: _inactiveItemsTextColor,
        ),
      ),
      // text: ansiText2TextSpan(
      //   theme.data.sequenceNumStyle('#${log.sequenceNum}'),
      //   defaulStyle: theme.data.normal,
      //   fontSize: borderTextFontSize,
      // ),
    );
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
              theme.formatMessage(theme.formatValue(log.message)),
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
        ' ${theme.formatMessage(theme.formatValue('$error'))}',
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

  Widget? _buildTags() {
    final log = widget.log;
    final theme = widget.theme.main.error;
    final tags = theme.allTags(log);

    return tags.isEmpty
        ? null
        : RichText(
            text: TextSpan(
              text: tags.map((tag) => '#$tag').join(' '),
              style: TextStyle(
                color: _inactiveItemsTextColor,
                fontSize: _borderItemsFontSize,
              ),
            ),
          );
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
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
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: _borderColor),
                              bottom: BorderSide(color: _borderColor),
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(_borderRadius),
                            ),
                          ),
                          padding: _borderItemsPadding,
                          child: _levelName,
                        ),
                        const SizedBox(width: _itemsSeparator),
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: _borderColor),
                              right: BorderSide(color: _borderColor),
                              bottom: BorderSide(color: _borderColor),
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(_borderRadius),
                              bottomRight: Radius.circular(_borderRadius),
                            ),
                          ),
                          padding: _borderItemsPadding,
                          child: _time,
                        ),
                        const SizedBox(width: _itemsSeparator),
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: _borderColor),
                              right: BorderSide(color: _borderColor),
                              bottom: BorderSide(color: _borderColor),
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(_borderRadius),
                              bottomRight: Radius.circular(_borderRadius),
                            ),
                          ),
                          padding: _borderItemsPadding,
                          child: _name,
                        ),
                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: _borderColor),
                              bottom: BorderSide(color: _borderColor),
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(_borderRadius),
                            ),
                          ),
                          padding: _borderItemsPadding,
                          child: _seqNum,
                        ),
                      ],
                    ),
                    // trace ids
                    if (_traceIds.isNotEmpty)
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
                            for (final traceId in _traceIds)
                              _BorderItem(
                                borderColor: _traceIdBorderColor,
                                child: traceId,
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
                    // data, error, stacktrace
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
                      children: [
                        if (widget.removed)
                          Container(
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(color: _borderColor),
                                top: BorderSide(color: _borderColor),
                              ),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(_borderRadius),
                              ),
                            ),
                            padding: _borderItemsPadding,
                            child: RichText(
                              text: TextSpan(
                                text: 'REMOVED',
                                style: TextStyle(
                                  color: _removedColor,
                                  fontSize: _removedFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: _borderColor),
                              top: BorderSide(color: _borderColor),
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(_borderRadius),
                            ),
                          ),
                          padding: _borderItemsPadding,
                          child: _tags,
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

class _BorderItem extends StatelessWidget {
  static const double _borderRadius = 4;
  static const EdgeInsetsGeometry _padding =
      EdgeInsets.symmetric(horizontal: 1);

  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;

  const _BorderItem({
    // ignore: unused_element_parameter
    super.key,
    // ignore: unused_element_parameter
    this.backgroundColor,
    // ignore: unused_element_parameter
    this.borderColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: _padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          border: switch (borderColor) {
            null => null,
            final color => Border.all(color: color)
          },
          borderRadius: const BorderRadius.all(
            Radius.circular(_borderRadius),
          ),
        ),
        child: child,
      );
}
