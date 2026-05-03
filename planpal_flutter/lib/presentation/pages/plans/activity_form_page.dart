import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:planpal_flutter/core/dtos/activity_conflict.dart';
import 'package:planpal_flutter/core/dtos/plan_activity.dart';
import 'package:planpal_flutter/core/dtos/plan_activity_requests.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/presentation/pages/location/location_picker_page.dart';

class ActivityFormPage extends ConsumerStatefulWidget {
  final String planId;
  final String planTitle;
  final PlanActivity? initialActivity;

  const ActivityFormPage({
    super.key,
    required this.planId,
    required this.planTitle,
    this.initialActivity,
  });

  bool get isEdit => initialActivity != null;

  @override
  ConsumerState<ActivityFormPage> createState() => _ActivityFormPageState();
}

class _ActivityFormPageState extends ConsumerState<ActivityFormPage> {
  final _formKey = GlobalKey<FormState>();
  PlanRepository get _repo => ref.read(planRepositoryProvider);

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _estimatedCostCtrl;
  late final TextEditingController _notesCtrl;

  double? _latitude;
  double? _longitude;
  String? _locationName;
  String? _locationAddress;
  String? _goongPlaceId;

  DateTime? _startTime;
  DateTime? _endTime;
  String _activityType = 'eating';
  bool _isSubmitting = false;
  late int _baseVersion;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialActivity;
    _titleCtrl = TextEditingController(text: initial?.title ?? '');
    _descriptionCtrl = TextEditingController(text: initial?.description ?? '');
    _estimatedCostCtrl = TextEditingController(
      text: initial?.estimatedCost?.toStringAsFixed(0) ?? '',
    );
    _notesCtrl = TextEditingController(text: initial?.notes ?? '');

    _latitude = initial?.latitude;
    _longitude = initial?.longitude;
    _locationName = initial?.locationName;
    _locationAddress = initial?.locationAddress;
    _goongPlaceId = initial?.goongPlaceId;
    _startTime = initial?.startTime;
    _endTime = initial?.endTime;
    _activityType = initial?.activityType ?? 'eating';
    _baseVersion = initial?.version ?? 1;
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
        title: Text(
          widget.isEdit
              ? context.l10n.t('activity_form.title_edit')
              : context.l10n.t('activity_form.title_create'),
        ),
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
              _buildPlanInfoCard(context),
              const SizedBox(height: 24),
              _buildTitleField(context),
              const SizedBox(height: 16),
              _buildActivityTypeDropdown(context),
              const SizedBox(height: 16),
              _buildDescriptionField(context),
              const SizedBox(height: 16),
              _buildTimeSection(context),
              const SizedBox(height: 16),
              _buildLocationSection(context),
              const SizedBox(height: 16),
              _buildEstimatedCostField(context),
              const SizedBox(height: 16),
              _buildNotesField(context),
              const SizedBox(height: 16),
              _buildVersionChip(context),
              const SizedBox(height: 32),
              _buildSubmitButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanInfoCard(BuildContext context) {
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
                  Text(
                    context.l10n.t('activity_form.plan_label'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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

  Widget _buildTitleField(BuildContext context) {
    return TextFormField(
      controller: _titleCtrl,
      decoration: InputDecoration(
        labelText: context.l10n.t('activity_form.field_title'),
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.title),
      ),
      validator: (value) => value?.trim().isEmpty == true
          ? context.l10n.t('activity_form.validation_title_required')
          : null,
    );
  }

  Widget _buildActivityTypeDropdown(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: _activityType,
      decoration: InputDecoration(
        labelText: context.l10n.t('activity_form.field_type'),
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.category),
      ),
      items: ActivityTypeChoices.values.map((value) {
        return DropdownMenuItem(
          value: value,
          child: Text(context.l10n.activityTypeLabel(value)),
        );
      }).toList(),
      onChanged: (value) => setState(() => _activityType = value!),
    );
  }

