import 'package:flutter/material.dart';

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
    this.showShadow = true,
  });

  /// Creates a list item card with standard spacing
  AppCard.listItem({
    super.key,
    required this.child,
    this.onTap,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.showShadow = true,
  }) : padding = const EdgeInsets.all(16),
       margin = const EdgeInsets.only(bottom: 12);

  /// Creates a section card with more spacing
  AppCard.section({
    super.key,
    required this.child,
    this.onTap,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.showShadow = true,
  }) : padding = const EdgeInsets.all(20),
       margin = const EdgeInsets.symmetric(vertical: 8);

  /// Creates a compact card for small items
  AppCard.compact({
    super.key,
    required this.child,
    this.onTap,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.showShadow = true,
  }) : padding = const EdgeInsets.all(12),
       margin = const EdgeInsets.only(bottom: 8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultBackgroundColor = backgroundColor ?? theme.cardColor;
    final defaultElevation = elevation ?? (showShadow ? 2.0 : 0.0);
    final defaultBorderRadius = borderRadius ?? BorderRadius.circular(12);
    final defaultPadding = padding ?? const EdgeInsets.all(16);
    final defaultMargin = margin ?? EdgeInsets.zero;

    Widget card = Container(
      margin: defaultMargin,
      decoration: BoxDecoration(
        color: defaultBackgroundColor,
        borderRadius: defaultBorderRadius,
        border: border,
        boxShadow: showShadow && defaultElevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: defaultElevation * 2,
                  offset: Offset(0, defaultElevation),
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
