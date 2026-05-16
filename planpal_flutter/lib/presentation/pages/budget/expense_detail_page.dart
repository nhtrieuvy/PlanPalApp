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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('budget.expense_detail'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            expense.category,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            AppFormatters.currency(
              context,
              amount: expense.amount,
              currencyCode: expense.currency,
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          _row(
            context,
            l10n.t('budget.paid_by'),
            _userName(expense.paidByUser),
          ),
          _row(
            context,
            l10n.t('budget.split_strategy'),
            _localizedSplitStrategy(l10n, expense.splitStrategy),
          ),
          if (expense.description.trim().isNotEmpty)
            _row(context, l10n.t('budget.description'), expense.description),
          const SizedBox(height: 20),
          Text(
            l10n.t('budget.participants'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...expense.participants.map(
            (participant) => Card(
              child: ListTile(
                title: Text(_userName(participant.user)),
                subtitle: Text(
                  l10n.t(
                    'budget.owes_amount',
                    params: {
                      'amount': AppFormatters.currency(
                        context,
                        amount: participant.owedAmount,
                        currencyCode: expense.currency,
                      ),
                    },
                  ),
                ),
                trailing: Text(
                  AppFormatters.currency(
                    context,
                    amount: participant.balance.abs(),
                    currencyCode: expense.currency,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }

  String _userName(user) {
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
      case 'equal':
      default:
        return l10n.t('budget.split_equal');
    }
  }
}
