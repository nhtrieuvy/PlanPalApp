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
          onRetry: () =>
              ref.read(balancesProvider(planId).notifier).refresh(),
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalToReceive = summary.balances
        .where((item) => item.netBalance > 0)
        .fold<double>(0, (sum, item) => sum + item.netBalance);
    final totalToPay = summary.balances
        .where((item) => item.netBalance < 0)
        .fold<double>(0, (sum, item) => sum + item.netBalance.abs());

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(balancesProvider(summary.planId).notifier).refresh(),
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
                ),
              ),
            ),
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
          colors: [colorScheme.primaryContainer, colorScheme.secondaryContainer],
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
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = ref.watch(authNotifierProvider).user?.id;
    final canRecord = currentUserId == suggestion.fromUser.id;
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
              tooltip: context.l10n.t('budget.mark_as_settled'),
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
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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
          AppFormatters.currency(context, amount: amount, currencyCode: currency),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

String _displayName(BalanceUser user) {
  return user.fullName.trim().isNotEmpty ? user.fullName : user.username;
}
