import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/budget_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

/// A plan-level ledger. Expense details stay scoped to one bill; this page
/// aggregates every shared expense and completed settlement in the plan.
class BalancesPage extends ConsumerWidget {
  final String planId;
  final String planTitle;

  const BalancesPage({
    super.key,
    required this.planId,
    required this.planTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(balancesProvider(planId));
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('budget.balances')),
        actions: [
          IconButton(
            tooltip: l10n.t('common.refresh'),
            onPressed: () => _refreshAll(ref),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: state.when(
        loading: () => const AppSkeleton.list(itemCount: 5),
        error: (error, _) => AppError(
          message: ErrorDisplayService.getUserFriendlyMessage(error),
          onRetry: () => ref.read(balancesProvider(planId).notifier).refresh(),
        ),
        data: (summary) => ResponsiveContent(
          mediumMaxWidth: 760,
          expandedMaxWidth: 960,
          child: _BalanceContent(planTitle: planTitle, summary: summary),
        ),
      ),
    );
  }

  Future<void> _refreshAll(WidgetRef ref) async {
    await ref.read(balancesProvider(planId).notifier).refresh();
    ref.invalidate(settlementsProvider(planId));
  }
}

class _BalanceContent extends ConsumerWidget {
  final String planTitle;
  final BalanceSummaryModel summary;

