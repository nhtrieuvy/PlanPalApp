import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';

/// A reusable card widget with consistent styling across the app
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final double? elevation;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final Border? border;
  final bool showShadow;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.showShadow = false,
  });

  /// Creates a list item card with standard spacing
  const AppCard.listItem({
    super.key,
    required this.child,
    this.onTap,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.showShadow = false,
  }) : padding = const EdgeInsets.all(AppSpacing.md),
       margin = const EdgeInsets.only(bottom: AppSpacing.sm);

  /// Creates a section card with more spacing
  const AppCard.section({
    super.key,
    required this.child,
    this.onTap,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.showShadow = false,
  }) : padding = const EdgeInsets.all(AppSpacing.lg),
       margin = const EdgeInsets.symmetric(vertical: AppSpacing.xs);

  /// Creates a compact card for small items
  const AppCard.compact({
    super.key,
    required this.child,
    this.onTap,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.showShadow = false,
  }) : padding = const EdgeInsets.all(AppSpacing.sm),
       margin = const EdgeInsets.only(bottom: AppSpacing.xs);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultBackgroundColor = backgroundColor ?? theme.cardColor;
    final defaultElevation = elevation ?? (showShadow ? 2.0 : 0.0);
    final defaultBorderRadius =
        borderRadius ?? BorderRadius.circular(AppRadius.card);
    final defaultPadding = padding ?? const EdgeInsets.all(AppSpacing.md);
    final defaultMargin = margin ?? EdgeInsets.zero;

    Widget card = Container(
      margin: defaultMargin,
      decoration: BoxDecoration(
        color: defaultBackgroundColor,
        borderRadius: defaultBorderRadius,
        border: border ?? Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: showShadow && defaultElevation > 0
            ? [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(padding: defaultPadding, child: child),
    );

    if (onTap != null) {
      card = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: defaultBorderRadius,
          child: card,
        ),
      );
    }

    return card;
  }
}
