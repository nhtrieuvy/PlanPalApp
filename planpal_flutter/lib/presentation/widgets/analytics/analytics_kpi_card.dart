import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:planpal_flutter/core/dtos/analytics_model.dart';

class AnalyticsKpiCard extends StatelessWidget {
  final AnalyticsKpi metric;
  final Color accentColor;
  final bool percentage;

  const AnalyticsKpiCard({
    super.key,
    required this.metric,
    required this.accentColor,
    this.percentage = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: surfaceColor,
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            metric.formatValue(percentage: percentage),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: metric.isPositiveChange
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              metric.changeLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: metric.isPositiveChange ? Colors.green.shade700 : Colors.red.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
