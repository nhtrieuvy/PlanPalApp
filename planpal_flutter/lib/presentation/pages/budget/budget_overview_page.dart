import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/riverpod/budget_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/presentation/pages/budget/add_expense_form.dart';
import 'package:planpal_flutter/presentation/pages/budget/expense_list_page.dart';
import 'package:planpal_flutter/presentation/widgets/budget/budget_breakdown_card.dart';
import 'package:planpal_flutter/presentation/widgets/budget/budget_summary_card.dart';
import 'package:planpal_flutter/presentation/widgets/budget/budget_trend_chart.dart';
import 'package:planpal_flutter/presentation/widgets/common/refreshable_page_wrapper.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class BudgetOverviewPage extends ConsumerStatefulWidget {
  final String planId;
  final String planTitle;
  final bool canManageBudget;

  const BudgetOverviewPage({
    super.key,
    required this.planId,
    required this.planTitle,
    this.canManageBudget = false,
  });

  @override
  ConsumerState<BudgetOverviewPage> createState() => _BudgetOverviewPageState();
}

class _BudgetOverviewPageState extends ConsumerState<BudgetOverviewPage> {
  @override
  Widget build(BuildContext context) {
    final budgetAsync = ref.watch(budgetProvider(widget.planId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget Overview'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddExpense,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Quick add'),
      ),
      body: RefreshablePageWrapper(
        onRefresh: _refresh,
        child: budgetAsync.when(
          loading: () => const AppSkeleton.list(itemCount: 4),
          error: (error, _) => AppError(
            message: ErrorDisplayService.getUserFriendlyMessage(error),
            onRetry: _refresh,
            retryLabel: 'Retry',
          ),
          data: (summary) => _buildContent(context, summary),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, BudgetModel summary) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.planTitle,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Track budget health, per-user contributions, and recent spending.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        BudgetSummaryCard(summary: summary),
        const SizedBox(height: 16),
        _buildActionRow(context, summary),
        const SizedBox(height: 16),
        BudgetTrendChart(points: summary.trend),
        const SizedBox(height: 16),
        BudgetBreakdownCard(
          items: summary.breakdown,
          currency: summary.currency,
        ),
      ],
    );
  }

  Widget _buildActionRow(BuildContext context, BudgetModel summary) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: _openExpenseList,
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text('View expenses'),
        ),
        OutlinedButton.icon(
          onPressed: _openAddExpense,
          icon: const Icon(Icons.add_card_rounded),
          label: const Text('Add expense'),
        ),
        if (widget.canManageBudget)
          OutlinedButton.icon(
            onPressed: () => _openBudgetDialog(summary),
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(
              summary.hasBudgetConfigured ? 'Update budget' : 'Set budget',
            ),
          ),
      ],
    );
  }

  Future<void> _refresh() async {
    await ref.read(budgetProvider(widget.planId).notifier).refresh();
  }

  Future<void> _openExpenseList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ExpenseListPage(planId: widget.planId, planTitle: widget.planTitle),
      ),
    );
    await _refresh();
  }

  Future<void> _openAddExpense() async {
    final result = await Navigator.of(context).push<ExpenseCreateResult>(
      MaterialPageRoute(
        builder: (context) =>
            AddExpenseForm(planId: widget.planId, planTitle: widget.planTitle),
      ),
    );

    if (result == null || !mounted) return;

    ref.invalidate(budgetProvider(widget.planId));
    ref.invalidate(expensesProvider(ExpenseListQuery(planId: widget.planId)));

    final warnings = result.warnings;
    if (warnings.isEmpty) {
      ErrorDisplayService.showSuccessSnackbar(
        context,
        'Expense added successfully',
      );
      return;
    }

    final buffer = StringBuffer('Expense added');
    for (final warning in warnings) {
      buffer.write('\n- ${warning.message}');
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(buffer.toString())));
  }

  Future<void> _openBudgetDialog(BudgetModel summary) async {
    final amountController = TextEditingController(
      text: summary.totalBudget > 0
          ? summary.totalBudget.toStringAsFixed(0)
          : '',
    );
    final currencyController = TextEditingController(text: summary.currency);
    final formKey = GlobalKey<FormState>();

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          summary.hasBudgetConfigured ? 'Update budget' : 'Set budget',
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Total budget',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  if (parsed == null || parsed < 0) {
                    return 'Enter a valid non-negative amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: currencyController,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  prefixIcon: Icon(Icons.currency_exchange_rounded),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.length < 3 || text.length > 10) {
                    return 'Currency must be between 3 and 10 characters';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true) return;

    try {
      await ref
          .read(budgetProvider(widget.planId).notifier)
          .updateBudget(
            totalBudget: double.parse(amountController.text.trim()),
            currency: currencyController.text.trim(),
          );
      if (!mounted) return;
      ErrorDisplayService.showSuccessSnackbar(
        context,
        'Budget saved successfully',
      );
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, error, showDialog: true);
    }
  }
}
