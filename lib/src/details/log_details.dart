import 'package:ansi_escape_codes/style.dart' as ansi;
import 'package:flutter/material.dart';
import 'package:team_logger/team_logger.dart';

import '../ansi_utils.dart';
import '../uikit/border_container.dart';
import 'log_node.dart';
import 'log_node_tile.dart';

final ThemeData _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.lightBlue,
    brightness: Brightness.dark,
  ),
);

const double _padding = 6;
const double _itemsSeparator = 3;
const double _messageFontSize = 12;
const double _dataFontSize = 11;
const _stackTraceBuilder = LogStackTrace(showIndexes: true);
const _row = LogRow(children: [], maxLength: 10000);

/// A screen with everything one log holds.
///
/// Two modes. As logged: views are drawn and hidden properties are omitted —
/// exactly what the console shows. Real data: the values behind the views,
/// the hidden properties, and no `Loggable.sanitizer` — the screen reads the
/// objects from memory, the way a debugger's inspector does. Keep out of the
/// log whatever must never reach the screen.
///
/// The tree is lazy, so a mutable object is shown as it is at the moment its
/// node gets expanded, not as it was when the log was written.
class LogDetails extends StatefulWidget {
  final Log log;
  final LogTheme theme;

  const LogDetails(this.log, this.theme, {super.key});

  @override
  State<LogDetails> createState() => _LogDetailsState();
}

class _LogDetailsState extends State<LogDetails> {
  final _expanded = <String>{};
  bool _real = false;

  @override
  void initState() {
    super.initState();

    // The first level is open from the start: everything below it is one tap
    // away, and a fully collapsed tree would show no more than the log item
    // in the list already does.
    for (final node in LogNode.root(widget.log.data).children(real: _real)) {
      if (node.expandable(real: _real)) _expanded.add(node.path);
    }
  }

  List<LogNode> _flatten() {
    final rows = <LogNode>[];

    void walk(LogNode node) {
      rows.add(node);
      if (!_expanded.contains(node.path)) return;
      node.children(real: _real).forEach(walk);
    }

    if (!widget.log.hasData) return rows;

    final root = LogNode.root(widget.log.data);
    if (!root.expandable(real: _real)) return [root];

    root.children(real: _real).forEach(walk);

    return rows;
  }

  void _toggle(LogNode node) => setState(() {
        if (!_expanded.remove(node.path)) _expanded.add(node.path);
      });

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final theme = widget.theme;
    final rows = _flatten();

    return Theme(
      data: _theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text('#${log.num} ${log.levelName}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: _padding),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(fontSize: _dataFontSize),
                  ),
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('as logged')),
                  ButtonSegment(value: true, label: Text('real data')),
                ],
                selected: {_real},
                onSelectionChanged: (selection) =>
                    setState(() => _real = selection.first),
              ),
            ),
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(_padding),
          itemCount: rows.length + 2,
          itemBuilder: (context, index) => switch (index) {
            0 => _Head(log: log, theme: theme),
            final i when i <= rows.length => _tile(rows[i - 1]),
            _ => _Tail(log: log, theme: theme),
          },
        ),
      ),
    );
  }

  Widget _tile(LogNode node) => LogNodeTile(
        node: node,
        theme: widget.theme,
        real: _real,
        expanded: _expanded.contains(node.path),
        expandable: node.expandable(real: _real),
        onTap: () => _toggle(node),
      );
}

class _Head extends StatelessWidget {
  final Log log;
  final LogTheme theme;

  const _Head({
    // ignore: unused_element_parameter
    super.key,
    required this.log,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _padding,
        children: [
          Wrap(
            spacing: _itemsSeparator,
            runSpacing: _itemsSeparator,
            children: [
              _Label(
                text: log.levelName,
                style: theme.data.levelNameStyle,
                defaultStyle: theme.data.normal,
              ),
              _Label(
                text: LogTime.timeToString(log.time),
                style: theme.data.timeStyle,
                defaultStyle: theme.data.normal,
              ),
              _Label(
                text: log.path,
                style: theme.data.pathStyle,
                defaultStyle: theme.data.normal,
              ),
              for (final traceId in log.traceIds)
                _Label(
                  text: traceId.toString(),
                  style: theme.main.traceIdStyle,
                  defaultStyle: theme.data.normal,
                ),
              for (final tag in log.tags)
                _Label(
                  text: '#$tag',
                  style: theme.main.tagsStyle,
                  defaultStyle: theme.data.normal,
                ),
            ],
          ),
          if (log.message.isNotEmpty)
            RichText(
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
            ),
          const SizedBox.shrink(),
        ],
      );
}

class _Tail extends StatelessWidget {
  final Log log;
  final LogTheme theme;

  const _Tail({
    // ignore: unused_element_parameter
    super.key,
    required this.log,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final errorTheme = theme.main.error;
    final error = log.error;
    final stackTrace = _stackTraceBuilder(log, errorTheme, _row, null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _padding,
      children: [
        if (error != null)
          RichText(
            text: ansiText2TextSpan(
              '${errorTheme.data.sectionStyle(errorTheme.main.errorTitle)}'
              '${errorTheme.styledColon}'
              ' ${errorTheme.formatMessage(
                errorTheme.formatValue(
                  '$error',
                  escapeAnsiCodes: LoggableConfig.defaultEscapeAnsiCodes,
                ),
                escapeAnsiCodes: false,
              )}',
              defaulStyle: errorTheme.data.normal,
              fontSize: _dataFontSize,
            ),
          ),
        if (stackTrace.lines.isNotEmpty)
          RichText(
            text: ansiText2TextSpan(
              stackTrace.lines.join('\n'),
              defaulStyle: errorTheme.data.normal,
              fontSize: _dataFontSize,
            ),
          ),
      ],
    );
  }
}

/// A bordered label of the head row, rounded on every corner.
class _Label extends StatelessWidget {
  final String text;
  final ansi.Style style;
  final ansi.Style defaultStyle;

  const _Label({
    // ignore: unused_element_parameter
    super.key,
    required this.text,
    required this.style,
    required this.defaultStyle,
  });

  @override
  Widget build(BuildContext context) => BorderContainer(
        text: text,
        style: style,
        defaultStyle: defaultStyle,
        topLeftRounded: true,
        topRightRounded: true,
        borderLeftRounded: true,
        borderRightRounded: true,
      );
}
