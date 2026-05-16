import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Map<String, TextEditingController> _splitControllers = {};
  final Set<String> _selectedParticipantIds = {};
  String _splitStrategy = 'equal';
  String? _paidByUserId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _paidByUserId = widget.members.isNotEmpty ? widget.members.first.id : null;
    _selectedParticipantIds.addAll(widget.members.map((member) => member.id));
    for (final member in widget.members) {
      _splitControllers[member.id] = TextEditingController();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('budget.form_title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.planTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.t('budget.form_description'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.t('budget.amount'),
                    prefixIcon: const Icon(Icons.payments_outlined),
                    hintText: l10n.t('budget.amount_hint'),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final parsed = double.tryParse((value ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return l10n.t('budget.validation_amount_positive');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _categoryController,
                  decoration: InputDecoration(
                    labelText: l10n.t('budget.category'),
                    prefixIcon: const Icon(Icons.category_outlined),
                    hintText: l10n.t('budget.category_hint'),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return l10n.t('budget.validation_category_required');
                    }
                    if (text.length > 100) {
                      return l10n.t('budget.validation_category_too_long');
                    }
                    return null;
                  },
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
                if (widget.members.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildSharingSection(context),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_circle_outline_rounded),
                    label: Text(
                      _isSubmitting
                          ? l10n.t('budget.saving')
                          : l10n.t('budget.add_expense'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
          DropdownButtonFormField<String>(
            initialValue: _paidByUserId,
            decoration: InputDecoration(
              labelText: l10n.t('budget.paid_by'),
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
            ),
            items: widget.members
                .map(
                  (member) => DropdownMenuItem(
                    value: member.id,
                    child: Text(_memberName(member)),
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
    if (!_formKey.currentState!.validate()) return;
    final splitError = _validateSplitInputs();
    if (splitError != null) {
      ErrorDisplayService.showErrorSnackbar(context, splitError);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final participantInputs = _buildParticipantInputs();
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

  String? _validateSplitInputs() {
    if (widget.members.isEmpty) return null;
    if (_selectedParticipantIds.isEmpty) {
      return context.l10n.t('budget.validation_participant_required');
    }
    if (_paidByUserId == null || _paidByUserId!.isEmpty) {
      return context.l10n.t('budget.validation_payer_required');
    }
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

  String _memberName(UserSummary member) {
    if (member.fullName.trim().isNotEmpty) return member.fullName;
    if (member.username.trim().isNotEmpty) return member.username;
    return member.email ?? member.id;
  }
}