  const _BalanceContent({required this.planTitle, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settlementsAsync = ref.watch(settlementsProvider(summary.planId));
    final pendingSettlements =
        settlementsAsync.valueOrNull
            ?.where((item) => item.status == 'pending')
            .toList() ??
        const <SettlementModel>[];
    final totalToReceive = summary.balances
        .where((item) => item.netBalance > 0)
        .fold<double>(0, (sum, item) => sum + item.netBalance);
    final totalToPay = summary.balances
        .where((item) => item.netBalance < 0)
        .fold<double>(0, (sum, item) => sum + item.netBalance.abs());

    return RefreshIndicator(
      onRefresh: () => _refreshAll(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            planTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.t('budget.balances_description'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          _LedgerHero(
            summary: summary,
            totalToReceive: totalToReceive,
            totalToPay: totalToPay,
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            icon: Icons.swap_horiz_rounded,
            title: l10n.t('budget.who_owes_whom'),
          ),
          const SizedBox(height: 10),
          if (summary.settlementSuggestions.isEmpty)
            _EmptyBalanceCard(text: l10n.t('budget.all_balances_settled'))
          else
            ...summary.settlementSuggestions.map(
              (suggestion) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DebtSuggestionCard(
                  planId: summary.planId,
                  currency: summary.currency,
                  suggestion: suggestion,
                  hasPendingRequest: pendingSettlements.any(
                    (item) =>
                        item.fromUserId == suggestion.fromUser.id &&
                        item.toUserId == suggestion.toUser.id,
                  ),
                ),
              ),
            ),
          if (pendingSettlements.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionTitle(
              icon: Icons.hourglass_top_rounded,
              title: l10n.t('budget.pending_settlements'),
            ),
            const SizedBox(height: 10),
            ...pendingSettlements.map(
              (settlement) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PendingSettlementCard(settlement: settlement),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.people_alt_outlined,
            title: l10n.t('budget.member_balances'),
          ),
          const SizedBox(height: 10),
          ...summary.balances.map(
            (balance) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BalanceCard(balance: balance, currency: summary.currency),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshAll(WidgetRef ref) async {
    await ref.read(balancesProvider(summary.planId).notifier).refresh();
    ref.invalidate(settlementsProvider(summary.planId));
  }
}

class _LedgerHero extends StatelessWidget {
  final BalanceSummaryModel summary;
  final double totalToReceive;
  final double totalToPay;

  const _LedgerHero({
    required this.summary,
    required this.totalToReceive,
    required this.totalToPay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.t(
                    'budget.total_shared_expenses',
                    params: {
                      'amount': AppFormatters.currency(
                        context,
                        amount: summary.totalExpenses,
                        currencyCode: summary.currency,
                      ),
                    },
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: context.l10n.t('budget.total_to_receive'),
                  amount: totalToReceive,
                  currency: summary.currency,
                  icon: Icons.south_west_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeroMetric(
                  label: context.l10n.t('budget.total_to_pay'),
                  amount: totalToPay,
                  currency: summary.currency,
                  icon: Icons.north_east_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;
  final IconData icon;

  const _HeroMetric({
    required this.label,
    required this.amount,
    required this.currency,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            AppFormatters.currency(
              context,
              amount: amount,
              currencyCode: currency,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _EmptyBalanceCard extends StatelessWidget {
  final String text;

  const _EmptyBalanceCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.task_alt_rounded, color: colorScheme.tertiary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _DebtSuggestionCard extends ConsumerStatefulWidget {
  final String planId;
  final String currency;
  final DebtSuggestionModel suggestion;
  final bool hasPendingRequest;

  const _DebtSuggestionCard({
    required this.planId,
    required this.currency,
    required this.suggestion,
    required this.hasPendingRequest,
  });

  @override
  ConsumerState<_DebtSuggestionCard> createState() =>
      _DebtSuggestionCardState();
}

class _DebtSuggestionCardState extends ConsumerState<_DebtSuggestionCard> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final suggestion = widget.suggestion;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = ref.watch(authNotifierProvider).user?.id;
    final canRecord =
        currentUserId == suggestion.fromUser.id && !widget.hasPendingRequest;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.errorContainer,
            foregroundColor: colorScheme.onErrorContainer,
            child: const Icon(Icons.arrow_forward_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t(
                    'budget.owes_to',
                    params: {
                      'from': _displayName(suggestion.fromUser),
                      'to': _displayName(suggestion.toUser),
                    },
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppFormatters.currency(
                    context,
                    amount: suggestion.amount,
                    currencyCode: widget.currency,
                  ),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (canRecord)
            IconButton.filled(
              tooltip: context.l10n.t('budget.request_payment_confirmation'),
              onPressed: _isSubmitting ? null : _recordSettlement,
              icon: _isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
            ),
        ],
      ),
    );
  }

  Future<void> _recordSettlement() async {
    final draft = await showModalBottomSheet<_SettlementRequestDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SettlementRequestSheet(),
    );
    if (draft == null || !mounted) return;
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(budgetRepositoryProvider)
          .createSettlement(
            planId: widget.planId,
            fromUserId: widget.suggestion.fromUser.id,
            toUserId: widget.suggestion.toUser.id,
            amount: widget.suggestion.amount,
            currency: widget.currency,
            paymentNote: draft.paymentNote,
            receiptFile: draft.receiptFile,
          );
      ref.invalidate(balancesProvider(widget.planId));
      ref.invalidate(settlementsProvider(widget.planId));
      if (!mounted) return;
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('budget.payment_request_sent'),
      );
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, error, showDialog: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _PendingSettlementCard extends ConsumerStatefulWidget {
  const _PendingSettlementCard({required this.settlement});

  final SettlementModel settlement;

  @override
  ConsumerState<_PendingSettlementCard> createState() =>
      _PendingSettlementCardState();
}

class _PendingSettlementCardState
    extends ConsumerState<_PendingSettlementCard> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final settlement = widget.settlement;
    final colors = Theme.of(context).colorScheme;
    final currentUserId = ref.watch(authNotifierProvider).user?.id;
    final canRespond = currentUserId == settlement.toUserId;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_send_rounded, color: colors.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_displayName(settlement.fromUser)} → '
                  '${_displayName(settlement.toUser)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                AppFormatters.currency(
                  context,
                  amount: settlement.amount,
                  currencyCode: settlement.currency,
                ),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          if (settlement.paymentNote.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(settlement.paymentNote),
          ],
          if (settlement.receiptUrl != null) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.attach_file_rounded),
              title: Text(context.l10n.t('budget.receipt')),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => launchUrl(
                Uri.parse(settlement.receiptUrl!),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
          if (canRespond) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _submitting ? null : () => _respond('reject'),
                  child: Text(context.l10n.t('budget.reject_payment')),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _submitting ? null : () => _respond('complete'),
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(context.l10n.t('budget.confirm_payment')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _respond(String action) async {
    var rejectionReason = '';
    if (action == 'reject') {
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          var value = '';
          return AlertDialog(
            title: Text(context.l10n.t('budget.reject_payment')),
            content: TextField(
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              onChanged: (text) => value = text,
              decoration: InputDecoration(
                labelText: context.l10n.t('budget.rejection_reason'),
                hintText: context.l10n.t('budget.rejection_reason_hint'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.l10n.t('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(value.trim()),
                child: Text(context.l10n.t('budget.reject_payment')),
              ),
            ],
          );
        },
      );
      if (reason == null || !mounted) return;
      rejectionReason = reason;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(budgetRepositoryProvider)
          .respondToSettlement(
            widget.settlement.id,
            action: action,
            rejectionReason: rejectionReason,
          );
      ref.invalidate(settlementsProvider(widget.settlement.planId));
      ref.invalidate(balancesProvider(widget.settlement.planId));
      if (!mounted) return;
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t(
          action == 'complete'
              ? 'budget.payment_confirmed'
              : 'budget.payment_rejected',
        ),
      );
    } catch (error) {
      if (mounted) ErrorDisplayService.handleError(context, error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _SettlementRequestDraft {
  const _SettlementRequestDraft({required this.paymentNote, this.receiptFile});

  final String paymentNote;
  final XFile? receiptFile;
}

class _SettlementRequestSheet extends StatefulWidget {
  const _SettlementRequestSheet();

  @override
  State<_SettlementRequestSheet> createState() =>
      _SettlementRequestSheetState();
}

class _SettlementRequestSheetState extends State<_SettlementRequestSheet> {
  final _paymentNote = TextEditingController();
  XFile? _receiptFile;
  String? _receiptName;

  @override
  void dispose() {
    _paymentNote.dispose();
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t('budget.request_payment_confirmation'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.t('budget.payment_proof_hint'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
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
                _receiptName ?? context.l10n.t('budget.attach_receipt'),
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  _SettlementRequestDraft(
                    paymentNote: _paymentNote.text.trim(),
                    receiptFile: _receiptFile,
                  ),
                ),
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  context.l10n.t('budget.request_payment_confirmation'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

class _BalanceCard extends StatelessWidget {
  final UserBalanceModel balance;
  final String currency;

  const _BalanceCard({required this.balance, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCreditor = balance.netBalance > 0;
    final isSettled = balance.netBalance.abs() < 0.005;
    final accent = isSettled
        ? colorScheme.tertiary
        : (isCreditor ? colorScheme.primary : colorScheme.error);
    final label = isSettled
        ? context.l10n.t('budget.settled')
        : (isCreditor
              ? context.l10n.t('budget.gets_back')
              : context.l10n.t('budget.owes'));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.secondaryContainer,
                foregroundColor: colorScheme.onSecondaryContainer,
                child: Text(_initials(balance.user)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _displayName(balance.user),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(color: accent),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppFormatters.currency(
                      context,
                      amount: balance.netBalance.abs(),
                      currencyCode: currency,
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LedgerValue(
                  label: context.l10n.t('budget.total_paid'),
                  amount: balance.totalPaid,
                  currency: currency,
                ),
              ),
              Expanded(
                child: _LedgerValue(
                  label: context.l10n.t('budget.total_owed'),
                  amount: balance.totalOwed,
                  currency: currency,
                ),
              ),
              Expanded(
                child: _LedgerValue(
                  label: context.l10n.t('budget.settlements'),
                  amount: balance.settlementPaid + balance.settlementReceived,
                  currency: currency,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(BalanceUser user) {
    final name = _displayName(user);
    final parts = name.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _LedgerValue extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;

  const _LedgerValue({
    required this.label,
    required this.amount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          AppFormatters.currency(
            context,
            amount: amount,
            currencyCode: currency,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

String _displayName(BalanceUser user) {
  return user.fullName.trim().isNotEmpty ? user.fullName : user.username;
}
