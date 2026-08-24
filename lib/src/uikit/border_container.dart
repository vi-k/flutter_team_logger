import 'package:ansi_escape_codes/style.dart' as ansi;
import 'package:flutter/material.dart';

import '../ansi_utils.dart';

/// Alpha applied to a foreground color to derive a border color.
const borderColorAlpha = 0.4;

/// A small bordered label: level name, time, path, log number, tags.
class BorderContainer extends StatelessWidget {
  static const EdgeInsetsGeometry _padding =
      EdgeInsets.only(left: 3, right: 3, top: 1, bottom: 1);
  static const double _borderRadius = 4;
  static const double _fontSize = 11;

  final String text;
  final ansi.Style style;
  final Color? borderColor;
  final bool topLeftRounded;
  final bool topRightRounded;
  final bool borderLeftRounded;
  final bool borderRightRounded;

  const BorderContainer({
    super.key,
    required ansi.Style style,
    required ansi.Style defaultStyle,
    this.borderColor,
    this.topLeftRounded = false,
    this.topRightRounded = false,
    this.borderLeftRounded = false,
    this.borderRightRounded = false,
    required this.text,
  }) : style = style is ansi.NoStyle ? defaultStyle : style;

  @override
  Widget build(BuildContext context) {
    final textStyle = ansiStyle2TextStyle(style, fontSize: _fontSize);
    final borderColor = this.borderColor ??
        ansiColor2Color(style.foregroundColor)?.withValues(
          alpha: borderColorAlpha,
        ) ??
        Colors.red;

    return Container(
      decoration: BoxDecoration(
        color: textStyle.backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.only(
          topLeft: topLeftRounded //
              ? const Radius.circular(_borderRadius)
              : Radius.zero,
          topRight: topRightRounded //
              ? const Radius.circular(_borderRadius)
              : Radius.zero,
          bottomLeft: borderLeftRounded //
              ? const Radius.circular(_borderRadius)
              : Radius.zero,
          bottomRight: borderRightRounded //
              ? const Radius.circular(_borderRadius)
              : Radius.zero,
        ),
      ),
      padding: _padding,
      child: Text(text, style: textStyle),
    );
  }
}
