import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';

/// A reusable cover image header widget for groups, plans, and profiles
class CoverImageHeader extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final double height;
  final Color? overlayColor;
  final double overlayOpacity;
  final Widget? leadingWidget;
  final List<Widget>? actions;
  final VoidCallback? onImageTap;
  final IconData? placeholderIcon;

  const CoverImageHeader({
    super.key,
    this.imageUrl,
    required this.title,
    this.subtitle,
    this.height = 200,
    this.overlayColor,
    this.overlayOpacity = 0.4,
    this.leadingWidget,
    this.actions,
    this.onImageTap,
    this.placeholderIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultOverlayColor = overlayColor ?? Colors.black;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          // Background image or placeholder
          _buildBackground(),

          // Dark overlay for text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  defaultOverlayColor.withValues(alpha: overlayOpacity * 0.3),
                  defaultOverlayColor.withValues(alpha: overlayOpacity),
                ],
              ),
            ),
          ),

          // Content overlay
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row with leading widget and actions
                    Row(
                      children: [
                        if (leadingWidget != null) leadingWidget!,
                        const Spacer(),
                        if (actions != null) ...actions!,
                      ],
                    ),

                    const Spacer(),

                    // Title and subtitle at bottom
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tap detector for image editing
          if (onImageTap != null)
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onImageTap,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    final hasValidImage = imageUrl != null && imageUrl!.isNotEmpty;

    if (hasValidImage) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Colors.grey[200],
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.1),
      child: Center(
        child: Icon(
          placeholderIcon ?? Icons.image,
          size: 64,
          color: AppColors.primary.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
