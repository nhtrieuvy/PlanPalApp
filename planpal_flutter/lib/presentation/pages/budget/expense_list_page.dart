import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/budget_model.dart';
import 'package:planpal_flutter/core/riverpod/budget_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/presentation/pages/budget/add_expense_form.dart';
import 'package:planpal_flutter/presentation/widgets/budget/expense_item.dart';
import 'package:planpal_flutter/presentation/widgets/common/refreshable_page_wrapper.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class ExpenseListPage extends ConsumerStatefulWidget {
  final String planId;
  final String planTitle;

  const ExpenseListPage({
    super.key,
    required this.planId,
    required this.planTitle,
  });

  @override
  ConsumerState<ExpenseListPage> createState() => _ExpenseListPageState();
}

class _ExpenseListPageState extends ConsumerState<ExpenseListPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _categoryController = TextEditingController();
  ExpenseFilter _filter = const ExpenseFilter();

  ExpenseListQuery get _query =>
      ExpenseListQuery(planId: widget.planId, filter: _filter);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesProvider(_query));
    final budgetAsync = ref.watch(budgetProvider(widget.planId));
    final currency = budgetAsync.valueOrNull?.currency ?? 'VND';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Expenses'),
        actions: [
          PopupMenuButton<String>(
            onSelected: _applySort,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'created_at:desc',
                child: Text('Newest first'),
              ),
              PopupMenuItem(
                value: 'created_at:asc',
                child: Text('Oldest first'),
              ),
              PopupMenuItem(
                value: 'amount:desc',
                child: Text('Highest amount'),
              ),
              PopupMenuItem(value: 'amount:asc', child: Text('Lowest amount')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.sort_rounded),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddExpense,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense'),
      ),
      body: Column(
        children: [
          _buildFilterBar(context),
          Expanded(
            child: RefreshablePageWrapper(
              onRefresh: _refresh,
              child: expensesAsync.when(
                loading: () => const AppSkeleton.list(itemCount: 6),
                error: (error, _) => AppError(
                  message: ErrorDisplayService.getUserFriendlyMessage(error),
                  onRetry: _refresh,
                  retryLabel: 'Retry',
                ),
                data: (data) => _buildContent(context, data, currency),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _categoryController,
              decoration: InputDecoration(
                hintText: 'Filter by category',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _categoryController.text.trim().isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _categoryController.clear();
                          _applyCategoryFilter();
                        },
                        icon: const Icon(Icons.close_rounded),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _applyCategoryFilter(),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _applyCategoryFilter,
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ExpenseFeedState data,
    String currency,
  ) {
    if (data.items.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          AppEmpty(
            icon: Icons.receipt_long_rounded,
            title: 'No expenses yet',
            description: 'New plan expenses will appear here.',
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: data.items.length + (data.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= data.items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ExpenseItem(expense: data.items[index], currency: currency);
      },
    );
  }

  Future<void> _refresh() async {
    await ref.read(expensesProvider(_query).notifier).refresh();
  }

  void _applyCategoryFilter() {
    setState(() {
      final category = _categoryController.text.trim();
      _filter = _filter.copyWith(category: category.isEmpty ? null : category);
    });
  }

  void _applySort(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return;
    setState(() {
      _filter = _filter.copyWith(sortBy: parts[0], sortDirection: parts[1]);
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels >= position.maxScrollExtent * 0.8) {
      ref.read(expensesProvider(_query).notifier).loadMore();
    }
  }

  Future<void> _openAddExpense() async {
    final result = await Navigator.of(context).push<ExpenseCreateResult>(
      MaterialPageRoute(
        builder: (context) =>
            AddExpenseForm(planId: widget.planId, planTitle: widget.planTitle),
      ),
    );
    if (result == null) return;
    ref.invalidate(budgetProvider(widget.planId));
    await _refresh();
  }
}
