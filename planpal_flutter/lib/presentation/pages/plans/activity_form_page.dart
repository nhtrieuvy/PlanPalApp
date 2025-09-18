import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/dtos/plan_requests.dart';
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
  String _activityType = 'sightseeing';
  bool _isSubmitting = false;

  final List<Map<String, String>> _activityTypes = [
    {'value': 'sightseeing', 'label': 'Tham quan'},
    {'value': 'dining', 'label': 'Ăn uống'},
    {'value': 'accommodation', 'label': 'Nghỉ ngơi'},
    {'value': 'transportation', 'label': 'Di chuyển'},
    {'value': 'entertainment', 'label': 'Giải trí'},
    {'value': 'shopping', 'label': 'Mua sắm'},
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
      appBar: AppBar(
        title: const Text('Tạo hoạt động mới'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Plan info
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_note,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Kế hoạch:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
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
              ),

              const SizedBox(height: 24),

              // Title field
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên hoạt động *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập tên hoạt động';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Activity type
              DropdownButtonFormField<String>(
                value: _activityType,
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
                onChanged: (value) {
                  setState(() {
                    _activityType = value!;
                  });
                },
              ),

              const SizedBox(height: 16),

              // Description field
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mô tả',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 16),

              // Time section
              const Text(
                'Thời gian',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickStartTime,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bắt đầu *',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _startTime != null
                                  ? DateFormat(
                                      'dd/MM/yyyy HH:mm',
                                    ).format(_startTime!)
                                  : 'Chọn thời gian',
                              style: TextStyle(
                                fontSize: 16,
                                color: _startTime != null
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _pickEndTime,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Kết thúc *',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _endTime != null
                                  ? DateFormat(
                                      'dd/MM/yyyy HH:mm',
                                    ).format(_endTime!)
                                  : 'Chọn thời gian',
                              style: TextStyle(
                                fontSize: 16,
                                color: _endTime != null
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Location section with minimap
              const Text(
                'Địa điểm',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              // Minimap for location selection
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      // Google Map or placeholder
                      _latitude != null && _longitude != null
                          ? GoogleMap(
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
                            )
                          : Container(
                              width: double.infinity,
                              height: double.infinity,
                              color: Colors.grey.shade100,
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
                                  const SizedBox(height: 4),
                                  Text(
                                    'Sử dụng bản đồ để chọn vị trí chính xác',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                      // Location info overlay (only when location is selected)
                      if (_latitude != null && _longitude != null)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
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
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_locationAddress != null)
                                  Text(
                                    _locationAddress!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'Chạm để thay đổi vị trí',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Tap overlay for when no location is selected
                      if (_latitude == null || _longitude == null)
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _showLocationPicker,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Estimated cost
              TextFormField(
                controller: _estimatedCostCtrl,
                decoration: const InputDecoration(
                  labelText: 'Chi phí dự kiến (VND)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 16),

              // Notes
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 32),

              // Submit button
              SizedBox(
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Đang tạo...'),
                          ],
                        )
                      : const Text(
                          'Tạo hoạt động',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
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
    // Show dialog to choose between map view or manual input
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Location Method'),
        content: const Text('Choose how you want to select the location:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'map'),
            child: const Text('Interactive Map'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: const Text('Manual Input'),
          ),
        ],
      ),
    );

    if (choice == null) return;

    Map<String, dynamic>? result;

    if (choice == 'map') {
      // Try Google Maps first
      try {
        result = await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (context) => LocationPickerPage(
              initialLatitude: _latitude,
              initialLongitude: _longitude,
              initialLocationName: _locationName,
            ),
          ),
        );
      } catch (e) {
        // If Google Maps fails, show error and fallback to manual
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Map error: $e. Using manual input.')),
          );
          result = await Navigator.of(context).push<Map<String, dynamic>>(
            MaterialPageRoute(
              builder: (context) => LocationPickerPage(
                initialLatitude: _latitude,
                initialLongitude: _longitude,
                initialLocationName: _locationName,
              ),
            ),
          );
        }
      }
    } else {
      // Manual input - now use the same LocationPickerPage
      result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (context) => LocationPickerPage(
            initialLatitude: _latitude,
            initialLongitude: _longitude,
            initialLocationName: _locationName,
          ),
        ),
      );
    }

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

    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn thời gian bắt đầu và kết thúc'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_endTime!.isBefore(_startTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thời gian kết thúc phải sau thời gian bắt đầu'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final request = CreateActivityRequest(
        planId: widget.planId,
        title: _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim().isNotEmpty
            ? _descriptionCtrl.text.trim()
            : '',
        activityType: _activityType,
        startTime: _startTime!.toIso8601String(),
        endTime: _endTime!.toIso8601String(),
        locationName: _locationName,
        locationAddress: _locationAddress,
        latitude: _latitude,
        longitude: _longitude,
        estimatedCost: _estimatedCostCtrl.text.trim().isNotEmpty
            ? double.tryParse(_estimatedCostCtrl.text.trim())
            : null,
        notes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
      );

      await _repo.createActivity(request);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tạo hoạt động thành công!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tạo hoạt động: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
