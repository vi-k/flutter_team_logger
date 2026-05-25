import 'package:flutter/material.dart';

class Chip extends StatefulWidget {
  final Color color;
  final Color inactiveBackgroundColor;
  final bool active;
  final bool selected;
  final Widget title;
  final Widget? subtitle;
  final void Function()? onPressed;
  final void Function()? onLongPress;

  const Chip({
    super.key,
    this.active = false,
    this.selected = false,
    required this.color,
    this.inactiveBackgroundColor = Colors.transparent,
    required this.title,
    this.subtitle,
    this.onPressed,
    this.onLongPress,
  });

  @override
  State<Chip> createState() => _ChipState();
}

class _ChipState extends State<Chip> with SingleTickerProviderStateMixin {
  static const double _borderRadius = 100;
  static const EdgeInsetsGeometry _padding =
      EdgeInsets.symmetric(vertical: 2, horizontal: 6);

  late final _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  late final _animation =
      _animationController.drive(CurveTween(curve: Curves.ease));

  @override
  void initState() {
    super.initState();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _animation,
        builder: (context, child) => Align(
          widthFactor: _animation.value,
          alignment: Alignment.centerRight,
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(
              Radius.circular(_borderRadius + 2),
            ),
            border: Border.all(
              color: widget.selected ? widget.color : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.all(1),
          child: FilledButton(
            style: FilledButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              minimumSize: const Size(50, 0),
              padding: _padding,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(
                  Radius.circular(_borderRadius),
                ),
                side: BorderSide(
                  color: widget.active
                      ? Colors.transparent
                      : widget.color.withValues(alpha: 0.2),
                ),
              ),
              overlayColor: widget.active ? null : widget.color,
              backgroundColor: widget.active
                  ? widget.selected
                      ? widget.color
                      : widget.color.withValues(alpha: 0.7)
                  : widget.inactiveBackgroundColor,
            ),
            onPressed: widget.onPressed,
            onLongPress: widget.onLongPress,
            child: DefaultTextStyle.merge(
              softWrap: false,
              overflow: TextOverflow.fade,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: widget.active ? Colors.black : widget.color,
              ),
              child: Column(
                children: [
                  widget.title,
                  if (widget.subtitle case final subtitle?) subtitle,
                ],
              ),
            ),
          ),
        ),
      );
}

class FilterChip extends StatelessWidget {
  final Color color;
  final Color inactiveBackgroundColor;
  final bool active;
  final bool selected;
  final String title;
  final (int, int)? logsCount;
  final void Function()? onPressed;
  final void Function()? onLongPress;

  const FilterChip({
    super.key,
    this.active = false,
    this.selected = false,
    required this.color,
    this.inactiveBackgroundColor = Colors.transparent,
    required this.title,
    required this.logsCount,
    this.onPressed,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) => Chip(
        color: color,
        inactiveBackgroundColor: inactiveBackgroundColor,
        active: active,
        selected: selected,
        title: Text(title),
        subtitle: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 8),
          child: switch (logsCount) {
            null => const SizedBox.shrink(),
            (final int filtered, final int total) when filtered == total =>
              Text('($total)'),
            (final int filtered, final int total) =>
              Text('($filtered of $total)'),
          },
        ),
        onPressed: onPressed,
        onLongPress: onLongPress,
      );
}
