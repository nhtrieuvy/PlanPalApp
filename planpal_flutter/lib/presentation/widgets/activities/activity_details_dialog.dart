import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/dtos/plan_activity.dart';
import '../../../core/theme/app_colors.dart';

class ActivityDetailsDialog extends StatelessWidget {
  final PlanActivity activity;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ActivityDetailsDialog({
    super.key,
    required this.activity,
    this.canEdit = false,
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
                      _buildActivityType(),
                      const SizedBox(height: 16),
                      _buildDescription(),
                      const SizedBox(height: 16),
                      _buildTimeInfo(),
                      const SizedBox(height: 16),
                      _buildLocationSection(context),
                      const SizedBox(height: 16),
                      // DEBUG: Hiển thị thông tin location để debug
                      const SizedBox(height: 16),
                      _buildCostInfo(),
                      if (activity.notes != null &&
                          activity.notes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildNotes(),
                      ],
                      const SizedBox(height: 16),
                      _buildStatusInfo(),
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
        gradient: LinearGradient(
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
                    child: const Text(
                      'Đã hoàn thành',
                      style: TextStyle(
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

  Widget _buildActivityType() {
    return _buildInfoCard(
      icon: Icons.category,
      title: 'Loại hoạt động',
      content: Text(
        activity.activityTypeDisplay.isNotEmpty
            ? activity.activityTypeDisplay
            : _getActivityTypeName(activity.activityType),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      color: _getActivityTypeColor(activity.activityType),
    );
  }

  Widget _buildDescription() {
    if (activity.description == null || activity.description!.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildInfoCard(
      icon: Icons.description,
      title: 'Mô tả',
      content: Text(
        activity.description!,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildTimeInfo() {
    return _buildInfoCard(
      icon: Icons.access_time,
      title: 'Thời gian',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activity.startTime != null)
            Row(
              children: [
                const Icon(Icons.play_arrow, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'Bắt đầu: ${DateFormat('dd/MM/yyyy HH:mm').format(activity.startTime!)}',
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
                  'Kết thúc: ${DateFormat('dd/MM/yyyy HH:mm').format(activity.endTime!)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
          if (activity.durationMinutes != null &&
              activity.durationMinutes! > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.timer, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  'Thời gian: ${activity.durationDisplay.isNotEmpty ? activity.durationDisplay : "${activity.durationMinutes}m"}',
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
    // Show location section when the activity has any location information.
    if (!activity.hasLocation) {
      return const SizedBox.shrink();
    }
    return _buildInfoCard(
      icon: Icons.location_on,
      title: 'Vị trí',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activity.locationName != null &&
              activity.locationName!.isNotEmpty)
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
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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
                    onPressed: () => _openInMaps(),
                    icon: const Icon(Icons.map, size: 16),
                    label: const Text('Mở bản đồ'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openDirections(),
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Chỉ đường'),
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

    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            // Static map using Google Static Maps API
            Image.network(
              'https://maps.googleapis.com/maps/api/staticmap?'
              'center=${activity.latitude},${activity.longitude}&'
              'zoom=15&'
              'size=400x120&'
              'markers=color:red%7C${activity.latitude},${activity.longitude}&'
              'key=AIzaSyD1GIETwZj5CNGQtZR2CPqDCkCYLZ6SZrc', // Replace with actual API key
              width: double.infinity,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[100],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map, size: 32, color: Colors.grey[400]),
                      const SizedBox(height: 4),
                      Text(
                        'Xem trên bản đồ',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      Text(
                        '${activity.latitude!.toStringAsFixed(6)}, ${activity.longitude!.toStringAsFixed(6)}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 10),
                      ),
                    ],
                  ),
                );
              },
            ),
            // Overlay for interaction
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openInMaps(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostInfo() {
    return _buildInfoCard(
      icon: Icons.attach_money,
      title: 'Chi phí dự kiến',
      content: Text(
        activity.estimatedCost != null && activity.estimatedCost! > 0
            ? '${NumberFormat('#,###').format(activity.estimatedCost)} VND'
            : 'Miễn phí',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: activity.estimatedCost != null && activity.estimatedCost! > 0
              ? Colors.orange[700]
              : Colors.green[700],
        ),
      ),
      color: activity.estimatedCost != null && activity.estimatedCost! > 0
          ? Colors.orange
          : Colors.green,
    );
  }

  Widget _buildNotes() {
    return _buildInfoCard(
      icon: Icons.note_alt,
      title: 'Ghi chú',
      content: Text(activity.notes!, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _buildStatusInfo() {
    return _buildInfoCard(
      icon: activity.isCompleted
          ? Icons.check_circle
          : Icons.radio_button_unchecked,
      title: 'Trạng thái',
      content: Row(
        children: [
          Icon(
            activity.isCompleted ? Icons.check_circle : Icons.pending,
            color: activity.isCompleted ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            activity.isCompleted ? 'Đã hoàn thành' : 'Chưa hoàn thành',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: activity.isCompleted
                  ? Colors.green[700]
                  : Colors.orange[700],
            ),
          ),
        ],
      ),
      color: activity.isCompleted ? Colors.green : Colors.orange,
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required Widget content,
    Color? color,
  }) {
    final cardColor = color ?? AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardColor.withValues(alpha: 0.2), width: 1),
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
          content,
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
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
              child: const Text('Đóng'),
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
                label: const Text('Chỉnh sửa'),
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
              tooltip: 'Xóa hoạt động',
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
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Bạn có chắc chắn muốn xóa hoạt động "${activity.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDelete?.call();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openInMaps() async {
    if (activity.latitude != null && activity.longitude != null) {
      final url =
          'https://www.google.com/maps/search/?api=1&query=${activity.latitude},${activity.longitude}';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    }
  }

  void _openDirections() async {
    if (activity.latitude != null && activity.longitude != null) {
      final url =
          'https://www.google.com/maps/dir/?api=1&destination=${activity.latitude},${activity.longitude}';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
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

  String _getActivityTypeName(String activityType) {
    switch (activityType) {
      case 'eating':
        return 'Ăn uống';
      case 'resting':
        return 'Nghỉ ngơi';
      case 'moving':
        return 'Di chuyển';
      case 'sightseeing':
        return 'Tham quan';
      case 'shopping':
        return 'Mua sắm';
      case 'entertainment':
        return 'Giải trí';
      case 'event':
        return 'Sự kiện';
      case 'sport':
        return 'Thể thao';
      case 'study':
        return 'Học tập';
      case 'work':
        return 'Công việc';
      default:
        return 'Khác';
    }
  }
}
