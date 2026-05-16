import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

class ExpenseItem extends StatelessWidget {
  final ExpenseModel expense;
  final String currency;

  const ExpenseItem({super.key, required this.expense, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final payerName = expense.paidByUser.fullName.isNotEmpty
        ? expense.paidByUser.fullName
        : expense.paidByUser.username;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expense.category,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      AppFormatters.currency(
                        context,
                        amount: expense.amount,
                        currencyCode: currency,
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.t('budget.paid_by_name', params: {'name': payerName}),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (expense.participants.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.t(
                      'budget.split_info',
                      params: {
                        'strategy': _localizedSplitStrategy(
                          l10n,
                          expense.splitStrategy,
                        ),
                        'count': '${expense.participants.length}',
                      },
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (expense.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    expense.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  AppFormatters.fullDateTime(context, expense.createdAt),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _localizedSplitStrategy(AppLocalizations l10n, String strategy) {
    switch (strategy) {
      case 'percentage':
        return l10n.t('budget.split_percentage');
      case 'exact':
        return l10n.t('budget.split_exact');
      case 'equal':
      default:
        return l10n.t('budget.split_equal');
    }
  }
}
