import 'package:flutter/animation.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 48;
}

abstract final class AppRadius {
  static const double small = 8;
  static const double control = 12;
  static const double card = 16;
  static const double sheet = 24;
  static const double pill = 999;
}

abstract final class AppSize {
  static const double minimumTouchTarget = 44;
  static const double controlHeight = 48;
  static const double icon = 24;
}

abstract final class AppMotion {
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration emphasized = Duration(milliseconds: 300);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;
}
