import 'package:flutter/material.dart';
import 'package:team_logger/team_logger.dart';

import '../ansi_utils.dart';
import '../uikit/border_container.dart';
import 'log_node.dart';

const double _fontSize = 11;
const double _indent = 14;
const double _arrowSize = 14;
const double _badgeSeparator = 3;

/// One row of the log data tree.
class LogNodeTile extends StatelessWidget {
  final LogNode node;
  final LogTheme theme;
  final bool real;
  final bool expanded;
  final bool expandable;
  final void Function()? onTap;

  const LogNodeTile({
    super.key,
    required this.node,
    required this.theme,
    required this.real,
    required this.expanded,
    required this.expandable,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = node.showName ? node.nameText(theme) : '';
    final text = expanded
        ? node.headerText(theme: theme, real: real)
        : node.valueText(theme: theme, real: real);
    final line = name.isEmpty || text.isEmpty
        ? '$name$text'
        : '$name${theme.styledColon} $text';

    return InkWell(
      onTap: expandable ? onTap : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: _indent * node.depth,
          top: 1,
          bottom: 1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: _badgeSeparator,
          children: [
            SizedBox(
              width: _arrowSize,
              child: expandable
                  ? Icon(
                      expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                      size: _arrowSize,
                    )
                  : null,
            ),
            Expanded(
              child: RichText(
                text: ansiText2TextSpan(
                  line,
                  defaulStyle: theme.data.normal,
                  fontSize: _fontSize,
                ),
              ),
            ),
            if (node.hidden)
              BorderContainer(
                text: 'hidden',
                style: theme.data.dim,
                defaultStyle: theme.data.normal,
                topLeftRounded: true,
                topRightRounded: true,
                borderLeftRounded: true,
                borderRightRounded: true,
              ),
            if (node.computed)
              BorderContainer(
                text: 'computed',
                style: theme.data.emphasis,
                defaultStyle: theme.data.normal,
                topLeftRounded: true,
                topRightRounded: true,
                borderLeftRounded: true,
                borderRightRounded: true,
              ),
          ],
        ),
      ),
    );
  }
}
