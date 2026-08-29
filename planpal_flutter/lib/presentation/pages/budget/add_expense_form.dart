import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/presentation/widgets/forms/form_wizard_scaffold.dart';
import 'package:planpal_flutter/presentation/widgets/forms/app_select_field.dart';

class AddExpenseForm extends ConsumerStatefulWidget {
  final String planId;
  final String planTitle;
  final List<UserSummary> members;

  const AddExpenseForm({
    super.key,
    required this.planId,
    required this.planTitle,
    this.members = const [],
  });

  @override
  ConsumerState<AddExpenseForm> createState() => _AddExpenseFormState();
}

class _AddExpenseFormState extends ConsumerState<AddExpenseForm> {
  final _basicStepKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Map<String, TextEditingController> _splitControllers = {};
  final Map<String, TextEditingController> _paymentControllers = {};
  final Set<String> _selectedParticipantIds = {};
  String _splitStrategy = 'equal';
  String? _paidByUserId;
  bool _hasMultiplePayers = false;
  bool _isSubmitting = false;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _paidByUserId = widget.members.isNotEmpty ? widget.members.first.id : null;
    _selectedParticipantIds.addAll(widget.members.map((member) => member.id));
    for (final member in widget.members) {
      _splitControllers[member.id] = TextEditingController();
      _paymentControllers[member.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    for (final controller in _splitControllers.values) {
      controller.dispose();
    }
    for (final controller in _paymentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FormWizardScaffold(
      title: l10n.t('budget.form_title'),
      steps: _buildWizardSteps(context),
      currentStep: _currentStep,
      isSubmitting: _isSubmitting,
      onBack: _handleBack,
      onNext: _handleNext,
      onFinish: _submit,
    );
  }

  List<FormWizardStep> _buildWizardSteps(BuildContext context) {
    final l10n = context.l10n;
    return [
      FormWizardStep(
        title: l10n.t('wizard.details'),
        icon: Icons.receipt_long_outlined,
        subtitle: widget.planTitle,
        child: Form(key: _basicStepKey, child: _buildBasicStep(context)),
      ),
      if (widget.members.isNotEmpty)
        FormWizardStep(
          title: l10n.t('wizard.sharing'),
          icon: Icons.group_outlined,
          subtitle: l10n.t('budget.form_description'),
          child: _buildSharingSection(context),
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
    if (_currentStep == 0) {
      return _basicStepKey.currentState?.validate() ?? _validateBasicDraft();
    }
    if (widget.members.isNotEmpty && _currentStep == 1) {
      final splitError = _validateSplitInputs();
      if (splitError != null) {
        ErrorDisplayService.showErrorSnackbar(context, splitError);
        return false;
      }
    }
    return true;
  }

  String? _validateAmount(String? value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed <= 0) {
      return context.l10n.t('budget.validation_amount_positive');
    }
    return null;
  }

  String? _validateCategory(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return context.l10n.t('budget.validation_category_required');
    }
    if (text.length > 100) {
      return context.l10n.t('budget.validation_category_too_long');
    }
    return null;
  }

  bool _validateBasicDraft({bool redirectToStep = false}) {
    final error =
        _validateAmount(_amountController.text) ??
        _validateCategory(_categoryController.text);
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.planTitle,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.t('budget.amount'),
            prefixIcon: const Icon(Icons.payments_outlined),
            hintText: l10n.t('budget.amount_hint'),
          ),
          onChanged: (_) => setState(() {}),
          validator: _validateAmount,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _categoryController,
          decoration: InputDecoration(
            labelText: l10n.t('budget.category'),
            prefixIcon: const Icon(Icons.category_outlined),
            hintText: l10n.t('budget.category_hint'),
          ),
          validator: _validateCategory,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: l10n.t('budget.description'),
            prefixIcon: const Icon(Icons.notes_rounded),
            alignLabelWithHint: true,
            hintText: l10n.t('budget.description_hint'),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    final l10n = context.l10n;
    final payer = _memberById(_paidByUserId);
    return Column(
      children: [
        ReviewSection(
          title: l10n.t('wizard.details'),
          items: [
            ReviewItem(l10n.t('budget.amount'), _amountController.text),
            ReviewItem(l10n.t('budget.category'), _categoryController.text),
            ReviewItem(
              l10n.t('budget.description'),
              _descriptionController.text,
            ),
          ],
        ),
        if (widget.members.isNotEmpty) ...[
          const SizedBox(height: 12),
          ReviewSection(
            title: l10n.t('wizard.sharing'),
            items: [
              ReviewItem(
                l10n.t('budget.payment_contributions'),
                _hasMultiplePayers
                    ? _paymentPreview()
                    : (payer == null ? '-' : _memberName(payer)),
              ),
              ReviewItem(
                l10n.t('budget.split_strategy'),
                _localizedSplitStrategy(l10n, _splitStrategy),
              ),
              ReviewItem(
                l10n.t('budget.participants'),
                '${_selectedParticipantIds.length}',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSharingSection(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final selectedCount = _selectedParticipantIds.length;
    final equalPreview = selectedCount == 0 ? 0 : amount / selectedCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('budget.expense_sharing'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.t('budget.multiple_payers')),
            subtitle: Text(l10n.t('budget.multiple_payers_description')),
            value: _hasMultiplePayers,
            onChanged: (enabled) {
              setState(() {
                _hasMultiplePayers = enabled;
                if (enabled && _paidByUserId != null) {
                  _paymentControllers[_paidByUserId!]?.text =
                      _amountController.text.trim();
                }
              });
            },
          ),
          const SizedBox(height: 8),
          if (_hasMultiplePayers)
            _buildPaymentContributions(context)
          else
            AppSelectField<String>(
              label: l10n.t('budget.paid_by'),
              value: _paidByUserId,
              prefixIcon: Icons.account_balance_wallet_outlined,
              hintText: l10n.t('budget.select_payer'),
              options: widget.members
                  .map(
                    (member) => AppSelectOption(
                      value: member.id,
                      label: _memberName(member),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _paidByUserId = value),
            ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'equal',
                label: Text(l10n.t('budget.split_equal')),
              ),
              ButtonSegment(
                value: 'percentage',
                label: Text(l10n.t('budget.split_percentage')),
              ),
              ButtonSegment(
                value: 'exact',
                label: Text(l10n.t('budget.split_exact')),
              ),
            ],
            selected: {_splitStrategy},
            onSelectionChanged: (values) {
              setState(() => _splitStrategy = values.first);
            },
          ),
          const SizedBox(height: 12),
          ...widget.members.map((member) {
            final selected = _selectedParticipantIds.contains(member.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedParticipantIds.add(member.id);
                        } else {
                          _selectedParticipantIds.remove(member.id);
                        }
                      });
                    },
                  ),
                  Expanded(child: Text(_memberName(member))),
                  if (selected && _splitStrategy == 'equal')
                    Text(
                      equalPreview > 0 ? equalPreview.toStringAsFixed(0) : '-',
                    ),
                  if (selected && _splitStrategy != 'equal')
                    SizedBox(
                      width: 108,
                      child: TextFormField(
                        controller: _splitControllers[member.id],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _splitStrategy == 'percentage'
                              ? l10n.t('budget.percent')
                              : l10n.t('budget.amount'),
                        ),
                        validator: (_) => _validateSplitInputs(),
                      ),
                    ),
                ],
              ),
            );
          }),
          if (selectedCount == 0)
            Text(
              l10n.t('budget.validation_participant_required'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_validateBasicDraft(redirectToStep: true)) {
      return;
    }
    final splitError = _validateSplitInputs();
    if (splitError != null) {
      if (widget.members.isNotEmpty) {
        setState(() => _currentStep = 1);
      }
      ErrorDisplayService.showErrorSnackbar(context, splitError);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final participantInputs = _buildParticipantInputs();
      final paymentInputs = _buildPaymentInputs();
      final result = await ref
          .read(budgetRepositoryProvider)
          .addExpense(
            widget.planId,
            amount: double.parse(_amountController.text.trim()),
            category: _categoryController.text.trim(),
            description: _descriptionController.text.trim(),
            paidByUserId: _paidByUserId,
            splitStrategy: _splitStrategy,
            participants: participantInputs,
            payments: paymentInputs,
          );
      if (!mounted) return;
      Navigator.of(context).pop<ExpenseCreateResult>(result);
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, error, showDialog: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  List<ExpenseParticipantInput> _buildParticipantInputs() {
    if (widget.members.isEmpty) return const [];
    return _selectedParticipantIds.map((userId) {
      final raw = _splitControllers[userId]?.text.trim() ?? '';
      final value = double.tryParse(raw);
      return ExpenseParticipantInput(
        userId: userId,
        amount: _splitStrategy == 'exact' ? value : null,
        percentage: _splitStrategy == 'percentage' ? value : null,
      );
    }).toList();
  }

  List<ExpensePaymentInput> _buildPaymentInputs() {
    if (!_hasMultiplePayers) return const [];
    return widget.members
        .map((member) {
          final amount = double.tryParse(
            _paymentControllers[member.id]?.text.trim() ?? '',
          );
          if (amount == null || amount <= 0) return null;
          return ExpensePaymentInput(userId: member.id, amount: amount);
        })
        .whereType<ExpensePaymentInput>()
        .toList();
  }

  String? _validateSplitInputs() {
    if (widget.members.isEmpty) return null;
    if (_selectedParticipantIds.isEmpty) {
      return context.l10n.t('budget.validation_participant_required');
    }
    if (!_hasMultiplePayers && (_paidByUserId == null || _paidByUserId!.isEmpty)) {
      return context.l10n.t('budget.validation_payer_required');
    }
    final paymentError = _validatePaymentInputs();
    if (paymentError != null) return paymentError;
    if (_splitStrategy == 'equal') return null;

    double total = 0;
    for (final userId in _selectedParticipantIds) {
      final raw = _splitControllers[userId]?.text.trim() ?? '';
      final value = double.tryParse(raw);
      if (value == null || value < 0) {
        return _splitStrategy == 'percentage'
            ? context.l10n.t('budget.validation_percentage_each')
            : context.l10n.t('budget.validation_amount_each');
      }
      total += value;
    }
    if (_splitStrategy == 'percentage' && (total - 100).abs() > 0.01) {
      return context.l10n.t('budget.validation_percentage_total');
    }
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (_splitStrategy == 'exact' && (total - amount).abs() > 0.01) {
      return context.l10n.t('budget.validation_exact_total');
    }
    return null;
  }

  String? _validatePaymentInputs() {
    if (!_hasMultiplePayers) return null;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    double total = 0;
    var payerCount = 0;
    for (final member in widget.members) {
      final raw = _paymentControllers[member.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final contribution = double.tryParse(raw);
      if (contribution == null || contribution <= 0) {
        return context.l10n.t('budget.validation_payment_amount');
      }
      payerCount += 1;
      total += contribution;
    }
    if (payerCount == 0) return context.l10n.t('budget.validation_payment_required');
    if ((total - amount).abs() > 0.01) {
      return context.l10n.t('budget.validation_payment_total');
    }
    return null;
  }

  Widget _buildPaymentContributions(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final total = _paymentTotal();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final isBalanced = (total - amount).abs() <= 0.01 && total > 0;
    final color = isBalanced ? theme.colorScheme.primary : theme.colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('budget.payment_contributions'),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.t('budget.payment_contributions_hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...widget.members.map(
            (member) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextFormField(
                controller: _paymentControllers[member.id],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _memberName(member),
                  prefixIcon: const Icon(Icons.payments_outlined),
                  hintText: '0',
                ),
              ),
            ),
          ),
          Text(
            l10n.t(
              'budget.payment_total_preview',
              params: {
                'total': total.toStringAsFixed(0),
                'amount': amount.toStringAsFixed(0),
              },
            ),
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  double _paymentTotal() => widget.members.fold<double>(
    0,
    (total, member) =>
        total + (double.tryParse(_paymentControllers[member.id]?.text.trim() ?? '') ?? 0),
  );

  String _paymentPreview() {
    return _buildPaymentInputs()
        .map((payment) {
          final member = _memberById(payment.userId);
          return '${member == null ? '-' : _memberName(member)}: ${payment.amount.toStringAsFixed(0)}';
        })
        .join(', ');
  }

  String _memberName(UserSummary member) {
    if (member.fullName.trim().isNotEmpty) return member.fullName;
    if (member.username.trim().isNotEmpty) return member.username;
    return member.email ?? member.id;
  }

  UserSummary? _memberById(String? userId) {
    if (userId == null) return null;
    for (final member in widget.members) {
      if (member.id == userId) return member;
    }
    return null;
  }

  String _localizedSplitStrategy(AppLocalizations l10n, String strategy) {
    switch (strategy) {
      case 'percentage':
        return l10n.t('budget.split_percentage');
      case 'exact':
        return l10n.t('budget.split_exact');
      default:
        return l10n.t('budget.split_equal');
    }
  }
}
