import 'package:flutter/material.dart';
import 'package:team_logger/team_logger.dart';

import 'ansi_utils.dart';

class LogItem extends StatefulWidget {
  static const _row = LogRow(children: [], maxLength: 10000);

  final Log log;
  final LogTheme theme;
  final bool removed;

  const LogItem(
    this.log,
    this.theme, {
    this.removed = false,
    super.key,
  });

  @override
  State<LogItem> createState() => _LogItemState();
}

class _LogItemState extends State<LogItem> {
  static final Color removedColor = Colors.redAccent.shade700;
  static const Color onRemovedColor = Colors.black87;
  static const double borderTextFontSize = 11;
  static const double messageFontSize = 13;
  static const double dataFontSize = 11;
  static const double removedFontSize = 10;

  static const EdgeInsetsGeometry boxOffset =
      EdgeInsets.only(top: 7, bottom: 6);
  static const double boxBorderRadius = 4;
  static const double borderRowLeftPadding = 6;
  static const double borderRowRightPadding = 6;
  static const EdgeInsetsGeometry borderTextPadding =
      EdgeInsets.symmetric(vertical: 1, horizontal: 1);
  static const double sectionSeparator = 8;
  static const EdgeInsetsGeometry contentPadding =
      EdgeInsets.only(top: 12, bottom: 8, left: 6, right: 6);

  static const _stackTracerBuilder = LogStackTrace(showIndexes: true);

  late final Widget _title;
  late final Widget _seqNum;
  late final Widget? _message;
  late final List<Widget> _data;
  late final Widget? _error;
  late final Widget? _stackTrace;
  late final Widget? _tags;
  late final Color _color;

  @override
  void initState() {
    super.initState();

    _color = ansiColor2Color(widget.theme.data.normal.foregroundColor)!;
    _title = _buildTitle();
    _message = _buildMessage();
    _data = _buildData();
    _seqNum = _buildSeqNum();
    _error = _buildError();
    _stackTrace = _buildStackTrace();
    _tags = _buildTags();
  }

  Widget _buildTitle() {
    final log = widget.log;
    final theme = widget.theme;

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: ansiText2TextSpan(
        '${'[${log.shortLevelName}]'} '
        '${theme.data.timeStyle(LogTime.timeToString(log.time))}'
        ' ${theme.data.pathStyle('[${log.path}]')}'
        '${theme.main.traceIdStyle(log.traceIds.map((e) => ' {$e}').join())}',
        defaulStyle: theme.data.normal,
        fontSize: borderTextFontSize,
      ),
    );
  }

  Widget _buildSeqNum() {
    final log = widget.log;
    final theme = widget.theme;

    return RichText(
      text: ansiText2TextSpan(
        theme.data.sequenceNumStyle('#${log.sequenceNum}'),
        defaulStyle: theme.data.normal,
        fontSize: borderTextFontSize,
      ),
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
              fontSize: messageFontSize,
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
                  fontSize: dataFontSize,
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
        fontSize: dataFontSize,
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
        fontSize: dataFontSize,
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
            text: ansiText2TextSpan(
              theme.main.tagsStyle(tags.map((e) => '#$e').join(' ')),
              defaulStyle: theme.data.normal,
              fontSize: borderTextFontSize,
            ),
          );
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
        style: TextStyle(color: _color),
        child: Stack(
          children: [
            // box with content
            Padding(
              padding: boxOffset,
              child: Material(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(boxBorderRadius),
                  side: BorderSide(color: _color),
                ),
                child: InkWell(
                  onTap: () {
                    //
                  },
                  focusColor: _color.withValues(alpha: 0.2),
                  highlightColor: _color.withValues(alpha: 0.3),
                  splashColor: _color.withValues(alpha: 0.4),
                  hoverColor: _color.withValues(alpha: 0.1),
                  canRequestFocus: false,
                  child: Padding(
                    padding: contentPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: sectionSeparator,
                      children: [
                        if (_message case final message?) message,
                        ..._data,
                        if (_error case final error?) error,
                        if (_stackTrace case final stackTrace?) stackTrace,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // top border row
            Positioned(
              top: 0,
              left: borderRowLeftPadding,
              right: borderRowRightPadding,
              child: IgnorePointer(
                child: Row(
                  children: [
                    // title
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          padding: borderTextPadding,
                          child: _title,
                        ),
                      ),
                    ),
                    // seq num
                    Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      padding: borderTextPadding,
                      child: _seqNum,
                    ),
                  ],
                ),
              ),
            ),
            // bottom border row
            if (_tags case final tags?)
              Positioned(
                bottom: 0,
                left: borderRowLeftPadding,
                right: borderRowRightPadding,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      if (widget.removed)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: removedColor,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(boxBorderRadius),
                            ),
                          ),
                          child: RichText(
                            text: const TextSpan(
                              text: ' REMOVED ',
                              style: TextStyle(
                                color: onRemovedColor,
                                fontSize: removedFontSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        padding: borderTextPadding,
                        child: tags,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}
