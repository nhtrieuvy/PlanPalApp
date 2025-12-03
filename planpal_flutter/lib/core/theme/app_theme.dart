import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static const double borderRadius = 16.0;
  static const double cardElevation = 4.0;
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;

  // Light Theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.lightSurface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.lightOnSurface,
      ),

      // Typography
      textTheme: _buildTextTheme(Brightness.light),

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        foregroundColor: AppColors.lightOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.lightOnSurface,
        ),
        systemOverlayStyle: _lightStatusBar,
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        shadowColor: AppColors.lightShadow,
      ),

      // Button Themes
      elevatedButtonTheme: _buildElevatedButtonTheme(Brightness.light),
      outlinedButtonTheme: _buildOutlinedButtonTheme(Brightness.light),
      textButtonTheme: _buildTextButtonTheme(Brightness.light),

      // Input Decoration
      inputDecorationTheme: _buildInputDecorationTheme(Brightness.light),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.lightOnSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: AppColors.lightSurfaceVariant,
        thickness: 1,
        space: 1,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.lightSurface,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius * 1.5),
        ),
      ),
    );
  }

  // Dark Theme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        secondary: AppColors.secondaryLight,
        surface: AppColors.darkSurface,
        onPrimary: AppColors.darkBackground,
        onSecondary: AppColors.darkBackground,
        onSurface: AppColors.darkOnSurface,
      ),

      // Typography
      textTheme: _buildTextTheme(Brightness.dark),

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.darkOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.darkOnSurface,
        ),
        systemOverlayStyle: _darkStatusBar,
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        shadowColor: AppColors.darkShadow,
      ),

      // Button Themes
      elevatedButtonTheme: _buildElevatedButtonTheme(Brightness.dark),
      outlinedButtonTheme: _buildOutlinedButtonTheme(Brightness.dark),
      textButtonTheme: _buildTextButtonTheme(Brightness.dark),

      // Input Decoration
      inputDecorationTheme: _buildInputDecorationTheme(Brightness.dark),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.darkBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.darkOnSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: AppColors.darkSurfaceVariant,
        thickness: 1,
        space: 1,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkSurface,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius * 1.5),
        ),
      ),
    );
  }

  // Helper Methods
  static TextTheme _buildTextTheme(Brightness brightness) {
    final Color textColor = brightness == Brightness.light
        ? AppColors.lightOnBackground
        : AppColors.darkOnBackground;
    final Color textColorVariant = brightness == Brightness.light
        ? AppColors.lightOnSurfaceVariant
        : AppColors.darkOnSurfaceVariant;

    return GoogleFonts.interTextTheme().copyWith(
      headlineLarge: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: textColor,
        height: 1.2,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: textColor,
        height: 1.2,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.3,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.3,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.4,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textColor,
        height: 1.4,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: textColor,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: textColor,
        height: 1.5,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: textColorVariant,
        height: 1.4,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textColor,
        height: 1.3,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textColor,
        height: 1.3,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: textColorVariant,
        height: 1.3,
      ),
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme(
    Brightness brightness,
  ) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonTheme(
    Brightness brightness,
  ) {
    final Color borderColor = brightness == Brightness.light
        ? AppColors.primary
        : AppColors.primaryLight;

    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: borderColor,
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  static TextButtonThemeData _buildTextButtonTheme(Brightness brightness) {
    final Color textColor = brightness == Brightness.light
        ? AppColors.primary
        : AppColors.primaryLight;

    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  static InputDecorationTheme _buildInputDecorationTheme(
    Brightness brightness,
  ) {
    final Color fillColor = brightness == Brightness.light
        ? AppColors.lightSurfaceVariant
        : AppColors.darkSurfaceVariant;
    final Color borderColor = brightness == Brightness.light
        ? AppColors.primary
        : AppColors.primaryLight;
    final Color hintColor = brightness == Brightness.light
        ? AppColors.lightOnSurfaceVariant
        : AppColors.darkOnSurfaceVariant;

    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: GoogleFonts.inter(color: hintColor, fontSize: 14),
    );
  }

  // Status Bar Styles
  static const _lightStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static const _darkStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
}
