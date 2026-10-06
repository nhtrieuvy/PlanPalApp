import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';

enum JourneyDirection { horizontal, vertical }

enum JourneyStopState { upcoming, current, completed }

class JourneyStop extends StatelessWidget {
  const JourneyStop({
    super.key,
    required this.state,
    this.icon,
    this.isDestination = false,
    this.size = 28,
  });

  final JourneyStopState state;
  final IconData? icon;
  final bool isDestination;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = state != JourneyStopState.upcoming;
    final fill = isDestination && active
        ? AppColors.sunsetCoral
        : active
        ? colors.primary
        : colors.surface;
    final foreground = active ? Colors.white : colors.onSurfaceVariant;
    return AnimatedContainer(
      duration: AppMotion.standard,
      curve: AppMotion.enter,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDestination
              ? AppColors.sunsetCoral
              : active
              ? colors.primary
              : colors.outline,
          width: state == JourneyStopState.current ? 3 : 2,
        ),
      ),
      child: Icon(
        state == JourneyStopState.completed
            ? Icons.check_rounded
            : icon ?? Icons.circle,
        size: size * .52,
        color: foreground,
      ),
    );
  }
}

class JourneyLine extends StatelessWidget {
  const JourneyLine({
    super.key,
    required this.stopCount,
    required this.currentStop,
    this.direction = JourneyDirection.horizontal,
    this.destinationAtEnd = true,
  }) : assert(stopCount >= 2);

  final int stopCount;
  final int currentStop;
  final JourneyDirection direction;
  final bool destinationAtEnd;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var index = 0; index < stopCount; index++) {
      final state = index < currentStop
          ? JourneyStopState.completed
          : index == currentStop
          ? JourneyStopState.current
          : JourneyStopState.upcoming;
      children.add(
        JourneyStop(
          state: state,
          isDestination: destinationAtEnd && index == stopCount - 1,
        ),
      );
      if (index != stopCount - 1) {
        final connector = _JourneyConnector(
          active: index < currentStop,
          direction: direction,
        );
        children.add(
          direction == JourneyDirection.horizontal
              ? Expanded(child: connector)
              : SizedBox(height: 24, child: connector),
        );
      }
    }
    return direction == JourneyDirection.horizontal
        ? Row(children: children)
        : Column(children: children);
  }
}

class JourneyPath extends StatelessWidget {
  const JourneyPath({
    super.key,
    required this.child,
    this.color,
    this.strokeWidth = 2,
  });

  final Widget child;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _JourneyPathPainter(
      color: color ?? Theme.of(context).colorScheme.primary,
      strokeWidth: strokeWidth,
    ),
    child: child,
  );
}

class JourneyProgress extends StatelessWidget {
  const JourneyProgress({
    super.key,
    required this.completedStops,
    required this.totalStops,
    this.direction = JourneyDirection.horizontal,
  });

  final int completedStops;
  final int totalStops;
  final JourneyDirection direction;

  @override
  Widget build(BuildContext context) => Semantics(
    value: '$completedStops/$totalStops',
    child: JourneyLine(
      stopCount: totalStops < 2 ? 2 : totalStops,
      currentStop: completedStops.clamp(0, totalStops).toInt(),
      direction: direction,
    ),
  );
}

class _JourneyConnector extends StatelessWidget {
  const _JourneyConnector({required this.active, required this.direction});

  final bool active;
  final JourneyDirection direction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.standard,
      width: direction == JourneyDirection.vertical ? 2 : null,
      height: direction == JourneyDirection.horizontal ? 2 : null,
      color: active ? colors.primary : colors.outlineVariant,
    );
  }
}

class _JourneyPathPainter extends CustomPainter {
  const _JourneyPathPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(-size.width * .04, size.height * .72)
      ..cubicTo(
        size.width * .23,
        size.height * .98,
        size.width * .38,
        size.height * .2,
        size.width * .58,
        size.height * .48,
      )
      ..cubicTo(
        size.width * .76,
        size.height * .7,
        size.width * .86,
        size.height * .08,
        size.width * 1.05,
        size.height * .26,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _JourneyPathPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