  Widget _buildDescriptionField(BuildContext context) {
    return TextFormField(
      controller: _descriptionCtrl,
      decoration: InputDecoration(
        labelText: context.l10n.t('activity_form.field_description'),
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.description),
      ),
      maxLines: 3,
    );
  }

  Widget _buildTimeSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t('activity_form.section_time'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildTimeField(
                context,
                '${context.l10n.t('plan.start')} *',
                _startTime,
                _pickStartTime,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTimeField(
                context,
                '${context.l10n.t('plan.end')} *',
                _endTime,
                _pickEndTime,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeField(
    BuildContext context,
    String label,
    DateTime? time,
    VoidCallback onTap,
  ) {
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
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              time != null
                  ? AppFormatters.fullDateTime(context, time)
                  : context.l10n.t('activity_form.select_time'),
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

  Widget _buildLocationSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t('activity_form.section_location'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _latitude != null && _longitude != null
                ? Stack(
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
                              title: _locationName ??
                                  context.l10n.t('activity_form.selected_location'),
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
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(225),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _locationName ??
                                    context.l10n.t('activity_form.selected_location'),
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
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Material(
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
                              context.l10n.t('activity_form.tap_select_location'),
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
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEstimatedCostField(BuildContext context) {
    return TextFormField(
      controller: _estimatedCostCtrl,
      decoration: InputDecoration(
        labelText: context.l10n.t('activity_form.field_cost'),
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.attach_money),
      ),
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildNotesField(BuildContext context) {
    return TextFormField(
      controller: _notesCtrl,
      decoration: InputDecoration(
        labelText: context.l10n.t('activity_form.field_notes'),
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.note),
      ),
      maxLines: 2,
    );
  }

  Widget _buildVersionChip(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: const Icon(Icons.layers, size: 18),
        label: Text(
          context.l10n.t(
            'activity_collab.current_version',
            params: {'version': 'v$_baseVersion'},
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(context.l10n.t('budget.saving')),
                ],
              )
            : Text(
                widget.isEdit
                    ? context.l10n.t('activity_collab.save_changes')
                    : context.l10n.t('activity_form.submit_create'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Future<void> _pickStartTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _startTime != null
          ? TimeOfDay.fromDateTime(_startTime!)
          : TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    setState(() {
      _startTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickEndTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endTime ?? _startTime ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _endTime != null
          ? TimeOfDay.fromDateTime(_endTime!)
          : (_startTime != null
                ? TimeOfDay.fromDateTime(_startTime!.add(const Duration(hours: 1)))
                : TimeOfDay.now()),
    );
    if (time == null || !mounted) return;

    setState(() {
      _endTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _showLocationPicker() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          initialLocationName: _locationName,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _latitude = (result['latitude'] as num?)?.toDouble();
      _longitude = (result['longitude'] as num?)?.toDouble();
      _locationName =
          result['location_name']?.toString() ?? result['address']?.toString();
      _locationAddress =
          result['location_address']?.toString() ?? result['address']?.toString();
      _goongPlaceId = result['goong_place_id']?.toString();
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = ref.read(authNotifierProvider);
    if (!authProvider.isLoggedIn) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('common.not_logged_in'),
      );
      return;
    }
    if (_startTime == null || _endTime == null) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('activity_form.select_time'),
      );
      return;
    }
    if (_endTime!.isBefore(_startTime!)) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('plan_form.validation_end_after_start'),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (widget.isEdit) {
        final request = UpdatePlanActivityRequest(
          version: _baseVersion,
          title: _titleCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          activityType: _activityType,
          startTime: _startTime,
          endTime: _endTime,
          locationName: _locationName,
          locationAddress: _locationAddress,
          latitude: _latitude,
          longitude: _longitude,
          goongPlaceId: _goongPlaceId,
          estimatedCost: _estimatedCostCtrl.text.trim().isNotEmpty
              ? double.tryParse(_estimatedCostCtrl.text.trim())
              : null,
          notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : '',
        );
        final response = await _repo.updateActivity(widget.initialActivity!.id, request);
        await _handleSuccessResponse(response);
      } else {
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
          goongPlaceId: _goongPlaceId,
          estimatedCost: _estimatedCostCtrl.text.trim().isNotEmpty
              ? double.tryParse(_estimatedCostCtrl.text.trim())
              : null,
          notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        );
        await _repo.createActivity(request);
        if (!mounted) return;
        ErrorDisplayService.showSuccessSnackbar(
          context,
          context.l10n.t('activity_form.submit_create'),
        );
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (error.statusCode == 409 && error.data is Map) {
        final raw = Map<String, dynamic>.from(error.data as Map);
        await _handleConflict(ActivityConflict.fromJson(raw));
      } else if (mounted) {
        ErrorDisplayService.handleError(
          context,
          error,
          showDialog: true,
          onRetry: _submitForm,
        );
      }
    } catch (error) {
      if (mounted) {
        ErrorDisplayService.handleError(
          context,
          error,
          showDialog: true,
          onRetry: _submitForm,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleSuccessResponse(Map<String, dynamic> response) async {
    final activityJson = response['activity'];
    if (activityJson is Map) {
      final updated = PlanActivity.fromJson(Map<String, dynamic>.from(activityJson));
      _baseVersion = updated.version;
    } else {
      _baseVersion += 1;
    }

    if (!mounted) return;
    ErrorDisplayService.showSuccessSnackbar(
      context,
      context.l10n.t('activity_collab.save_changes'),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _handleConflict(ActivityConflict conflict) async {
    if (!mounted) return;
    final action = await showDialog<_ConflictAction>(
      context: context,
      builder: (_) => _ActivityConflictDialog(conflict: conflict),
    );
    if (!mounted) return;

    if (action == _ConflictAction.useServer) {
      _applyServerActivity(conflict.serverActivity);
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('activity_collab.server_version_loaded'),
      );
      return;
    }

    if (action == _ConflictAction.overwrite) {
      setState(() {
        _baseVersion = conflict.serverVersion;
      });
      final overwriteRequest = UpdatePlanActivityRequest(
        version: conflict.serverVersion,
        force: true,
        title: _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        activityType: _activityType,
        startTime: _startTime,
        endTime: _endTime,
        locationName: _locationName,
        locationAddress: _locationAddress,
        latitude: _latitude,
        longitude: _longitude,
        goongPlaceId: _goongPlaceId,
        estimatedCost: _estimatedCostCtrl.text.trim().isNotEmpty
            ? double.tryParse(_estimatedCostCtrl.text.trim())
            : null,
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : '',
      );
      final response = await _repo.updateActivity(
        widget.initialActivity!.id,
        overwriteRequest,
      );
      await _handleSuccessResponse(response);
    }
  }

  void _applyServerActivity(PlanActivity activity) {
    setState(() {
      _titleCtrl.text = activity.title;
      _descriptionCtrl.text = activity.description ?? '';
      _estimatedCostCtrl.text = activity.estimatedCost?.toStringAsFixed(0) ?? '';
      _notesCtrl.text = activity.notes ?? '';
      _activityType = activity.activityType;
      _startTime = activity.startTime;
      _endTime = activity.endTime;
      _latitude = activity.latitude;
      _longitude = activity.longitude;
      _locationName = activity.locationName;
      _locationAddress = activity.locationAddress;
      _goongPlaceId = activity.goongPlaceId;
      _baseVersion = activity.version;
    });
  }
}

enum _ConflictAction { overwrite, useServer }

class _ActivityConflictDialog extends StatelessWidget {
  final ActivityConflict conflict;

  const _ActivityConflictDialog({required this.conflict});

  @override
  Widget build(BuildContext context) {
    final fieldLabels = conflict.conflictingFields
        .map((field) => context.l10n.activityFieldLabel(field))
        .join(', ');

    return AlertDialog(
      title: Text(context.l10n.t('activity_collab.conflict_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(conflict.message),
          const SizedBox(height: 12),
          Text(
            context.l10n.t(
              'activity_collab.conflict_versions',
              params: {
                'client': 'v${conflict.clientVersion ?? '?'}',
                'server': 'v${conflict.serverVersion}',
              },
            ),
          ),
          if (fieldLabels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.t(
                'activity_collab.conflict_fields',
                params: {'fields': fieldLabels},
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ConflictAction.useServer),
          child: Text(context.l10n.t('activity_collab.use_server')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ConflictAction.overwrite),
          child: Text(context.l10n.t('activity_collab.overwrite')),
        ),
      ],
    );
  }
}
