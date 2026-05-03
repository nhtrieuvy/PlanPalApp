import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/dtos/plan_activity.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/activity_providers.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

class ActivityDetailsDialog extends StatelessWidget {
  final PlanActivity activity;
  final bool canEdit;
  final ActivityRealtimeHighlight? realtimeHighlight;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ActivityDetailsDialog({
    super.key,
    required this.activity,
    this.canEdit = false,
    this.realtimeHighlight,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildActivityType(context),
                      if (realtimeHighlight != null) ...[
                        const SizedBox(height: 16),
                        _buildRealtimeNotice(context),
                      ],
                      const SizedBox(height: 16),
                      _buildDescription(context),
                      const SizedBox(height: 16),
                      _buildTimeInfo(context),
                      const SizedBox(height: 16),
                      _buildLocationSection(context),
                      const SizedBox(height: 16),
                      _buildCostInfo(context),
                      if (activity.notes != null && activity.notes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildNotes(context),
                      ],
                      const SizedBox(height: 16),
                      _buildStatusInfo(context),
                      const SizedBox(height: 16),
                      _buildVersionInfo(context),
                    ],
                  ),
                ),
              ),
            ),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getActivityIcon(activity.activityType),
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (activity.isCompleted)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      context.l10n.t('activity_details.completed'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityType(BuildContext context) {
    return _buildInfoCard(
      context: context,
      icon: Icons.category,
      title: context.l10n.t('activity_details.type'),
      content: Text(
        context.l10n.activityTypeLabel(activity.activityType),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      color: _getActivityTypeColor(activity.activityType),
    );
  }

  Widget _buildRealtimeNotice(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = Colors.amber;
    final fields = realtimeHighlight!.updatedFields
        .map((field) => context.l10n.activityFieldLabel(field))
        .join(', ');
    final updatedBy = realtimeHighlight!.updatedBy;
    final message = updatedBy == null || updatedBy.isEmpty
        ? context.l10n.t(
            'activity_collab.edited_fields',
            params: {
              'fields': fields.isEmpty ? context.l10n.t('common.edit') : fields,
            },
          )
        : context.l10n.t(
            'activity_collab.edited_by',
            params: {
              'user': updatedBy,
              'fields': fields.isEmpty ? context.l10n.t('common.edit') : fields,
            },
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(BuildContext context) {
    if (activity.description == null || activity.description!.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildInfoCard(
      context: context,
      icon: Icons.description,
      title: context.l10n.t('activity_details.description'),
      content: Text(activity.description!, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _buildTimeInfo(BuildContext context) {
    return _buildInfoCard(
      context: context,
      icon: Icons.access_time,
      title: context.l10n.t('activity_details.time'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activity.startTime != null)
            Row(
              children: [
                const Icon(Icons.play_arrow, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  context.l10n.t(
                    'activity_details.start',
                    params: {
                      'value': AppFormatters.fullDateTime(
                        context,
                        activity.startTime!,
                      ),
                    },
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          if (activity.endTime != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.stop, size: 16, color: Colors.red),
                const SizedBox(width: 4),
                Text(
                  context.l10n.t(
                    'activity_details.end',
                    params: {
                      'value': AppFormatters.fullDateTime(
                        context,
                        activity.endTime!,
                      ),
                    },
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
          if (activity.durationMinutes != null && activity.durationMinutes! > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.timer, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  context.l10n.t(
                    'activity_details.duration',
                    params: {
                      'value': activity.durationDisplay.isNotEmpty
                          ? activity.durationDisplay
                          : '${activity.durationMinutes}m',
                    },
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationSection(BuildContext context) {
    if (!activity.hasLocation) {
      return const SizedBox.shrink();
    }

    return _buildInfoCard(
      context: context,
      icon: Icons.location_on,
      title: context.l10n.t('activity_details.location'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activity.locationName != null && activity.locationName!.isNotEmpty)
            Text(
              activity.locationName!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          if (activity.locationAddress != null &&
              activity.locationAddress!.isNotEmpty &&
              activity.locationAddress != activity.locationName) ...[
            const SizedBox(height: 4),
            Text(
              activity.locationAddress!,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (activity.latitude != null && activity.longitude != null) ...[
            const SizedBox(height: 8),
            _buildMiniMap(context),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openInMaps,
                    icon: const Icon(Icons.map, size: 16),
                    label: Text(context.l10n.t('activity_details.open_map')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openDirections,
                    icon: const Icon(Icons.directions, size: 16),
                    label: Text(context.l10n.t('activity_details.directions')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      color: Colors.green,
    );
  }

  Widget _buildMiniMap(BuildContext context) {
    if (activity.latitude == null || activity.longitude == null) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Image.network(
              'https://maps.googleapis.com/maps/api/staticmap?'
              'center=${activity.latitude},${activity.longitude}&'
              'zoom=15&'
              'size=400x120&'
              'markers=color:red%7C${activity.latitude},${activity.longitude}&'
              'key=AIzaSyD1GIETwZj5CNGQtZR2CPqDCkCYLZ6SZrc',
              width: double.infinity,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map,
                        size: 32,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.t('activity_details.view_on_map'),
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${activity.latitude!.toStringAsFixed(6)}, ${activity.longitude!.toStringAsFixed(6)}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openInMaps,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostInfo(BuildContext context) {
    final hasCost = activity.estimatedCost != null && activity.estimatedCost! > 0;
    final valueColor = hasCost ? Colors.orange : Colors.green;
    return _buildInfoCard(
      context: context,
      icon: Icons.attach_money,
      title: context.l10n.t('activity_form.field_cost'),
      content: Text(
        hasCost
            ? AppFormatters.currency(
                context,
                amount: activity.estimatedCost!.toDouble(),
                currencyCode: 'VND',
              )
            : context.l10n.t('common.free'),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: valueColor,
        ),
      ),
      color: hasCost ? Colors.orange : Colors.green,
    );
  }

  Widget _buildNotes(BuildContext context) {
    return _buildInfoCard(
      context: context,
      icon: Icons.note_alt,
      title: context.l10n.t('activity_details.notes'),
      content: Text(activity.notes!, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _buildStatusInfo(BuildContext context) {
    final completed = activity.isCompleted;
    final statusColor = completed ? Colors.green : Colors.orange;
    return _buildInfoCard(
      context: context,
      icon: completed ? Icons.check_circle : Icons.radio_button_unchecked,
      title: context.l10n.t('activity_details.status'),
      content: Row(
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.pending,
            color: statusColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            completed
                ? context.l10n.t('activity_details.completed')
                : context.l10n.t('activity_details.not_completed'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: statusColor,
            ),
          ),
        ],
      ),
      color: completed ? Colors.green : Colors.orange,
    );
  }

  Widget _buildVersionInfo(BuildContext context) {
    return _buildInfoCard(
      context: context,
      icon: Icons.layers,
      title: context.l10n.t('activity_collab.version_label'),
      content: Text(
        'v${activity.version}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      color: Colors.blueGrey,
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Widget content,
    Color? color,
  }) {
    final cardColor = color ?? AppColors.primary;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cardColor.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cardColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cardColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: TextStyle(color: colorScheme.onSurface),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.t('activity_details.close')),
            ),
          ),
          if (canEdit && onEdit != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onEdit?.call();
                },
                icon: const Icon(Icons.edit, size: 16),
                label: Text(context.l10n.t('activity_details.edit')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
          if (canEdit && onDelete != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showDeleteConfirmation(context);
              },
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: context.l10n.t('activity_details.delete_tooltip'),
            ),
          ],
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('activity_details.delete_confirm_title')),
        content: Text(
          context.l10n.t(
            'activity_details.delete_confirm_message',
            params: {'title': activity.title},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('common.cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDelete?.call();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              context.l10n.t('common.delete'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInMaps() async {
    if (activity.latitude == null || activity.longitude == null) return;
    final url =
        'https://www.google.com/maps/search/?api=1&query=${activity.latitude},${activity.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openDirections() async {
    if (activity.latitude == null || activity.longitude == null) return;
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${activity.latitude},${activity.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  IconData _getActivityIcon(String activityType) {
    switch (activityType) {
      case 'eating':
        return Icons.restaurant;
      case 'resting':
        return Icons.hotel;
      case 'moving':
        return Icons.directions_car;
      case 'sightseeing':
        return Icons.camera_alt;
      case 'shopping':
        return Icons.shopping_bag;
      case 'entertainment':
        return Icons.movie;
      case 'event':
        return Icons.event;
      case 'sport':
        return Icons.sports;
      case 'study':
        return Icons.school;
      case 'work':
        return Icons.work;
      default:
        return Icons.place;
    }
  }

  Color _getActivityTypeColor(String activityType) {
    switch (activityType) {
      case 'eating':
        return Colors.orange;
      case 'resting':
        return Colors.blue;
      case 'moving':
        return Colors.purple;
      case 'sightseeing':
        return Colors.green;
      case 'shopping':
        return Colors.pink;
      case 'entertainment':
        return Colors.red;
      case 'event':
        return Colors.indigo;
      case 'sport':
        return Colors.teal;
      case 'study':
        return Colors.brown;
      case 'work':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
