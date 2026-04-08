import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planpal_flutter/core/dtos/audit_log_model.dart';
import 'package:planpal_flutter/core/riverpod/audit_logs_provider.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

class AuditLogList extends ConsumerStatefulWidget {
  final String title;
  final String? resourceType;
  final String? resourceId;

  const AuditLogList({
    super.key,
    this.title = 'Audit Log',
    this.resourceType,
    this.resourceId,
  });

  bool get isResourceScoped =>
      resourceType != null &&
      resourceType!.isNotEmpty &&
      resourceId != null &&
      resourceId!.isNotEmpty;

  @override
  ConsumerState<AuditLogList> createState() => _AuditLogListState();
}

class _AuditLogListState extends ConsumerState<AuditLogList> {
  final ScrollController _scrollController = ScrollController();
  final DateFormat _timestampFormat = DateFormat('dd/MM/yyyy HH:mm');

  String _selectedAction = '';
  String _selectedUserId = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  AuditLogFilter get _filters => AuditLogFilter(
    action: _selectedAction.isEmpty ? null : _selectedAction,
    userId: _selectedUserId.isEmpty ? null : _selectedUserId,
    dateFrom: _dateFrom == null
        ? null
        : DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day),
    dateTo: _dateTo == null
        ? null
        : DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59),
  );

  AuditLogQuery get _resourceQuery => AuditLogQuery(
    resourceType: widget.resourceType!,
    resourceId: widget.resourceId!,
    filters: _filters,
  );

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 240) return;
    _loadMore();
  }

  void _loadMore() {
    if (widget.isResourceScoped) {
      ref.read(resourceAuditLogsProvider(_resourceQuery).notifier).loadMore();
      return;
    }
    ref.read(auditLogsProvider(_filters).notifier).loadMore();
  }

  void _refresh() {
    if (widget.isResourceScoped) {
      ref.read(resourceAuditLogsProvider(_resourceQuery).notifier).refresh();
      return;
    }
    ref.read(auditLogsProvider(_filters).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = widget.isResourceScoped
        ? ref.watch(resourceAuditLogsProvider(_resourceQuery))
        : ref.watch(auditLogsProvider(_filters));
    final feedState = asyncState.valueOrNull;
    final actorOptions = _buildActorOptions(feedState?.items ?? const []);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.history_edu_outlined,
                    color: AppColors.secondary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh audit logs',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildFilters(actorOptions),
            const SizedBox(height: 16),
            SizedBox(
              height: 320,
              child: asyncState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    _AuditErrorState(error: error, onRetry: _refresh),
                data: (state) => _buildListState(context, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(Map<String, String> actorOptions) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: _selectedAction,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Action',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All actions')),
              ...AuditLogModel.actionOptions.map(
                (option) => DropdownMenuItem(
                  value: option.value,
                  child: Text(option.label),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedAction = value ?? '';
              });
            },
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: _selectedUserId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'User',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All users')),
              ...actorOptions.entries.map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedUserId = value ?? '';
              });
            },
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDate(isStartDate: true),
          icon: const Icon(Icons.date_range_outlined),
          label: Text(
            _dateFrom == null
                ? 'From date'
                : DateFormat('dd/MM/yyyy').format(_dateFrom!),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDate(isStartDate: false),
          icon: const Icon(Icons.event_available_outlined),
          label: Text(
            _dateTo == null
                ? 'To date'
                : DateFormat('dd/MM/yyyy').format(_dateTo!),
          ),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _selectedAction = '';
              _selectedUserId = '';
              _dateFrom = null;
              _dateTo = null;
            });
          },
          child: const Text('Clear filters'),
        ),
      ],
    );
  }

  Widget _buildListState(BuildContext context, AuditLogFeedState state) {
    if (state.items.isEmpty) {
      return const Center(
        child: Text('No audit activity matches the current filters.'),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      itemCount:
          state.items.length + (state.isLoadingMore || state.hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          if (state.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Center(
            child: TextButton.icon(
              onPressed: _loadMore,
              icon: const Icon(Icons.expand_more),
              label: const Text('Load more'),
            ),
          );
        }

        final log = state.items[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ActionBadge(label: log.actionLabel),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.metadataSummary,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                log.actorDisplayName,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                _timestampFormat.format(log.createdAt),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, String> _buildActorOptions(List<AuditLogModel> logs) {
    final result = <String, String>{};
    for (final log in logs) {
      final userId = log.userId;
      if (userId == null || userId.isEmpty) continue;
      result[userId] = log.actorDisplayName;
    }
    return result;
  }

  Future<void> _pickDate({required bool isStartDate}) async {
    final initialDate = isStartDate
        ? (_dateFrom ?? DateTime.now())
        : (_dateTo ?? _dateFrom ?? DateTime.now());
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) return;
    setState(() {
      if (isStartDate) {
        _dateFrom = pickedDate;
      } else {
        _dateTo = pickedDate;
      }
    });
  }
}

class _ActionBadge extends StatelessWidget {
  final String label;

  const _ActionBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AuditErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _AuditErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            ErrorDisplayService.getUserFriendlyMessage(error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
