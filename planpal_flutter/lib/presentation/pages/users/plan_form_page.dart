import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/presentation/widgets/forms/app_select_field.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/dtos/plan_requests.dart';
import 'package:planpal_flutter/presentation/widgets/forms/form_wizard_scaffold.dart';
import '../../../core/dtos/group_summary.dart';
import '../../../core/dtos/plan_model.dart';
import '../../../core/services/error_display_service.dart';

class PlanFormPage extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initial;
  const PlanFormPage({super.key, this.initial});

  @override
  ConsumerState<PlanFormPage> createState() => _PlanFormPageState();
}

class _PlanFormPageState extends ConsumerState<PlanFormPage> {
  final _basicStepKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isPublic = true;
  bool _submitting = false;
  PlanRepository get _repo => ref.read(planRepositoryProvider);
  List<GroupSummary> _groups = [];
  String? _selectedGroupId;
  String _planType = 'personal';
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
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

    _planType = widget.initial?['plan_type']?.toString() ?? 'personal';
    _isPublic = _planType == 'group'
        ? true
        : (widget.initial?['is_public'] ?? true);
    _selectedGroupId = widget.initial?['group_id']?.toString();
    _fetchGroups();
  }

  Future<void> _fetchGroups() async {
    try {
      final groupRepo = ref.read(groupRepositoryProvider);
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
    final localizations = AppLocalizations.of(context);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      cancelText: localizations.t('common.cancel'),
      confirmText: 'OK',
      helpText: localizations.t('activity_form.select_time'),
      builder: (BuildContext context, Widget? child) {
        return Localizations.override(
          context: context,
          locale: const Locale('en', 'US'),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
        );
      },
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
    if (!_validateBeforeSubmit()) return;
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('plan_form.validation_end_after_start'),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      PlanModel result;
      final isPublic = _planType == 'group' ? true : _isPublic;
      // Check if we have an ID to determine edit vs create mode
      final planId = widget.initial?['id']?.toString();
      if (planId == null || planId.isEmpty) {
        // Create mode
        final request = CreatePlanRequest(
          title: _titleCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          // send UTC ISO strings so server stores an unambiguous instant
          startDate: _startDate?.toUtc().toIso8601String() ?? '',
          endDate: _endDate?.toUtc().toIso8601String() ?? '',
          isPublic: isPublic,
          planType: _planType,
          groupId: _selectedGroupId,
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
        // Edit mode
        final request = UpdatePlanRequest(
          title: _titleCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          // send UTC ISO strings so server stores an unambiguous instant
          startDate: _startDate?.toUtc().toIso8601String(),
          endDate: _endDate?.toUtc().toIso8601String(),
          isPublic: isPublic,
          planType: _planType,
        );
        result = await _repo.updatePlan(planId, request);
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
      ErrorDisplayService.handleError(context, e, showDialog: true);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final planId = widget.initial?['id']?.toString();
    final isEdit = planId != null && planId.isNotEmpty;
    final l10n = context.l10n;
    final steps = _buildWizardSteps(context);
    return FormWizardScaffold(
      title: isEdit
          ? l10n.t('plan_form.title_edit')
          : l10n.t('plan_form.title_create'),
      steps: steps,
      currentStep: _currentStep,
      isSubmitting: _submitting,
      onBack: _handleBack,
      onNext: _handleNext,
      onFinish: _submit,
    );
  }

  bool _validateBeforeSubmit() {
    if (!_validateBasicDraft(redirectToStep: true)) {
      return false;
    }
    if (_planType == 'group' &&
        (_selectedGroupId == null || _selectedGroupId!.isEmpty)) {
      setState(() => _currentStep = 1);
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('plan_form.validation_group_required'),
      );
      return false;
    }
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      setState(() => _currentStep = 2);
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('plan_form.validation_end_after_start'),
      );
      return false;
    }
    return true;
  }

  List<FormWizardStep> _buildWizardSteps(BuildContext context) {
    final l10n = context.l10n;
    return [
      FormWizardStep(
        title: l10n.t('wizard.basic_info'),
        icon: Icons.article_outlined,
        subtitle: l10n.t('plan_form.title_create'),
        child: Form(key: _basicStepKey, child: _buildBasicStep(context)),
      ),
      FormWizardStep(
        title: l10n.t('plan_form.field_type'),
        icon: Icons.category_outlined,
        subtitle: l10n.t('wizard.required_step'),
        child: _buildTypeStep(context),
      ),
      FormWizardStep(
        title: l10n.t('wizard.time'),
        icon: Icons.schedule_outlined,
        subtitle: l10n.t('plan_form.validation_end_after_start'),
        child: _buildTimeStep(context),
      ),
      FormWizardStep(
        title: l10n.t('wizard.settings'),
        icon: Icons.tune_outlined,
        child: _buildSettingsStep(context),
      ),
      FormWizardStep(
        title: l10n.t('wizard.review'),
        icon: Icons.fact_check_outlined,
        subtitle: l10n.t('wizard.review_subtitle'),
        child: _buildReviewStep(context),
      ),
    ];
  }

  void _handleBack() {
    if (_currentStep == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _currentStep -= 1);
  }

  void _handleNext() {
    if (!_validateCurrentStep()) return;
    setState(() => _currentStep += 1);
  }

  bool _validateCurrentStep() {
    final l10n = context.l10n;
    if (_currentStep == 0) {
      return _basicStepKey.currentState?.validate() ?? _validateBasicDraft();
    }
    if (_currentStep == 1 &&
        _planType == 'group' &&
        (_selectedGroupId == null || _selectedGroupId!.isEmpty)) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        l10n.t('plan_form.validation_group_required'),
      );
      return false;
    }
    if (_currentStep == 2 &&
        _startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        l10n.t('plan_form.validation_end_after_start'),
      );
      return false;
    }
    return true;
  }

  String? _validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.l10n.t('plan_form.validation_title_required');
    }
    return null;
  }

  bool _validateBasicDraft({bool redirectToStep = false}) {
    final error = _validateTitle(_titleCtrl.text);
    if (error == null) return true;

    if (redirectToStep && _currentStep != 0) {
      setState(() => _currentStep = 0);
    }
    ErrorDisplayService.showErrorSnackbar(context, error);
    return false;
  }

  Widget _buildBasicStep(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        TextFormField(
          controller: _titleCtrl,
          decoration: InputDecoration(
            labelText: l10n.t('plan_form.field_title'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.flag_outlined),
          ),
          validator: _validateTitle,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionCtrl,
          decoration: InputDecoration(
            labelText: l10n.t('plan_form.field_description'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.notes_outlined),
          ),
          maxLines: 4,
        ),
      ],
    );
  }

  Widget _buildTypeStep(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        _buildPlanTypeCard(
          context,
          value: 'personal',
          icon: Icons.person_outline,
          title: l10n.t('plan_form.type_personal'),
          selected: _planType == 'personal',
          onTap: () => setState(() {
            _planType = 'personal';
            _selectedGroupId = null;
          }),
        ),
        const SizedBox(height: 12),
        _buildPlanTypeCard(
          context,
          value: 'group',
          icon: Icons.groups_outlined,
          title: l10n.t('plan_form.type_group'),
          selected: _planType == 'group',
          onTap: () => setState(() {
            _planType = 'group';
            _isPublic = true;
          }),
        ),
        if (_planType == 'group') ...[
          const SizedBox(height: 16),
          AppSelectField<String>(
            label: l10n.t('plan_form.select_group'),
            value: _selectedGroupId,
            prefixIcon: Icons.group_work_outlined,
            hintText: l10n.t('plan_form.select_group'),
            options: _groups
                .map((group) => AppSelectOption(value: group.id, label: group.name))
                .toList(),
            onChanged: (value) => setState(() => _selectedGroupId = value),
          ),
        ],
      ],
    );
  }

  Widget _buildPlanTypeCard(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? colorScheme.primary : null),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeStep(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        _buildDateButton(
          context,
          icon: Icons.play_circle_outline,
          label: _startDate != null
              ? l10n.t(
                  'plan_form.start_label',
                  params: {
                    'value': AppFormatters.fullDateTime(context, _startDate!),
                  },
                )
              : l10n.t('plan_form.select_start_date'),
          onPressed: () => _pickDateTime(isStart: true),
        ),
        const SizedBox(height: 12),
        _buildDateButton(
          context,
          icon: Icons.stop_circle_outlined,
          label: _endDate != null
              ? l10n.t(
                  'plan_form.end_label',
                  params: {
                    'value': AppFormatters.fullDateTime(context, _endDate!),
                  },
                )
              : l10n.t('plan_form.select_end_date'),
          onPressed: () => _pickDateTime(isStart: false),
        ),
      ],
    );
  }

  Widget _buildDateButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _buildSettingsStep(BuildContext context) {
    final l10n = context.l10n;
    if (_planType == 'group') {
      return ReviewSection(
        title: l10n.t('plan_form.type_group'),
        items: [
          ReviewItem(
            l10n.t('plan_form.select_group'),
            _selectedGroupName() ?? '-',
          ),
          ReviewItem(l10n.t('plan_form.public'), l10n.t('common.yes')),
        ],
      );
    }
    return SwitchListTile(
      title: Text(l10n.t('plan_form.public')),
      subtitle: Text(
        _isPublic
            ? l10n.t('plan_form.public_description_public')
            : l10n.t('plan_form.public_description_private'),
      ),
      value: _isPublic,
      onChanged: (value) => setState(() => _isPublic = value),
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    final l10n = context.l10n;
    final selectedGroupName = _selectedGroupName();
    return Column(
      children: [
        ReviewSection(
          title: l10n.t('wizard.basic_info'),
          items: [
            ReviewItem(l10n.t('plan_form.field_title'), _titleCtrl.text),
            ReviewItem(
              l10n.t('plan_form.field_description'),
              _descriptionCtrl.text,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ReviewSection(
          title: l10n.t('plan_form.field_type'),
          items: [
            ReviewItem(
              l10n.t('plan_form.field_type'),
              _planType == 'group'
                  ? l10n.t('plan_form.type_group')
                  : l10n.t('plan_form.type_personal'),
            ),
            if (_planType == 'group')
              ReviewItem(
                l10n.t('plan_form.select_group'),
                selectedGroupName ?? '-',
              ),
          ],
        ),
        const SizedBox(height: 12),
        ReviewSection(
          title: l10n.t('wizard.time'),
          items: [
            ReviewItem(
              l10n.t('plan.start'),
              _startDate == null
                  ? '-'
                  : AppFormatters.fullDateTime(context, _startDate!),
            ),
            ReviewItem(
              l10n.t('plan.end'),
              _endDate == null
                  ? '-'
                  : AppFormatters.fullDateTime(context, _endDate!),
            ),
            ReviewItem(
              l10n.t('plan_form.public'),
              _planType == 'group' || _isPublic
                  ? l10n.t('common.yes')
                  : l10n.t('common.no'),
            ),
          ],
        ),
      ],
    );
  }

  String? _selectedGroupName() {
    for (final group in _groups) {
      if (group.id == _selectedGroupId) return group.name;
    }
    return null;
  }
}
