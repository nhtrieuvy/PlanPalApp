import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/responsive/app_breakpoints.dart';

/// Keeps content readable on wide screens without changing compact layouts.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.mediumMaxWidth = 900,
    this.expandedMaxWidth = 1280,
    this.compactPadding = EdgeInsets.zero,
    this.mediumPadding = const EdgeInsets.symmetric(horizontal: 24),
    this.expandedPadding = const EdgeInsets.symmetric(horizontal: 32),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double mediumMaxWidth;
  final double expandedMaxWidth;
  final EdgeInsetsGeometry compactPadding;
  final EdgeInsetsGeometry mediumPadding;
  final EdgeInsetsGeometry expandedPadding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final windowClass = AppBreakpoints.windowClassOf(context);
    final maxWidth = switch (windowClass) {
      AppWindowClass.compact => double.infinity,
      AppWindowClass.medium => mediumMaxWidth,
      AppWindowClass.expanded => expandedMaxWidth,
    };
    final padding = switch (windowClass) {
      AppWindowClass.compact => compactPadding,
      AppWindowClass.medium => mediumPadding,
      AppWindowClass.expanded => expandedPadding,
    };

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
