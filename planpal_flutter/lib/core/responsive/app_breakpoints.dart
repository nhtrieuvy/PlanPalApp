import 'package:flutter/widgets.dart';

enum AppWindowClass { compact, medium, expanded }

abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double expanded = 1024;

  static AppWindowClass windowClassOf(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < compact) return AppWindowClass.compact;
    if (width <= expanded) return AppWindowClass.medium;
    return AppWindowClass.expanded;
  }

  static bool isCompact(BuildContext context) =>
      windowClassOf(context) == AppWindowClass.compact;

  static bool isExpanded(BuildContext context) =>
      windowClassOf(context) == AppWindowClass.expanded;
}
