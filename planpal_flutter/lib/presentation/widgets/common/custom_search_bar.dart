import 'package:flutter/material.dart';
// removed color_utils; use withAlpha directly
import 'package:google_fonts/google_fonts.dart';

class CustomSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final bool autofocus;

  const CustomSearchBar({
    super.key,
    required this.controller,
    this.hintText = 'Search...',
    this.onChanged,
    this.onClear,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withAlpha(50),
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        onChanged: onChanged,
        style: GoogleFonts.inter(
          fontSize: 16,
          color: theme.colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.inter(
            fontSize: 16,
            color: theme.colorScheme.onSurface.withAlpha(125),
          ),
          prefixIcon: prefixIcon != null
              ? Icon(
                  prefixIcon,
                  color: theme.colorScheme.onSurface.withAlpha(150),
                  size: 20,
                )
              : null,
          suffixIcon: _buildSuffixIcon(theme),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget? _buildSuffixIcon(ThemeData theme) {
    if (controller.text.isNotEmpty) {
      return IconButton(
        onPressed: () {
          controller.clear();
          onClear?.call();
          onChanged?.call('');
        },
        icon: Icon(
          Icons.clear,
          color: theme.colorScheme.onSurface.withAlpha(150),
          size: 20,
        ),
      );
    }
    return suffixIcon;
  }
}
