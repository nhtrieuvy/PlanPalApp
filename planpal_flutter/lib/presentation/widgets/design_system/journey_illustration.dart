import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';

enum JourneyIllustrationType {
  emptyTrips,
  emptyGroups,
  emptyMessages,
  emptyPolls,
  onboarding,
  tripCreated,
  destination,
}

class JourneyIllustration extends StatelessWidget {
  const JourneyIllustration({
    super.key,
    required this.type,
    this.width = 220,
    this.height = 150,
  });

  final JourneyIllustrationType type;
  final double width;
  final double height;

  IconData get _icon => switch (type) {
    JourneyIllustrationType.emptyTrips => Icons.route_outlined,
    JourneyIllustrationType.emptyGroups => Icons.group_outlined,
    JourneyIllustrationType.emptyMessages => Icons.chat_bubble_outline_rounded,
    JourneyIllustrationType.emptyPolls => Icons.how_to_vote_outlined,
    JourneyIllustrationType.onboarding => Icons.explore_outlined,
    JourneyIllustrationType.tripCreated => Icons.check_rounded,
    JourneyIllustrationType.destination => Icons.landscape_outlined,
  };

  bool get _arrived => type == JourneyIllustrationType.tripCreated;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _CartographicIllustrationPainter(
            primary: colors.primary,
            secondary: colors.secondary,
            surface: colors.surfaceContainerLow,
            arrived: _arrived,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.standard,
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _arrived ? AppColors.sunsetCoral : colors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 4),
              ),
              child: Icon(_icon, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartographicIllustrationPainter extends CustomPainter {
  const _CartographicIllustrationPainter({
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.arrived,
  });

  final Color primary;
  final Color secondary;
  final Color surface;
  final bool arrived;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)),
      Paint()..color = surface,
    );

    final contourPaint = Paint()
      ..color = secondary.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var index = 0; index < 3; index++) {
      final inset = 12.0 + index * 12;
      canvas.drawOval(
        Rect.fromLTWH(
          inset,
          size.height * .18 + index * 4,
          size.width - inset * 2,
          size.height * .58 - index * 8,
        ),
        contourPaint,
      );
    }

    final route = Path()
      ..moveTo(size.width * .08, size.height * .78)
      ..cubicTo(
        size.width * .3,
        size.height * .95,
        size.width * .38,
        size.height * .28,
        size.width * .58,
        size.height * .5,
      )
      ..cubicTo(
        size.width * .72,
        size.height * .67,
        size.width * .8,
        size.height * .2,
        size.width * .92,
        size.height * .28,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = primary.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(size.width * .08, size.height * .78),
      5,
      Paint()..color = primary,
    );
    canvas.drawCircle(
      Offset(size.width * .92, size.height * .28),
      arrived ? 8 : 6,
      Paint()..color = AppColors.sunsetCoral,
    );
  }

  @override
  bool shouldRepaint(covariant _CartographicIllustrationPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.surface != surface ||
      oldDelegate.arrived != arrived;
}
