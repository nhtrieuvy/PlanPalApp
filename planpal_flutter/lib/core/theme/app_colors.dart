import 'package:flutter/material.dart';

@immutable
class AvatarPalette {
  const AvatarPalette({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

class AppColors {
  static const Color deepOcean = Color(0xFF081A19);
  static const Color oceanTeal = Color(0xFF0B6B62);
  static const Color journeyMint = Color(0xFFA9DED2);
  static const Color horizonBlue = Color(0xFF287E9A);
  static const Color sunsetCoral = Color(0xFFF47A5A);
  static const Color warmSand = Color(0xFFF4F0E7);
  static const Color warmWhite = Color(0xFFFFFDF8);
  static const Color ink = Color(0xFF172724);

  // Journey Green anchors planning and trust. Coral is reserved for
  // discovery and high-attention travel moments, never generic decoration.
  static const Color primary = oceanTeal;
  static const Color primaryDark = Color(0xFF07534D);
  static const Color primaryLight = Color(0xFF7DD6C5);

  static const Color secondary = horizonBlue;
  static const Color secondaryDark = Color(0xFF1C6177);
  static const Color secondaryLight = Color(0xFF8BC8DA);

  static const Color accent = sunsetCoral;
  static const Color accentDark = Color(0xFFC9573E);
  static const Color accentLight = Color(0xFFFFC2B2);

  // Shared neutral scale for icons, metadata and disabled states.
  static const Color neutral400 = Color(0xFF93A19D);
  static const Color neutral500 = Color(0xFF74827E);
  static const Color neutral600 = Color(0xFF5A6864);
  static const Color neutral700 = Color(0xFF3F504C);

  // Light Theme Colors
  static const Color lightBackground = Color(0xFFF7F4ED);
  static const Color lightSurface = warmWhite;
  static const Color lightSurfaceVariant = Color(0xFFEAF0EC);
  static const Color lightOnBackground = ink;
  static const Color lightOnSurface = Color(0xFF20312E);
  static const Color lightOnSurfaceVariant = Color(0xFF53645F);
  static const Color lightOutline = Color(0xFFD7DDD8);

  // Dark Theme Colors
  static const Color darkBackground = deepOcean;
  static const Color darkSurface = Color(0xFF122C29);
  static const Color darkSurfaceVariant = Color(0xFF20423D);
  static const Color darkOnBackground = Color(0xFFF2F5EF);
  static const Color darkOnSurface = Color(0xFFE2EAE5);
  static const Color darkOnSurfaceVariant = Color(0xFFADC1BA);
  static const Color darkOutline = Color(0xFF31524D);

  // Status Colors
  static const Color success = Color(0xFF2B8A67);
  static const Color warning = Color(0xFFD68A22);
  static const Color error = Color(0xFFC94F4F);
  static const Color info = Color(0xFF367FA3);

  // Gradient Colors
  static const List<Color> primaryGradient = [
    Color(0xFF07534D),
    Color(0xFF0B6B62),
    Color(0xFF287E9A),
  ];

  static const List<Color> secondaryGradient = [
    Color(0xFF287E9A),
    Color(0xFF5DA8B6),
  ];

  static const List<Color> successGradient = [
    Color(0xFF2B8A67),
    Color(0xFF0B6B62),
  ];

  // Shadow Colors
  static const Color lightShadow = Color(0x1A000000);
  static const Color darkShadow = Color(0x40000000);

  // Card Colors for different categories
  static const List<Color> cardColors = [
    Color(0xFF0B6B62),
    Color(0xFF287E9A),
    Color(0xFFF47A5A),
    Color(0xFFD68A22),
    Color(0xFF557C67),
    Color(0xFF8A6F56),
  ];

  // Get color by index for consistent coloring
  static Color getCardColor(int index) {
    return cardColors[index % cardColors.length];
  }

  /// Returns a stable, theme-aware color pair for generated avatars.
  static AvatarPalette avatarPalette(String seed, Brightness brightness) {
    final normalizedSeed = seed.trim().toLowerCase();
    var hash = 0;
    for (final codeUnit in normalizedSeed.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }

    final base = getCardColor(hash);
    if (brightness == Brightness.dark) {
      return AvatarPalette(
        background: Color.alphaBlend(base.withValues(alpha: 0.24), darkSurface),
        foreground: Color.lerp(base, Colors.white, 0.48)!,
      );
    }

    return AvatarPalette(
      background: Color.alphaBlend(base.withValues(alpha: 0.11), lightSurface),
      foreground: base,
    );
  }
}
