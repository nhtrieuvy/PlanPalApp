import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';

/// A reusable card widget with consistent styling across the app
class AppCard extends StatefulWidget {
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
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultBackgroundColor =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerLowest;
    final defaultElevation =
        widget.elevation ?? (widget.showShadow ? 2.0 : 0.0);
    final defaultBorderRadius =
        widget.borderRadius ?? BorderRadius.circular(AppRadius.card);
    final defaultPadding =
        widget.padding ?? const EdgeInsets.all(AppSpacing.md);
    final defaultMargin = widget.margin ?? EdgeInsets.zero;

    final card = AnimatedContainer(
      duration: AppMotion.quick,
      curve: AppMotion.enter,
      margin: defaultMargin,
      decoration: BoxDecoration(
        color: defaultBackgroundColor,
        borderRadius: defaultBorderRadius,
        border:
            widget.border ??
            Border.all(
              color: _hovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.45)
                  : theme.colorScheme.outlineVariant,
            ),
        boxShadow: defaultElevation > 0
            ? [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: defaultBorderRadius,
          child: Padding(padding: defaultPadding, child: widget.child),
        ),
      ),
    );

    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: widget.onTap == null
          ? null
          : (_) => setState(() => _hovered = true),
      onExit: widget.onTap == null
          ? null
          : (_) => setState(() => _hovered = false),
      child: card,
    );
  }
}
