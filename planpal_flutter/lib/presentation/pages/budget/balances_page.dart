import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/budget_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

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
            onPressed: () =>
                ref.read(balancesProvider(planId).notifier).refresh(),
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
        data: (summary) =>
            _BalanceContent(planTitle: planTitle, summary: summary),
      ),
    );
  }
}

class _BalanceContent extends ConsumerWidget {
  final String planTitle;
  final BalanceSummaryModel summary;

  const _BalanceContent({required this.planTitle, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(balancesProvider(summary.planId).notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            planTitle,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle(context, context.l10n.t('budget.who_owes_whom')),
          const SizedBox(height: 8),
          if (summary.settlementSuggestions.isEmpty)
            _emptyCard(context, context.l10n.t('budget.all_balances_settled'))
          else
            ...summary.settlementSuggestions.map(
              (suggestion) => _DebtSuggestionCard(
                planId: summary.planId,
                currency: summary.currency,
                suggestion: suggestion,
              ),
            ),
          const SizedBox(height: 20),
          _sectionTitle(context, context.l10n.t('budget.member_balances')),
          const SizedBox(height: 8),
          ...summary.balances.map(
            (balance) =>
                _BalanceCard(balance: balance, currency: summary.currency),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  Widget _emptyCard(BuildContext context, String text) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}

class _DebtSuggestionCard extends ConsumerStatefulWidget {
  final String planId;
  final String currency;
  final DebtSuggestionModel suggestion;

  const _DebtSuggestionCard({
    required this.planId,
    required this.currency,
    required this.suggestion,
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
    final currentUserId = ref.watch(authNotifierProvider).user?.id;
    final canRecord = currentUserId == suggestion.fromUser.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t(
                'budget.owes_to',
                params: {
                  'from': suggestion.fromUser.fullName,
                  'to': suggestion.toUser.fullName,
                },
              ),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              AppFormatters.currency(
                context,
                amount: suggestion.amount,
                currencyCode: widget.currency,
              ),
            ),
            if (canRecord) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _recordSettlement,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(context.l10n.t('budget.mark_as_settled')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _recordSettlement() async {
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
          );
      ref.invalidate(balancesProvider(widget.planId));
      if (!mounted) return;
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('budget.settlement_recorded'),
      );
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, error, showDialog: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _BalanceCard extends StatelessWidget {
  final UserBalanceModel balance;
  final String currency;

  const _BalanceCard({required this.balance, required this.currency});

  @override
  Widget build(BuildContext context) {
    final color = balance.netBalance >= 0
        ? Colors.green
        : Theme.of(context).colorScheme.error;
    final label = balance.netBalance >= 0
        ? context.l10n.t('budget.gets_back')
        : context.l10n.t('budget.owes');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(child: Text(_initials(balance.user))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    balance.user.fullName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    context.l10n.t(
                      'budget.paid_owes',
                      params: {
                        'paid': AppFormatters.currency(
                          context,
                          amount: balance.totalPaid,
                          currencyCode: currency,
                        ),
                        'owed': AppFormatters.currency(
                          context,
                          amount: balance.totalOwed,
                          currencyCode: currency,
                        ),
                      },
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              '$label ${AppFormatters.currency(context, amount: balance.netBalance.abs(), currencyCode: currency)}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(BalanceUser user) {
    final name = user.fullName.trim().isNotEmpty
        ? user.fullName
        : user.username;
    final parts = name.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
