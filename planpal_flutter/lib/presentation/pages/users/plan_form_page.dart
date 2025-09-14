import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planpal_flutter/core/repositories/group_repository.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/dtos/plan_requests.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import '../../../core/dtos/group_summary.dart';
import '../../../core/dtos/plan_detail.dart';

class PlanFormPage extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const PlanFormPage({super.key, this.initial});

  @override
  State<PlanFormPage> createState() => _PlanFormPageState();
}

class _PlanFormPageState extends State<PlanFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isPublic = true;
  bool _submitting = false;
  late final PlanRepository _repo;
  List<GroupSummary> _groups = [];
  String? _selectedGroupId;
  String _planType = 'personal';

  @override
  void initState() {
    super.initState();
    _repo = PlanRepository(context.read<AuthProvider>());
    _titleCtrl = TextEditingController(
      text: widget.initial?['title']?.toString() ?? '',
    );
    _descriptionCtrl = TextEditingController(
      text: widget.initial?['description']?.toString() ?? '',
    );

    // Parse dates if any
    final startDateStr = widget.initial?['start_date']?.toString();
    final endDateStr = widget.initial?['end_date']?.toString();
    try {
      if (startDateStr != null && startDateStr.isNotEmpty) {
        _startDate = DateTime.parse(startDateStr);
      }
    } catch (_) {}
    try {
      if (endDateStr != null && endDateStr.isNotEmpty) {
        _endDate = DateTime.parse(endDateStr);
      }
    } catch (_) {}

    _isPublic = widget.initial?['is_public'] ?? true;
    _planType = widget.initial?['plan_type']?.toString() ?? 'personal';
    _selectedGroupId = widget.initial?['group_id']?.toString();
    _fetchGroups();
  }

  Future<void> _fetchGroups() async {
    try {
      final repo = context.read<AuthProvider>();
      final groupRepo = GroupRepository(repo);
      final groups = await groupRepo.getGroups();
      if (!mounted) return;
      setState(() => _groups = groups);
    } catch (e) {
      // ignore error, show empty
      setState(() => _groups = []);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final initialDate = (isStart ? _startDate : _endDate) ?? now;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: initialDate,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (!mounted || time == null) return;

    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!mounted) return;
    setState(() {
      if (isStart) {
        _startDate = dt;
      } else {
        _endDate = dt;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ngày kết thúc phải sau ngày bắt đầu')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      PlanDetail result;
      if (widget.initial == null) {
        final request = CreatePlanRequest(
          title: _titleCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          startDate: _startDate?.toIso8601String() ?? '',
          endDate: _endDate?.toIso8601String() ?? '',
          isPublic: _isPublic,
          planType: _planType,
        );
        result = await _repo.createPlan(request);
        if (!mounted) return;
        Navigator.of(context).pop({
          'action': 'created',
          'plan': {
            'id': result.id,
            'title': result.title,
            'start_date': result.startDate?.toIso8601String(),
            'end_date': result.endDate?.toIso8601String(),
            'is_public': result.isPublic,
            'plan_type': result.planType,
            'group_id': result.group?.id,
          },
        });
      } else {
        final id = widget.initial!['id'];
        final request = UpdatePlanRequest(
          title: _titleCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          startDate: _startDate?.toIso8601String(),
          endDate: _endDate?.toIso8601String(),
          isPublic: _isPublic,
          planType: _planType,
        );
        result = await _repo.updatePlan(id, request);
        if (!mounted) return;
        Navigator.of(context).pop({
          'action': 'updated',
          'plan': {
            'id': result.id,
            'title': result.title,
            'start_date': result.startDate?.toIso8601String(),
            'end_date': result.endDate?.toIso8601String(),
            'is_public': result.isPublic,
            'plan_type': result.planType,
            'group_id': result.group?.id,
          },
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Sửa kế hoạch' : 'Tạo kế hoạch'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tiêu đề kế hoạch',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Vui lòng nhập tiêu đề kế hoạch'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mô tả',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Kế hoạch cá nhân'),
                      value: 'personal',
                      groupValue: _planType,
                      onChanged: (v) => setState(() {
                        _planType = v!;
                        _selectedGroupId = null;
                      }),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Kế hoạch nhóm'),
                      value: 'group',
                      groupValue: _planType,
                      onChanged: (v) => setState(() {
                        _planType = v!;
                      }),
                    ),
                  ),
                ],
              ),
              if (_planType == 'group') ...[
                DropdownButtonFormField<String>(
                  value: _selectedGroupId,
                  decoration: const InputDecoration(
                    labelText: 'Chọn nhóm',
                    border: OutlineInputBorder(),
                  ),
                  items: _groups
                      .map(
                        (g) =>
                            DropdownMenuItem(value: g.id, child: Text(g.name)),
                      )
                      .toList(),
                  validator: (v) {
                    if (_planType == 'group' && (v == null || v.isEmpty)) {
                      return 'Vui lòng chọn nhóm';
                    }
                    return null;
                  },
                  onChanged: (v) => setState(() => _selectedGroupId = v),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDateTime(isStart: true),
                      icon: const Icon(Icons.play_circle_outline),
                      label: Text(
                        _startDate != null
                            ? 'Bắt đầu: ${DateFormat('dd/MM/yyyy HH:mm').format(_startDate!)}'
                            : 'Chọn ngày bắt đầu',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDateTime(isStart: false),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(
                        _endDate != null
                            ? 'Kết thúc: ${DateFormat('dd/MM/yyyy HH:mm').format(_endDate!)}'
                            : 'Chọn ngày kết thúc',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Công khai'),
                subtitle: Text(
                  _isPublic ? 'Mọi người có thể xem' : 'Chỉ mình tôi',
                ),
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.save),
                  label: Text(isEdit ? 'Lưu thay đổi' : 'Tạo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
