import 'package:flutter/material.dart';

class Chip extends StatefulWidget {
  static const double _borderRadius = 100;
  static const EdgeInsetsGeometry _padding =
      EdgeInsets.symmetric(vertical: 2, horizontal: 6);

  final Color color;
  final Color inactiveBackgroundColor;
  final bool active;
  final Widget title;
  final Widget? subtitle;
  final void Function()? onPressed;
  final void Function()? onLongPress;

  const Chip({
    super.key,
    this.active = false,
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
        child: InkWell(
          onTap: widget.onPressed,
          onLongPress: widget.onLongPress,
          focusColor: widget.color.withValues(alpha: 0.2),
          highlightColor: widget.color.withValues(alpha: 0.3),
          splashColor: widget.color.withValues(alpha: 0.4),
          hoverColor: widget.color.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.all(
            Radius.circular(Chip._borderRadius),
          ),
          child: Container(
            decoration: BoxDecoration(
              color:
                  widget.active ? widget.color : widget.inactiveBackgroundColor,
              borderRadius: const BorderRadius.all(
                Radius.circular(Chip._borderRadius),
              ),
              border: Border.all(color: widget.color.withValues(alpha: 0.4)),
            ),
            padding: Chip._padding,
            constraints: const BoxConstraints(minWidth: 50),
            child: DefaultTextStyle.merge(
              softWrap: false,
              overflow: TextOverflow.fade,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: widget.active
                    ? Color.lerp(widget.color, Colors.black, 0.9)
                    : widget.color,
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
  final String title;
  final int logsCount;
  final int newLogsCount;
  final void Function()? onPressed;
  final void Function()? onLongPress;

  const FilterChip({
    super.key,
    this.active = false,
    required this.color,
    this.inactiveBackgroundColor = Colors.transparent,
    required this.title,
    required this.logsCount,
    required this.newLogsCount,
    this.onPressed,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) => Chip(
        color: color,
        inactiveBackgroundColor: inactiveBackgroundColor,
        active: active,
        title: Text(title),
        subtitle: Text(
          '$logsCount'
          '${newLogsCount == 0 ? '' : '+$newLogsCount'}',
          style: const TextStyle(fontSize: 8),
        ),
        onPressed: onPressed,
        onLongPress: onLongPress,
      );
}
