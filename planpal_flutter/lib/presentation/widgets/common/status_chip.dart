import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// A reusable status chip widget for displaying plan statuses, activity types, etc.
class StatusChip extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool outlined;
  final double? fontSize;
  final EdgeInsets? padding;

  const StatusChip({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.onTap,
    this.outlined = false,
    this.fontSize,
    this.padding,
  });

  /// Creates a status chip for plan statuses
  StatusChip.planStatus({
    super.key,
    required this.label,
    required String status,
    this.onTap,
    this.outlined = false,
    this.fontSize,
    this.padding,
  }) : backgroundColor = _getPlanStatusColor(status),
       textColor = _getPlanStatusTextColor(status),
       icon = _getPlanStatusIcon(status);

  /// Creates a status chip for activity types
  StatusChip.activityType({
    super.key,
    required this.label,
    required String activityType,
    this.onTap,
    this.outlined = false,
    this.fontSize,
    this.padding,
  }) : backgroundColor = _getActivityTypeColor(activityType),
       textColor = null,
       icon = _getActivityTypeIcon(activityType);

  /// Creates a success-styled chip
  const StatusChip.success({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.outlined = false,
    this.fontSize,
    this.padding,
  }) : backgroundColor = Colors.green,
       textColor = Colors.white;

  /// Creates an error-styled chip
  const StatusChip.error({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.outlined = false,
    this.fontSize,
    this.padding,
  }) : backgroundColor = Colors.red,
       textColor = Colors.white;

  /// Creates a warning-styled chip
  const StatusChip.warning({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.outlined = false,
    this.fontSize,
    this.padding,
  }) : backgroundColor = Colors.orange,
       textColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    final defaultBackgroundColor = backgroundColor ?? AppColors.primary;
    final defaultTextColor =
        textColor ?? (outlined ? defaultBackgroundColor : Colors.white);
    final defaultFontSize = fontSize ?? 12;
    final defaultPadding =
        padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4);

    Widget chip = Container(
      padding: defaultPadding,
      decoration: BoxDecoration(
        color: outlined
            ? Colors.transparent
            : defaultBackgroundColor.withValues(alpha: 0.1),
        border: outlined ? Border.all(color: defaultBackgroundColor) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: defaultFontSize + 2, color: defaultTextColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: defaultFontSize,
              color: defaultTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      chip = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: chip,
      );
    }

    return chip;
  }

  // Helper methods for plan status styling
  static Color _getPlanStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'upcoming':
        return Colors.blue;
      case 'ongoing':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return AppColors.primary;
    }
  }

  static Color _getPlanStatusTextColor(String status) {
    return Colors.white;
  }

  static IconData _getPlanStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'upcoming':
        return Icons.schedule;
      case 'ongoing':
        return Icons.play_arrow;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  // Helper methods for activity type styling
  static Color _getActivityTypeColor(String activityType) {
    switch (activityType.toLowerCase()) {
      case 'sightseeing':
        return Colors.blue;
      case 'dining':
        return Colors.orange;
      case 'accommodation':
        return Colors.purple;
      case 'transportation':
        return Colors.green;
      case 'entertainment':
        return Colors.pink;
      case 'shopping':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  static IconData _getActivityTypeIcon(String activityType) {
    switch (activityType.toLowerCase()) {
      case 'sightseeing':
        return Icons.camera_alt;
      case 'dining':
        return Icons.restaurant;
      case 'accommodation':
        return Icons.hotel;
      case 'transportation':
        return Icons.directions_car;
      case 'entertainment':
        return Icons.movie;
      case 'shopping':
        return Icons.shopping_bag;
      default:
        return Icons.event;
    }
  }
}
