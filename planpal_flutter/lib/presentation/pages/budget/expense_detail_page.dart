import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';

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
          PopupMenuButton<String>(
            tooltip: l10n.t('common.more'),
            onSelected: (value) {
              if (value == 'delete') _deleteExpense(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.t('budget.delete_expense'),
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ResponsiveContent(
        mediumMaxWidth: 720,
        expandedMaxWidth: 840,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _HeroSummary(expense: expense),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _correctExpense(context, ref),
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(l10n.t('budget.correct_expense')),
              ),
            ),
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
              children: [
                ...expense.participants.map(
                  (participant) => _ParticipantRow(
                    participant: participant,
                    currency: expense.currency,
                  ),
                ),
                const Divider(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _correctExpense(context, ref, participantsOnly: true),
                    icon: const Icon(Icons.group_add_outlined),
                    label: Text(l10n.t('budget.edit_participants')),
                  ),
                ),
              ],
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
      ),
    );
  }

  Future<void> _correctExpense(
    BuildContext context,
    WidgetRef ref, {
    bool participantsOnly = false,
  }) async {
    final membersFuture = _loadParticipants(ref);
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final draft = await showModalBottomSheet<_ExpenseCorrectionDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: isWide ? const BoxConstraints(maxWidth: 760) : null,
      builder: (_) => FutureBuilder<List<UserSummary>>(
        future: membersFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 280,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _ExpenseCorrectionSheet(
            expense: expense,
            members: snapshot.data!,
            participantsOnly: participantsOnly,
          );
        },
      ),
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
            receiptFile: draft.receiptFile,
            splitStrategy: draft.splitStrategy,
            participants: draft.participants,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (context.mounted) {
        ErrorDisplayService.handleError(context, error, showDialog: true);
      }
    }
  }

  Future<List<UserSummary>> _loadParticipants(WidgetRef ref) async {
    final users = <String, UserSummary>{
      expense.paidByUser.id: expense.paidByUser,
      for (final participant in expense.participants)
        participant.user.id: participant.user,
    };
    try {
      final plan = await ref
          .read(planRepositoryProvider)
          .getPlanDetail(expense.planId);
      users[plan.creator.id] = plan.creator;
      for (final collaborator in plan.collaborators) {
        users[collaborator.id] = collaborator;
      }
    } catch (_) {
      // Current expense members still allow a safe correction when plan detail
      // is temporarily unavailable.
    }
    return users.values.toList();
  }

  Future<void> _deleteExpense(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('budget.delete_expense_title')),
        content: Text(
          context.l10n.t(
            'budget.delete_expense_description',
            params: {'category': expense.category},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.t('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(budgetRepositoryProvider)
          .deleteExpense(expense.planId, expense.id);
      if (context.mounted) Navigator.of(context).pop(true);
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
    required this.splitStrategy,
    required this.participants,
    this.receiptFile,
  });

  final double amount;
  final String category;
  final String description;
  final String paymentNote;
  final String reason;
  final String splitStrategy;
  final List<ExpenseParticipantInput> participants;
  final XFile? receiptFile;
}

class _ExpenseCorrectionSheet extends StatefulWidget {
  const _ExpenseCorrectionSheet({
    required this.expense,
    required this.members,
    this.participantsOnly = false,
  });

  final ExpenseModel expense;
  final List<UserSummary> members;
  final bool participantsOnly;

  @override
  State<_ExpenseCorrectionSheet> createState() =>
      _ExpenseCorrectionSheetState();
}

enum _ExpenseCorrectionSection { details, participants }

