import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';

class ExpenseDetailPage extends StatelessWidget {
  final ExpenseModel expense;

  const ExpenseDetailPage({super.key, required this.expense});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('budget.expense_detail'))),
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
