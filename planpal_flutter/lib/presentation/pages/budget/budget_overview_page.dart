import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/budget_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/presentation/pages/budget/add_expense_form.dart';
import 'package:planpal_flutter/presentation/pages/budget/balances_page.dart';
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
    final l10n = context.l10n;
    final budgetAsync = ref.watch(budgetProvider(widget.planId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('budget.overview_title')),
        actions: [
          IconButton(
            tooltip: l10n.t('common.refresh'),
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
        label: Text(l10n.t('budget.quick_add')),
      ),
      body: RefreshablePageWrapper(
        onRefresh: _refresh,
        child: budgetAsync.when(
          loading: () => const AppSkeleton.list(itemCount: 4),
          error: (error, _) => AppError(
            message: ErrorDisplayService.getUserFriendlyMessage(error),
            onRetry: _refresh,
            retryLabel: l10n.t('common.retry'),
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
          context.l10n.t('budget.track_description'),
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
          label: Text(context.l10n.t('budget.view_expenses')),
        ),
        OutlinedButton.icon(
          onPressed: _openBalances,
          icon: const Icon(Icons.account_balance_rounded),
          label: const Text('Balances'),
        ),
        OutlinedButton.icon(
          onPressed: _openAddExpense,
          icon: const Icon(Icons.add_card_rounded),
          label: Text(context.l10n.t('budget.add_expense')),
        ),
        if (widget.canManageBudget)
          OutlinedButton.icon(
            onPressed: () => _openBudgetDialog(summary),
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(
              summary.hasBudgetConfigured
                  ? context.l10n.t('budget.update_budget')
                  : context.l10n.t('budget.set_budget'),
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
    final members = await _loadPlanMembers();
    if (!mounted) return;
    final result = await Navigator.of(context).push<ExpenseCreateResult>(
      MaterialPageRoute(
        builder: (context) => AddExpenseForm(
          planId: widget.planId,
          planTitle: widget.planTitle,
          members: members,
        ),
      ),
    );

    if (result == null || !mounted) return;

    ref.invalidate(budgetProvider(widget.planId));
    ref.invalidate(expensesProvider(ExpenseListQuery(planId: widget.planId)));

    final warnings = result.warnings;
    if (warnings.isEmpty) {
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('budget.expense_added_successfully'),
      );
      return;
    }

    final buffer = StringBuffer(context.l10n.t('budget.expense_added'));
    for (final warning in warnings) {
      buffer.write('\n- ${warning.message}');
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(buffer.toString())));
  }

  Future<void> _openBalances() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            BalancesPage(planId: widget.planId, planTitle: widget.planTitle),
      ),
    );
    await _refresh();
  }

  Future<List<UserSummary>> _loadPlanMembers() async {
    try {
      final plan = await ref
          .read(planRepositoryProvider)
          .getPlanDetail(widget.planId);
      return plan.collaborators;
    } catch (_) {
      return const [];
    }
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
          summary.hasBudgetConfigured
              ? context.l10n.t('budget.dialog_title_update')
              : context.l10n.t('budget.dialog_title_set'),
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
                decoration: InputDecoration(
                  labelText: context.l10n.t('budget.total_budget'),
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  if (parsed == null || parsed < 0) {
                    return context.l10n.t(
                      'budget.validation_non_negative_amount',
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: currencyController,
                decoration: InputDecoration(
                  labelText: context.l10n.t('budget.currency'),
                  prefixIcon: const Icon(Icons.currency_exchange_rounded),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.length < 3 || text.length > 10) {
                    return context.l10n.t('budget.validation_currency_length');
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
            child: Text(context.l10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(context.l10n.t('common.save')),
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
        context.l10n.t('budget.saved_successfully'),
      );
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, error, showDialog: true);
    }
  }
}
