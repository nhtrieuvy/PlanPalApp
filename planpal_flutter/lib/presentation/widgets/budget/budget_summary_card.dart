import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

class BudgetSummaryCard extends StatelessWidget {
  final BudgetModel summary;

  const BudgetSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (summary.spentPercentage.clamp(0, 100) / 100).toDouble();
    final accent = summary.overBudget
        ? AppColors.error
        : summary.nearLimit
        ? AppColors.warning
        : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withAlpha(24),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Budget Overview',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.hasBudgetConfigured
                          ? '${summary.spentPercentage.toStringAsFixed(1)}% spent'
                          : 'No budget configured yet',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: summary.hasBudgetConfigured ? progress : 0,
              minHeight: 12,
              backgroundColor: theme.colorScheme.outlineVariant.withAlpha(70),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricChip(
                label: 'Budget',
                value: _formatCurrency(summary.totalBudget, summary.currency),
                color: AppColors.primary,
              ),
              _MetricChip(
                label: 'Spent',
                value: _formatCurrency(summary.totalSpent, summary.currency),
                color: AppColors.warning,
              ),
              _MetricChip(
                label: 'Remaining',
                value: _formatCurrency(
                  summary.remainingBudget,
                  summary.currency,
                ),
                color: summary.remainingBudget < 0
                    ? AppColors.error
                    : AppColors.success,
              ),
              _MetricChip(
                label: 'Expenses',
                value: summary.expenseCount.toString(),
                color: AppColors.info,
              ),
            ],
          ),
          if (summary.overBudget || summary.nearLimit) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withAlpha(18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Icon(
                    summary.overBudget
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    color: accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      summary.overBudget
                          ? 'This plan is over budget.'
                          : 'This plan is close to its budget limit.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatCurrency(double amount, String currency) {
    final symbol = currency.toUpperCase() == 'VND'
        ? '₫'
        : currency.toUpperCase();
    return NumberFormat.currency(
      locale: 'vi_VN',
      symbol: symbol,
    ).format(amount);
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
