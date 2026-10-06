import 'package:flutter/material.dart';

@immutable
class PlanPalSemanticColors extends ThemeExtension<PlanPalSemanticColors> {
  const PlanPalSemanticColors({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceInteractive,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.brandPrimary,
    required this.brandSecondary,
    required this.brandAccent,
    required this.borderDefault,
    required this.borderStrong,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceInteractive;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color brandPrimary;
  final Color brandSecondary;
  final Color brandAccent;
  final Color borderDefault;
  final Color borderStrong;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  static const light = PlanPalSemanticColors(
    backgroundPrimary: Color(0xFFF7F4ED),
    backgroundSecondary: Color(0xFFEFE9DD),
    surface: Color(0xFFFFFDF8),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceInteractive: Color(0xFFE4F3EF),
    textPrimary: Color(0xFF172724),
    textSecondary: Color(0xFF435651),
    textMuted: Color(0xFF667772),
    brandPrimary: Color(0xFF0B6B62),
    brandSecondary: Color(0xFF287E9A),
    brandAccent: Color(0xFFF47A5A),
    borderDefault: Color(0xFFD7DDD8),
    borderStrong: Color(0xFFA8B6B0),
    success: Color(0xFF2B8A67),
    warning: Color(0xFFD68A22),
    danger: Color(0xFFC94F4F),
    info: Color(0xFF367FA3),
  );

  static const dark = PlanPalSemanticColors(
    backgroundPrimary: Color(0xFF081A19),
    backgroundSecondary: Color(0xFF0D2422),
    surface: Color(0xFF122C29),
    surfaceRaised: Color(0xFF193632),
    surfaceInteractive: Color(0xFF20423D),
    textPrimary: Color(0xFFF2F5EF),
    textSecondary: Color(0xFFC5D2CD),
    textMuted: Color(0xFF95AAA3),
    brandPrimary: Color(0xFF7DD6C5),
    brandSecondary: Color(0xFF8BC8DA),
    brandAccent: Color(0xFFFF9B82),
    borderDefault: Color(0xFF31524D),
    borderStrong: Color(0xFF58756E),
    success: Color(0xFF72D0A9),
    warning: Color(0xFFF3B865),
    danger: Color(0xFFFFA8A8),
    info: Color(0xFF8BC8DA),
  );

  @override
  PlanPalSemanticColors copyWith({
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceInteractive,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? brandPrimary,
    Color? brandSecondary,
    Color? brandAccent,
    Color? borderDefault,
    Color? borderStrong,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
  }) => PlanPalSemanticColors(
    backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
    backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceInteractive: surfaceInteractive ?? this.surfaceInteractive,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    brandPrimary: brandPrimary ?? this.brandPrimary,
    brandSecondary: brandSecondary ?? this.brandSecondary,
    brandAccent: brandAccent ?? this.brandAccent,
    borderDefault: borderDefault ?? this.borderDefault,
    borderStrong: borderStrong ?? this.borderStrong,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    info: info ?? this.info,
  );

  @override
  PlanPalSemanticColors lerp(covariant PlanPalSemanticColors? other, double t) {
    if (other == null) return this;
    return PlanPalSemanticColors(
      backgroundPrimary: Color.lerp(
        backgroundPrimary,
        other.backgroundPrimary,
        t,
      )!,
      backgroundSecondary: Color.lerp(
        backgroundSecondary,
        other.backgroundSecondary,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceInteractive: Color.lerp(
        surfaceInteractive,
        other.surfaceInteractive,
        t,
      )!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t)!,
      brandSecondary: Color.lerp(brandSecondary, other.brandSecondary, t)!,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

extension PlanPalThemeContext on BuildContext {
  PlanPalSemanticColors get semanticColors =>
      Theme.of(this).extension<PlanPalSemanticColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? PlanPalSemanticColors.dark
          : PlanPalSemanticColors.light);
}
