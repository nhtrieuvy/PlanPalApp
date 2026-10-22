import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/budget_providers.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/pages/budget/add_expense_form.dart';
import 'package:planpal_flutter/presentation/pages/budget/balances_page.dart';
import 'package:planpal_flutter/presentation/pages/budget/expense_list_page.dart';
import 'package:planpal_flutter/presentation/widgets/budget/budget_breakdown_card.dart';
import 'package:planpal_flutter/presentation/widgets/budget/budget_summary_card.dart';
import 'package:planpal_flutter/presentation/widgets/budget/budget_trend_chart.dart';
import 'package:planpal_flutter/presentation/widgets/common/refreshable_page_wrapper.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';

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
      body: RefreshablePageWrapper(
        onRefresh: _refresh,
        child: budgetAsync.when(
          loading: () => const AppSkeleton.list(itemCount: 4),
          error: (error, _) => AppError(
            message: ErrorDisplayService.getUserFriendlyMessage(error),
            onRetry: _refresh,
            retryLabel: l10n.t('common.retry'),
          ),
          data: (summary) => ResponsiveContent(
            mediumMaxWidth: 860,
            expandedMaxWidth: 1120,
            child: _buildContent(context, summary),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, BudgetModel summary) {
    final insightsAsync = ref.watch(financeInsightsProvider(widget.planId));
    final recurringAsync = ref.watch(recurringExpensesProvider(widget.planId));
    final currentUserId = ref.watch(authNotifierProvider).user?.id;
    final primaryContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BudgetSummaryCard(summary: summary),
        const SizedBox(height: AppSpacing.md),
        _buildActions(context, summary),
        const SizedBox(height: AppSpacing.md),
        insightsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
          data: (insights) => _FinanceInsightsCard(insights: insights),
        ),
        recurringAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: _RecurringExpensesCard(
                    items: items,
                    canManageBudget: widget.canManageBudget,
                    currentUserId: currentUserId,
                    onToggle: _toggleRecurringExpense,
                  ),
                ),
        ),
      ],
    );
    final analysisContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JourneySectionHeader(
          title: context.l10n.t('budget.finance_insights'),
          icon: Icons.query_stats_rounded,
        ),
        const SizedBox(height: AppSpacing.sm),
        BudgetTrendChart(points: summary.trend),
        const SizedBox(height: AppSpacing.md),
        BudgetBreakdownCard(
          items: summary.breakdown,
          currency: summary.currency,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          JourneyPageHeader(
            eyebrow: context.l10n.t('budget.overview_title'),
            title: widget.planTitle,
            subtitle: context.l10n.t('budget.track_description'),
            leadingIcon: Icons.account_balance_wallet_outlined,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: constraints.maxWidth >= 900
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: primaryContent),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(flex: 5, child: analysisContent),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      primaryContent,
                      const SizedBox(height: AppSpacing.xl),
                      analysisContent,
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, BudgetModel summary) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _openAddExpense,
            icon: const Icon(Icons.add_card_rounded),
            label: Text(context.l10n.t('budget.add_expense')),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.outlined(
          onPressed: () => _showBudgetActions(context, summary),
          tooltip: context.l10n.t('common.manage'),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Future<void> _showBudgetActions(
    BuildContext context,
    BudgetModel summary,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.t('common.manage'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.receipt_long_rounded),
                title: Text(context.l10n.t('budget.view_expenses')),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openExpenseList();
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_rounded),
                title: Text(context.l10n.t('budget.balances')),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openBalances();
                },
              ),
              if (widget.canManageBudget)
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: Text(
                    summary.hasBudgetConfigured
                        ? context.l10n.t('budget.update_budget')
                        : context.l10n.t('budget.set_budget'),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openBudgetDialog(summary);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    await ref.read(budgetProvider(widget.planId).notifier).refresh();
    ref.invalidate(financeInsightsProvider(widget.planId));
    ref.invalidate(settlementsProvider(widget.planId));
    ref.invalidate(recurringExpensesProvider(widget.planId));
  }

  Future<void> _toggleRecurringExpense(
    RecurringExpenseModel item,
    bool isActive,
  ) async {
    try {
      await ref
          .read(budgetRepositoryProvider)
          .setRecurringExpenseActive(
            widget.planId,
            item.id,
            isActive: isActive,
          );
      ref.invalidate(recurringExpensesProvider(widget.planId));
      if (!mounted) return;
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t(
          isActive ? 'budget.recurrence_resumed' : 'budget.recurrence_paused',
        ),
      );
    } catch (error) {
      if (mounted) {
        ErrorDisplayService.handleError(context, error, showDialog: true);
      }
    }
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

class _FinanceInsightsCard extends StatelessWidget {
  const _FinanceInsightsCard({required this.insights});

  final FinanceInsightsModel insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final forecast = insights.forecast;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Text(
                context.l10n.t('budget.finance_insights'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InsightMetric(
                  label: context.l10n.t('budget.projected_total'),
                  value: AppFormatters.currency(
                    context,
                    amount: forecast.projectedTotal,
                    currencyCode: insights.currency,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsightMetric(
                  label: context.l10n.t('budget.daily_average'),
                  value: AppFormatters.currency(
                    context,
                    amount: forecast.dailyAverage,
                    currencyCode: insights.currency,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: forecast.projectedOverBudget
                  ? colors.errorContainer
                  : colors.tertiaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  forecast.projectedOverBudget
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.t(
                      forecast.projectedOverBudget
                          ? 'budget.forecast_over'
                          : 'budget.forecast_safe',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (insights.categories.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              context.l10n.t('budget.category_analysis'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ...insights.categories
                .take(4)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.category)),
                        Text('${item.percentage.toStringAsFixed(1)}%'),
                        const SizedBox(width: 10),
                        Text(
                          AppFormatters.currency(
                            context,
                            amount: item.amount,
                            currencyCode: insights.currency,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (insights.pendingSettlementCount > 0) ...[
            const Divider(height: 24),
            Text(
              '${context.l10n.t('budget.pending_confirmations')}: '
              '${insights.pendingSettlementCount}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecurringExpensesCard extends StatelessWidget {
  const _RecurringExpensesCard({
    required this.items,
    required this.canManageBudget,
    required this.currentUserId,
    required this.onToggle,
  });

  final List<RecurringExpenseModel> items;
  final bool canManageBudget;
  final String? currentUserId;
  final Future<void> Function(RecurringExpenseModel item, bool isActive)
  onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.t('budget.recurring_schedules'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final canManage =
                canManageBudget || currentUserId == item.createdByUserId;
            return SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: item.isActive,
              onChanged: canManage ? (value) => onToggle(item, value) : null,
              title: Text(
                item.category,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${AppFormatters.currency(context, amount: item.amount, currencyCode: item.currency)}'
                ' • ${context.l10n.t('budget.frequency_${item.frequency}')}'
                '\n${context.l10n.t('budget.next_charge')}: '
                '${AppFormatters.fullDateTime(context, item.nextRunAt)}',
              ),
              secondary: Icon(
                item.isActive
                    ? Icons.play_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                color: item.isActive ? colors.primary : colors.onSurfaceVariant,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _InsightMetric extends StatelessWidget {
  const _InsightMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
