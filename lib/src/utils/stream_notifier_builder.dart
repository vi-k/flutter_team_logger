import 'package:flutter/material.dart';

class StreamNotifierBuilder extends StreamBuilder<void> {
  StreamNotifierBuilder({
    super.key,
    required super.stream,
    required Widget Function(BuildContext context) builder,
  }) : super(
          builder: (context, _) => builder(context),
        );
}
