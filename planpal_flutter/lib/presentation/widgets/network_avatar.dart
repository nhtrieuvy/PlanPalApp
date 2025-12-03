import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';

/// A reusable avatar widget that handles network images with fallback to initials
class NetworkAvatar extends StatelessWidget {
  final String? imageUrl;
  final String initials;
  final double size;
  final Color? backgroundColor;
  final Color? textColor;
  final double? fontSize;
  final VoidCallback? onTap;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;

  const NetworkAvatar({
    super.key,
    this.imageUrl,
    required this.initials,
    this.size = 48,
    this.backgroundColor,
    this.textColor,
    this.fontSize,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
  });

  /// Creates a small avatar (32px) for list items
  const NetworkAvatar.small({
    super.key,
    this.imageUrl,
    required this.initials,
    this.backgroundColor,
    this.textColor,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
  }) : size = 32,
       fontSize = 14;

  /// Creates a medium avatar (48px) for cards
  const NetworkAvatar.medium({
    super.key,
    this.imageUrl,
    required this.initials,
    this.backgroundColor,
    this.textColor,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
  }) : size = 48,
       fontSize = 16;

  /// Creates a large avatar (80px) for profiles
  const NetworkAvatar.large({
    super.key,
    this.imageUrl,
    required this.initials,
    this.backgroundColor,
    this.textColor,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
  }) : size = 80,
       fontSize = 24;

  @override
  Widget build(BuildContext context) {
    final defaultBackgroundColor =
        backgroundColor ?? AppColors.primary.withValues(alpha: 0.1);
    final defaultTextColor = textColor ?? AppColors.primary;
    final defaultFontSize = fontSize ?? (size * 0.4);

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: defaultBackgroundColor,
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(
                color: borderColor ?? AppColors.primary,
                width: borderWidth,
              )
            : null,
      ),
      child: ClipOval(
        child: _buildAvatarContent(defaultTextColor, defaultFontSize),
      ),
    );

    if (onTap != null) {
      avatar = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: avatar,
      );
    }

    return avatar;
  }

  Widget _buildAvatarContent(Color textColor, double fontSize) {
    final hasValidImage = imageUrl != null && imageUrl!.isNotEmpty;

    if (hasValidImage) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: size,
          height: size,
          color: Colors.grey[200],
          child: Center(
            child: SizedBox(
              width: size * 0.3,
              height: size * 0.3,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) =>
            _buildInitialsWidget(textColor, fontSize),
      );
    }

    return _buildInitialsWidget(textColor, fontSize);
  }

  Widget _buildInitialsWidget(Color textColor, double fontSize) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }
}
