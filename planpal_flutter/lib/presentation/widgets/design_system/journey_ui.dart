import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';

/// Shared visual language for PlanPal's planning surfaces. These components
/// create hierarchy with type and spacing before introducing containers.
class JourneyPageHeader extends StatelessWidget {
  const JourneyPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.leadingIcon,
    this.action,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final IconData? leadingIcon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leadingIcon != null) ...[
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Icon(leadingIcon, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

class JourneySectionHeader extends StatelessWidget {
  const JourneySectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.xs),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class JourneySurface extends StatefulWidget {
  const JourneySurface({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.selected = false,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool selected;
  final String? semanticLabel;

  @override
  State<JourneySurface> createState() => _JourneySurfaceState();
}

class _JourneySurfaceState extends State<JourneySurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final interactive = widget.onTap != null;
    final background = widget.selected
        ? colors.primaryContainer.withValues(alpha: 0.55)
        : _hovered && interactive
        ? colors.surfaceContainerLow
        : colors.surfaceContainerLowest;

    final surface = AnimatedContainer(
      duration: AppMotion.quick,
      curve: AppMotion.enter,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: widget.selected ? colors.primary : colors.outlineVariant,
          width: widget.selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );

    return Semantics(
      button: interactive,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
        onExit: interactive ? (_) => setState(() => _hovered = false) : null,
        child: surface,
      ),
    );
  }
}

class JourneyMetricData {
  const JourneyMetricData({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasis;
}

class JourneyMetricStrip extends StatelessWidget {
  const JourneyMetricStrip({super.key, required this.metrics});

  final List<JourneyMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: metrics.map((metric) {
            final width = compact
                ? (constraints.maxWidth - AppSpacing.xs) / 2
                : (constraints.maxWidth -
                          AppSpacing.xs * (metrics.length - 1)) /
                      metrics.length;
            return SizedBox(
              width: width,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: metric.emphasis
                      ? colors.primaryContainer
                      : colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Row(
                  children: [
                    Icon(
                      metric.icon,
                      size: 18,
                      color: metric.emphasis
                          ? colors.onPrimaryContainer
                          : colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            metric.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// A route dot and connecting thread used by itinerary and activity feeds.
class JourneyRouteMarker extends StatelessWidget {
  const JourneyRouteMarker({
    super.key,
    required this.icon,
    this.isFirst = false,
    this.isLast = false,
    this.completed = false,
  });

  final IconData icon;
  final bool isFirst;
  final bool isLast;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final routeColor = completed ? colors.primary : colors.outline;
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: 2,
              color: isFirst ? Colors.transparent : routeColor,
            ),
          ),
          AnimatedContainer(
            duration: AppMotion.standard,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: completed ? colors.primary : colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: routeColor, width: 2),
            ),
            child: Icon(
              completed ? Icons.check_rounded : icon,
              size: 17,
              color: completed ? colors.onPrimary : colors.primary,
            ),
          ),
          Expanded(
            child: Container(
              width: 2,
              color: isLast ? Colors.transparent : routeColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet route-line motif for branded hero areas. It intentionally stays
/// low contrast so content remains the visual priority.
class JourneyPathBackdrop extends StatelessWidget {
  const JourneyPathBackdrop({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _JourneyPathPainter(
      color: color ?? Theme.of(context).colorScheme.onPrimary,
    ),
    child: child,
  );
}

/// Compact route progress for trip cards. It communicates journey stage
/// without introducing a dashboard-style percentage meter.
class JourneyRouteProgress extends StatelessWidget {
  const JourneyRouteProgress({
    super.key,
    required this.completedStops,
    this.totalStops = 3,
    this.color,
  });

  final int completedStops;
  final int totalStops;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final routeColor = color ?? Theme.of(context).colorScheme.primary;
    final safeTotal = totalStops < 2 ? 2 : totalStops;
    return Semantics(
      value: '$completedStops/$safeTotal',
      child: Row(
        children: [
          for (var index = 0; index < safeTotal; index++) ...[
            AnimatedContainer(
              duration: AppMotion.standard,
              width: index < completedStops ? 10 : 8,
              height: index < completedStops ? 10 : 8,
              decoration: BoxDecoration(
                color: index < completedStops ? routeColor : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: routeColor, width: 1.5),
              ),
            ),
            if (index != safeTotal - 1)
              Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.standard,
                  height: 2,
                  color: index < completedStops - 1
                      ? routeColor
                      : routeColor.withValues(alpha: .28),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _JourneyPathPainter extends CustomPainter {
  const _JourneyPathPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(-size.width * .05, size.height * .78)
      ..cubicTo(
        size.width * .2,
        size.height * .95,
        size.width * .34,
        size.height * .22,
        size.width * .56,
        size.height * .48,
      )
      ..cubicTo(
        size.width * .72,
        size.height * .68,
        size.width * .82,
        size.height * .12,
        size.width * 1.08,
        size.height * .24,
      );
    final paint = Paint()
      ..color = color.withValues(alpha: .2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);

    final dotPaint = Paint()..color = color.withValues(alpha: .5);
    canvas.drawCircle(Offset(size.width * .56, size.height * .48), 5, dotPaint);
    canvas.drawCircle(Offset(size.width * .82, size.height * .23), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _JourneyPathPainter oldDelegate) =>
      oldDelegate.color != color;
}
