import 'package:ansi_escape_codes/style.dart' as ansi;
import 'package:flutter/material.dart';

TextSpan ansiText2TextSpan(
  String text, {
  required ansi.Style defaulStyle,
  double? fontSize,
}) {
  final parser = ansi.Parser(text);
  final spans = <TextSpan>[];

  for (final m in parser.matches) {
    final entity = m.entity;
    if (entity is ansi.Text) {
      final style = m.state.toStyle();
      spans.add(_buildTextSpan(entity.string, style));
    }
  }

  return TextSpan(
    style: ansiStyle2TextStyle(defaulStyle, fontSize: fontSize),
    children: spans,
  );
}

TextStyle ansiStyle2TextStyle(ansi.Style style, {double? fontSize}) =>
    TextStyle(
      fontSize: fontSize,
      color: ansiColor2Color(style.foregroundColor),
      backgroundColor: ansiColor2Color(style.backgroundColor),
      fontWeight: style.isBold ? FontWeight.bold : null,
      fontStyle: style.isItalic ? FontStyle.italic : null,
      decoration: style.isUnderline ? TextDecoration.underline : null,
    );

Color? ansiColor2Color(ansi.Color? color) => switch (color) {
      null => null,
      ansi.Color256(:final color) => ansiColors2Color(color),
      ansi.Color16(:final color) => ansiColors2Color(color),
      ansi.ColorRgb(:final r, :final g, :final b) =>
        Color.fromARGB(255, r, g, b),
    };

Color ansiColors2Color(ansi.Colors? color) => switch (color) {
      null => Colors.transparent,
      ansi.Colors.black => Colors.black,
      ansi.Colors.red => Colors.red,
      ansi.Colors.green => Colors.green,
      ansi.Colors.yellow => Colors.yellow,
      ansi.Colors.blue => Colors.blue,
      ansi.Colors.magenta => Colors.purple,
      ansi.Colors.cyan => Colors.cyan,
      ansi.Colors.white => Colors.white54,
      ansi.Colors.highBlack => Colors.white24,
      ansi.Colors.highRed => Colors.redAccent,
      ansi.Colors.highGreen => Colors.greenAccent,
      ansi.Colors.highYellow => Colors.yellowAccent,
      ansi.Colors.highBlue => Colors.blueAccent,
      ansi.Colors.highMagenta => Colors.purpleAccent,
      ansi.Colors.highCyan => Colors.cyanAccent,
      ansi.Colors.highWhite => Colors.white,
      < ansi.Colors.gray0 =>
        _rgbToColor(color.index - ansi.Colors.rgb000.index),
      _ => _grayToColor(color.index - ansi.Colors.gray0.index),
    };

Color _rgbToColor(int index) =>
    Color.fromARGB(255, index ~/ 36 * 51, index % 36 ~/ 6 * 51, index % 6 * 51);

Color _grayToColor(int index) {
  final gray = (index * 255 / 23).round();
  return Color.fromARGB(255, gray, gray, gray);
}

TextSpan _buildTextSpan(String text, ansi.Style style) => TextSpan(
      text: text,
      style: ansiStyle2TextStyle(style),
    );
