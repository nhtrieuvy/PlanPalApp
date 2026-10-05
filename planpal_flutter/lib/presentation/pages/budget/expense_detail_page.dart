import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';

class ExpenseDetailPage extends ConsumerWidget {
  final ExpenseModel expense;

  const ExpenseDetailPage({super.key, required this.expense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('budget.expense_detail')),
        actions: [
          IconButton(
            tooltip: l10n.t('budget.correct_expense'),
            onPressed: () => _correctExpense(context, ref),
            icon: const Icon(Icons.edit_note_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _HeroSummary(expense: expense),
          const SizedBox(height: 20),
          _InfoCard(
            title: l10n.t('wizard.details'),
            icon: Icons.receipt_long_outlined,
            children: [
              _InfoRow(
                icon: Icons.category_outlined,
                label: l10n.t('budget.category'),
                value: expense.category,
              ),
              _InfoRow(
                icon: Icons.call_split_outlined,
                label: l10n.t('budget.split_strategy'),
                value: _localizedSplitStrategy(l10n, expense.splitStrategy),
              ),
              if (expense.description.trim().isNotEmpty)
                _InfoRow(
                  icon: Icons.notes_outlined,
                  label: l10n.t('budget.description'),
                  value: expense.description,
                ),
              if (expense.paymentNote.trim().isNotEmpty)
                _InfoRow(
                  icon: Icons.payments_outlined,
                  label: l10n.t('budget.payment_note'),
                  value: expense.paymentNote,
                ),
              if (expense.entryType == 'correction')
                _InfoRow(
                  icon: Icons.history_rounded,
                  label: l10n.t('budget.corrected_entry'),
                  value: expense.correctionReason,
                ),
              if (expense.receiptUrl != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file_rounded),
                  title: Text(l10n.t('budget.receipt')),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => launchUrl(
                    Uri.parse(expense.receiptUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: l10n.t('budget.payment_contributions'),
            icon: Icons.account_balance_wallet_outlined,
            children: _paymentRows(context, l10n),
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: l10n.t('budget.participants'),
            icon: Icons.group_outlined,
            children: expense.participants
                .map(
                  (participant) => _ParticipantRow(
                    participant: participant,
                    currency: expense.currency,
                  ),
                )
                .toList(),
          ),
          if (expense.participants.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.t('budget.breakdown_empty'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _correctExpense(BuildContext context, WidgetRef ref) async {
    final draft = await showModalBottomSheet<_ExpenseCorrectionDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExpenseCorrectionSheet(expense: expense),
    );
    if (draft == null || !context.mounted) return;
    try {
      final result = await ref
          .read(budgetRepositoryProvider)
          .correctExpense(
            expense.planId,
            expense.id,
            amount: draft.amount,
            category: draft.category,
            description: draft.description,
            paymentNote: draft.paymentNote,
            reason: draft.reason,
            receiptPath: draft.receiptPath,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (context.mounted) {
        ErrorDisplayService.handleError(context, error, showDialog: true);
      }
    }
  }

  List<Widget> _paymentRows(BuildContext context, AppLocalizations l10n) {
    if (expense.payments.isEmpty) {
      return [
        _InfoRow(
          icon: Icons.person_outline,
          label: l10n.t('budget.paid_by'),
          value: _userName(expense.paidByUser),
          trailing: AppFormatters.currency(
            context,
            amount: expense.amount,
            currencyCode: expense.currency,
          ),
        ),
      ];
    }
    return expense.payments
        .map(
          (payment) => _InfoRow(
            icon: Icons.person_outline,
            label: _userName(payment.user),
            value: l10n.t('budget.paid_by'),
            trailing: AppFormatters.currency(
              context,
              amount: payment.amount,
              currencyCode: expense.currency,
            ),
          ),
        )
        .toList();
  }

  String _userName(dynamic user) {
    if (user.fullName.trim().isNotEmpty) return user.fullName;
    if (user.username.trim().isNotEmpty) return user.username;
    return user.id;
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

class _ExpenseCorrectionDraft {
  const _ExpenseCorrectionDraft({
    required this.amount,
    required this.category,
    required this.description,
    required this.paymentNote,
    required this.reason,
    this.receiptPath,
  });

  final double amount;
  final String category;
  final String description;
  final String paymentNote;
  final String reason;
  final String? receiptPath;
}

class _ExpenseCorrectionSheet extends StatefulWidget {
  const _ExpenseCorrectionSheet({required this.expense});

  final ExpenseModel expense;

  @override
  State<_ExpenseCorrectionSheet> createState() =>
      _ExpenseCorrectionSheetState();
}

class _ExpenseCorrectionSheetState extends State<_ExpenseCorrectionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _paymentNote;
  final _reason = TextEditingController();
  String? _receiptPath;
  String? _receiptName;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.expense.amount.toStringAsFixed(2),
    );
    _category = TextEditingController(text: widget.expense.category);
    _description = TextEditingController(text: widget.expense.description);
    _paymentNote = TextEditingController(text: widget.expense.paymentNote);
  }

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _description.dispose();
    _paymentNote.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.t('budget.correct_expense'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.l10n.t('budget.amount'),
                ),
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  return amount == null || amount <= 0
                      ? context.l10n.t('budget.validation_amount_positive')
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _category,
                decoration: InputDecoration(
                  labelText: context.l10n.t('budget.category'),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? context.l10n.t('budget.validation_category_required')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: InputDecoration(
                  labelText: context.l10n.t('budget.description'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _paymentNote,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.l10n.t('budget.payment_note'),
                  hintText: context.l10n.t('budget.payment_note_hint'),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  _receiptName ?? context.l10n.t('budget.attach_new_receipt'),
                ),
                subtitle: Text(context.l10n.t('budget.receipt_formats')),
                trailing: _receiptPath == null
                    ? const Icon(Icons.add_rounded)
                    : IconButton(
                        tooltip: context.l10n.t('budget.remove_receipt'),
                        onPressed: () => setState(() {
                          _receiptPath = null;
                          _receiptName = null;
                        }),
                        icon: const Icon(Icons.close_rounded),
                      ),
                onTap: _pickReceipt,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.l10n.t('budget.correction_reason'),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? context.l10n.t('budget.correction_reason')
                    : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(context.l10n.t('common.save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _ExpenseCorrectionDraft(
        amount: double.parse(_amount.text.trim()),
        category: _category.text.trim(),
        description: _description.text.trim(),
        paymentNote: _paymentNote.text.trim(),
        reason: _reason.text.trim(),
        receiptPath: _receiptPath,
      ),
    );
  }

  Future<void> _pickReceipt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    final file = result?.files.single;
    if (file?.path == null || !mounted) return;
    if (file!.size > 10 * 1024 * 1024) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('budget.receipt_too_large'),
      );
      return;
    }
    setState(() {
      _receiptPath = file.path;
      _receiptName = file.name;
    });
  }
}

class _HeroSummary extends StatelessWidget {
  final ExpenseModel expense;

  const _HeroSummary({required this.expense});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            expense.category,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppFormatters.currency(
              context,
              amount: expense.amount,
              currencyCode: expense.currency,
            ),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppFormatters.fullDateTime(context, expense.createdAt),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  final ExpenseParticipantModel participant;
  final String currency;

  const _ParticipantRow({required this.participant, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final name = participant.user.fullName.trim().isNotEmpty
        ? participant.user.fullName
        : participant.user.username;

    final balance = participant.balance;
    final amount = balance.abs();

    final String statusText;
    if (balance < 0) {
      statusText = context.l10n.t(
        'budget.owes_amount',
        params: {
          'amount': AppFormatters.currency(
            context,
            amount: amount,
            currencyCode: currency,
          ),
        },
      );
    } else if (balance > 0) {
      statusText = context.l10n.t(
        'budget.receives_amount',
        params: {
          'amount': AppFormatters.currency(
            context,
            amount: amount,
            currencyCode: currency,
          ),
        },
      );
    } else {
      statusText = context.l10n.t('budget.settled');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.secondaryContainer,
            foregroundColor: colorScheme.onSecondaryContainer,
            child: Text(
              participant.user.initials.isEmpty
                  ? '?'
                  : participant.user.initials,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          Text(
            AppFormatters.currency(
              context,
              amount: amount,
              currencyCode: currency,
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: balance > 0
                  ? colorScheme.primary
                  : balance < 0
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