class _ExpenseCorrectionSheetState extends State<_ExpenseCorrectionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _paymentNote;
  final _reason = TextEditingController();
  XFile? _receiptFile;
  String? _receiptName;
  late String _splitStrategy;
  late final Set<String> _selectedParticipantIds;
  final Map<String, TextEditingController> _splitControllers = {};
  late _ExpenseCorrectionSection _section;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.expense.amount.toStringAsFixed(2),
    );
    _category = TextEditingController(text: widget.expense.category);
    _description = TextEditingController(text: widget.expense.description);
    _paymentNote = TextEditingController(text: widget.expense.paymentNote);
    _section = widget.participantsOnly
        ? _ExpenseCorrectionSection.participants
        : _ExpenseCorrectionSection.details;
    _splitStrategy = widget.expense.splitStrategy;
    _selectedParticipantIds = widget.expense.participants
        .map((item) => item.user.id)
        .toSet();
    if (_selectedParticipantIds.isEmpty && widget.members.isNotEmpty) {
      _selectedParticipantIds.addAll(widget.members.map((item) => item.id));
    }
    for (final member in widget.members) {
      ExpenseParticipantModel? participant;
      for (final item in widget.expense.participants) {
        if (item.user.id == member.id) {
          participant = item;
          break;
        }
      }
      final value = _splitStrategy == 'percentage' && participant != null
          ? participant.owedAmount / widget.expense.amount * 100
          : participant?.owedAmount;
      _splitControllers[member.id] = TextEditingController(
        text: value == null ? '' : value.toStringAsFixed(2),
      );
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _description.dispose();
    _paymentNote.dispose();
    _reason.dispose();
    for (final controller in _splitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final height = mediaQuery.size.height > 860
        ? 760.0
        : mediaQuery.size.height * .88;
    final showParticipants = _section == _ExpenseCorrectionSection.participants;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.t(
                                widget.participantsOnly
                                    ? 'budget.edit_participants'
                                    : 'budget.correct_expense',
                              ),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.l10n.t(
                                showParticipants
                                    ? 'budget.edit_participants_hint'
                                    : 'budget.correct_expense_hint',
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.t('common.close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                if (!widget.participantsOnly)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: SegmentedButton<_ExpenseCorrectionSection>(
                      expandedInsets: EdgeInsets.zero,
                      segments: [
                        ButtonSegment(
                          value: _ExpenseCorrectionSection.details,
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: Text(
                            context.l10n.t('budget.expense_information'),
                          ),
                        ),
                        ButtonSegment(
                          value: _ExpenseCorrectionSection.participants,
                          icon: const Icon(Icons.group_outlined),
                          label: Text(context.l10n.t('budget.split_expense')),
                        ),
                      ],
                      selected: {_section},
                      onSelectionChanged: _selectSection,
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey(_section),
                        child: showParticipants
                            ? _buildParticipantsSection(context)
                            : _buildDetailsSection(context),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    children: [
                      if (showParticipants && !widget.participantsOnly) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(
                              () =>
                                  _section = _ExpenseCorrectionSection.details,
                            ),
                            child: Text(context.l10n.t('wizard.back')),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: showParticipants
                              ? _submit
                              : _continueToParticipants,
                          child: Text(
                            context.l10n.t(
                              showParticipants ? 'common.save' : 'wizard.next',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsSection(BuildContext context) {
    return Column(
      key: const ValueKey('expense-details'),
      children: [
        TextFormField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
          trailing: _receiptFile == null
              ? const Icon(Icons.add_rounded)
              : IconButton(
                  tooltip: context.l10n.t('budget.remove_receipt'),
                  onPressed: () => setState(() {
                    _receiptFile = null;
                    _receiptName = null;
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
          onTap: _pickReceipt,
        ),
      ],
    );
  }

  Widget _buildParticipantsSection(BuildContext context) {
    return Column(
      key: const ValueKey('expense-participants'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t('budget.split_strategy'),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          expandedInsets: EdgeInsets.zero,
          segments: [
            ButtonSegment(
              value: 'equal',
              label: Text(context.l10n.t('budget.split_equal')),
            ),
            ButtonSegment(
              value: 'percentage',
              label: Text(context.l10n.t('budget.split_percentage')),
            ),
            ButtonSegment(
              value: 'exact',
              label: Text(context.l10n.t('budget.split_exact')),
            ),
          ],
          selected: {_splitStrategy},
          onSelectionChanged: (values) => setState(() {
            _splitStrategy = values.first;
          }),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.t('budget.participants'),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        ...widget.members.map(_buildParticipantRow),
        const SizedBox(height: 16),
        TextFormField(
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.l10n.t('budget.correction_reason'),
            hintText: context.l10n.t('budget.correction_reason_hint'),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? context.l10n.t('budget.correction_reason_required')
              : null,
        ),
      ],
    );
  }

  void _selectSection(Set<_ExpenseCorrectionSection> sections) {
    final next = sections.first;
    if (next == _ExpenseCorrectionSection.participants &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _section = next);
  }

  void _continueToParticipants() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _section = _ExpenseCorrectionSection.participants);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final participantError = _validateParticipants();
    if (participantError != null) {
      ErrorDisplayService.showErrorSnackbar(context, participantError);
      return;
    }
    Navigator.of(context).pop(
      _ExpenseCorrectionDraft(
        amount: double.parse(_amount.text.trim()),
        category: _category.text.trim(),
        description: _description.text.trim(),
        paymentNote: _paymentNote.text.trim(),
        reason: _reason.text.trim(),
        splitStrategy: _splitStrategy,
        participants: _buildParticipantInputs(),
        receiptFile: _receiptFile,
      ),
    );
  }

  Widget _buildParticipantRow(UserSummary member) {
    final selected = _selectedParticipantIds.contains(member.id);
    final name = member.fullName.trim().isNotEmpty
        ? member.fullName
        : member.username;
    return Row(
      children: [
        Checkbox(
          value: selected,
          onChanged: (value) => setState(() {
            if (value == true) {
              _selectedParticipantIds.add(member.id);
            } else {
              _selectedParticipantIds.remove(member.id);
            }
          }),
        ),
        Expanded(child: Text(name)),
        if (selected && _splitStrategy != 'equal')
          SizedBox(
            width: 112,
            child: TextFormField(
              controller: _splitControllers[member.id],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _splitStrategy == 'percentage'
                    ? context.l10n.t('budget.percent')
                    : context.l10n.t('budget.amount'),
              ),
            ),
          ),
      ],
    );
  }

  List<ExpenseParticipantInput> _buildParticipantInputs() {
    return _selectedParticipantIds.map((userId) {
      final value = double.tryParse(
        _splitControllers[userId]?.text.trim() ?? '',
      );
      return ExpenseParticipantInput(
        userId: userId,
        amount: _splitStrategy == 'exact' ? value : null,
        percentage: _splitStrategy == 'percentage' ? value : null,
      );
    }).toList();
  }

  String? _validateParticipants() {
    if (_selectedParticipantIds.isEmpty) {
      return context.l10n.t('budget.validation_participant_required');
    }
    if (_splitStrategy == 'equal') return null;
    var total = 0.0;
    for (final userId in _selectedParticipantIds) {
      final value = double.tryParse(
        _splitControllers[userId]?.text.trim() ?? '',
      );
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
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (_splitStrategy == 'exact' && (total - amount).abs() > 0.01) {
      return context.l10n.t('budget.validation_exact_total');
    }
    return null;
  }

  Future<void> _pickReceipt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: kIsWeb,
    );
    final file = result?.files.single;
    if (file == null || (!kIsWeb && file.path == null) || !mounted) return;
    if (file.size > 10 * 1024 * 1024) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('budget.receipt_too_large'),
      );
      return;
    }
    setState(() {
      _receiptFile = file.xFile;
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
