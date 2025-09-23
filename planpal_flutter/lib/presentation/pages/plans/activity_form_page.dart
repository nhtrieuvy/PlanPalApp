import 'package:flutter/material.dart';
// removed color_utils; use withAlpha directly
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/dtos/plan_activity_requests.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/presentation/pages/location/location_picker_page.dart';

class ActivityFormPage extends StatefulWidget {
  final String planId;
  final String planTitle;

  const ActivityFormPage({
    super.key,
    required this.planId,
    required this.planTitle,
  });

  @override
  State<ActivityFormPage> createState() => _ActivityFormPageState();
}

class _ActivityFormPageState extends State<ActivityFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final PlanRepository _repo;

  // Form controllers
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _estimatedCostCtrl;
  late final TextEditingController _notesCtrl;

  // Location data
  double? _latitude;
  double? _longitude;
  String? _locationName;
  String? _locationAddress;

  // Form data
  DateTime? _startTime;
  DateTime? _endTime;
  String _activityType = 'eating';
  bool _isSubmitting = false;

  final List<Map<String, String>> _activityTypes = [
    {'value': 'eating', 'label': 'Ăn uống'},
    {'value': 'resting', 'label': 'Nghỉ ngơi'},
    {'value': 'moving', 'label': 'Di chuyển'},
    {'value': 'sightseeing', 'label': 'Tham quan'},
    {'value': 'shopping', 'label': 'Mua sắm'},
    {'value': 'entertainment', 'label': 'Giải trí'},
    {'value': 'event', 'label': 'Sự kiện'},
    {'value': 'sport', 'label': 'Thể thao'},
    {'value': 'study', 'label': 'Học tập'},
    {'value': 'work', 'label': 'Công việc'},
    {'value': 'other', 'label': 'Khác'},
  ];

  @override
  void initState() {
    super.initState();
    _repo = PlanRepository(context.read<AuthProvider>());
    _titleCtrl = TextEditingController();
    _descriptionCtrl = TextEditingController();
    _estimatedCostCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _estimatedCostCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPlanInfoCard(),
              const SizedBox(height: 24),
              _buildTitleField(),
              const SizedBox(height: 16),
              _buildActivityTypeDropdown(),
              const SizedBox(height: 16),
              _buildDescriptionField(),
              const SizedBox(height: 16),
              _buildTimeSection(),
              const SizedBox(height: 16),
              _buildLocationSection(),
              const SizedBox(height: 16),
              _buildEstimatedCostField(),
              const SizedBox(height: 16),
              _buildNotesField(),
              const SizedBox(height: 32),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Tạo hoạt động mới'),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    );
  }

  Widget _buildPlanInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.event_note, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kế hoạch:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    widget.planTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleCtrl,
      decoration: const InputDecoration(
        labelText: 'Tên hoạt động *',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.title),
      ),
      validator: (value) =>
          value?.trim().isEmpty == true ? 'Vui lòng nhập tên hoạt động' : null,
    );
  }

  Widget _buildActivityTypeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _activityType,
      decoration: const InputDecoration(
        labelText: 'Loại hoạt động',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.category),
      ),
      items: _activityTypes.map((type) {
        return DropdownMenuItem(
          value: type['value'],
          child: Text(type['label']!),
        );
      }).toList(),
      onChanged: (value) => setState(() => _activityType = value!),
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionCtrl,
      decoration: const InputDecoration(
        labelText: 'Mô tả',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.description),
      ),
      maxLines: 3,
    );
  }

  Widget _buildTimeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Thời gian',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildTimeField('Bắt đầu *', _startTime, _pickStartTime),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTimeField('Kết thúc *', _endTime, _pickEndTime),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeField(String label, DateTime? time, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              time != null
                  ? DateFormat('dd/MM/yyyy HH:mm').format(time)
                  : 'Chọn thời gian',
              style: TextStyle(
                fontSize: 16,
                color: time != null ? Colors.black : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Địa điểm',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildLocationMap(),
      ],
    );
  }

  Widget _buildLocationMap() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _latitude != null && _longitude != null
            ? _buildMapWithLocation()
            : _buildLocationPlaceholder(),
      ),
    );
  }

  Widget _buildMapWithLocation() {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_latitude!, _longitude!),
            zoom: 16,
          ),
          markers: {
            Marker(
              markerId: const MarkerId('selected_location'),
              position: LatLng(_latitude!, _longitude!),
              infoWindow: InfoWindow(
                title: _locationName ?? 'Vị trí đã chọn',
                snippet: _locationAddress,
              ),
            ),
          },
          onTap: (_) => _showLocationPicker(),
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          tiltGesturesEnabled: false,
          rotateGesturesEnabled: false,
        ),
        _buildLocationInfoOverlay(),
      ],
    );
  }

  Widget _buildLocationPlaceholder() {
    return Material(
      color: Colors.grey.shade100,
      child: InkWell(
        onTap: _showLocationPicker,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_location_alt,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 8),
              Text(
                'Chạm để chọn vị trí',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationInfoOverlay() {
    return Positioned(
      bottom: 8,
      left: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(225),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _locationName ?? 'Vị trí đã chọn',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_locationAddress != null)
              Text(
                _locationAddress!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstimatedCostField() {
    return TextFormField(
      controller: _estimatedCostCtrl,
      decoration: const InputDecoration(
        labelText: 'Chi phí dự kiến (VND)',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.attach_money),
      ),
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesCtrl,
      decoration: const InputDecoration(
        labelText: 'Ghi chú',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.note),
      ),
      maxLines: 2,
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSubmitting
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Đang tạo...'),
                ],
              )
            : const Text(
                'Tạo hoạt động',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Future<void> _pickStartTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (time != null && mounted) {
        setState(() {
          _startTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _pickEndTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: _startTime != null
            ? TimeOfDay.fromDateTime(_startTime!.add(const Duration(hours: 1)))
            : TimeOfDay.now(),
      );

      if (time != null && mounted) {
        setState(() {
          _endTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  void _showLocationPicker() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => LocationPickerPage(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          initialLocationName: _locationName,
        ),
      ),
    );

    if (result != null) {
      _handleLocationResult(result);
    }
  }

  void _handleLocationResult(Map<String, dynamic> data) {
    setState(() {
      _latitude = (data['latitude'] as num?)?.toDouble();
      _longitude = (data['longitude'] as num?)?.toDouble();
      _locationName =
          data['location_name']?.toString() ?? data['address']?.toString();
      _locationAddress =
          data['location_address']?.toString() ?? data['address']?.toString();
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    // Check authentication first
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isLoggedIn) {
      _showError('Bạn cần đăng nhập để tạo hoạt động.');
      return;
    }

    if (_startTime == null || _endTime == null) {
      _showError('Vui lòng chọn thời gian bắt đầu và kết thúc');
      return;
    }

    if (_endTime!.isBefore(_startTime!)) {
      _showError('Thời gian kết thúc phải sau thời gian bắt đầu');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final request = CreatePlanActivityRequest(
        planId: widget.planId,
        title: _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        activityType: _activityType,
        startTime: _startTime!,
        endTime: _endTime!,
        latitude: _latitude,
        longitude: _longitude,
        locationName: _locationName,
        locationAddress: _locationAddress,
        estimatedCost: _estimatedCostCtrl.text.trim().isNotEmpty
            ? double.tryParse(_estimatedCostCtrl.text.trim())
            : null,
        notes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
      );

      await _repo.createActivity(request);

      if (mounted) {
        _showSuccess('Tạo hoạt động thành công!');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Không thể tạo hoạt động. Vui lòng thử lại.';

        // Extract detailed error message
        if (e.toString().contains('401')) {
          errorMessage = 'Bạn cần đăng nhập để tạo hoạt động.';
        } else if (e.toString().contains('403')) {
          errorMessage = 'Bạn không có quyền tạo hoạt động cho kế hoạch này.';
        } else if (e.toString().contains('400')) {
          errorMessage = 'Dữ liệu không hợp lệ. Vui lòng kiểm tra lại.';
        }

        _showError('$errorMessage\nLỗi chi tiết: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
}
