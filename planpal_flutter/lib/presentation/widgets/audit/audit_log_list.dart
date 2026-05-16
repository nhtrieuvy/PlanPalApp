import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/audit_log_model.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/audit_logs_provider.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

class AuditLogList extends ConsumerStatefulWidget {
  final String title;
  final String? resourceType;
  final String? resourceId;
  final int refreshSignal;

  const AuditLogList({
    super.key,
    this.title = 'Audit Log',
    this.resourceType,
    this.resourceId,
    this.refreshSignal = 0,
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

  @override
  void didUpdateWidget(covariant AuditLogList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
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
                  tooltip: context.l10n.t('audit.refresh'),
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
    final actionItems = _buildActionDropdownItems();
    final actorItems = _buildActorDropdownItems(actorOptions);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: _selectedAction,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.l10n.t('audit.action'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: actionItems,
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
            decoration: InputDecoration(
              labelText: context.l10n.t('audit.user'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: actorItems,
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
                ? context.l10n.t('common.from_date')
                : AppFormatters.shortDate(context, _dateFrom!),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDate(isStartDate: false),
          icon: const Icon(Icons.event_available_outlined),
          label: Text(
            _dateTo == null
                ? context.l10n.t('common.to_date')
                : AppFormatters.shortDate(context, _dateTo!),
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
          child: Text(context.l10n.t('common.clear_filters')),
        ),
      ],
    );
  }

  List<DropdownMenuItem<String>> _buildActionDropdownItems() {
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: '',
        child: Text(context.l10n.t('audit.all_actions')),
      ),
      ...AuditLogModel.actionOptions.map(
        (option) => DropdownMenuItem(
          value: option.value,
          child: Text(context.l10n.auditActionLabel(option.value)),
        ),
      ),
    ];

    final hasSelectedAction =
        _selectedAction.isEmpty ||
        items.any((item) => item.value == _selectedAction);
    if (!hasSelectedAction) {
      items.add(
        DropdownMenuItem(
          value: _selectedAction,
          child: Text(context.l10n.auditActionLabel(_selectedAction)),
        ),
      );
    }

    return items;
  }

  List<DropdownMenuItem<String>> _buildActorDropdownItems(
    Map<String, String> actorOptions,
  ) {
    final entries = Map<String, String>.from(actorOptions);
    if (_selectedUserId.isNotEmpty && !entries.containsKey(_selectedUserId)) {
      entries[_selectedUserId] = context.l10n.t('audit.selected_user');
    }

    return [
      DropdownMenuItem(
        value: '',
        child: Text(context.l10n.t('audit.all_users')),
      ),
      ...entries.entries.map(
        (entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ),
    ];
  }

  Widget _buildListState(BuildContext context, AuditLogFeedState state) {
    if (state.items.isEmpty) {
      return Center(child: Text(context.l10n.t('audit.empty')));
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
              label: Text(context.l10n.t('audit.load_more')),
            ),
          );
        }

        final log = state.items[index];
        final l10n = context.l10n;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ActionBadge(label: log.localizedActionLabel(l10n)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.localizedMetadataSummary(l10n),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                log.localizedActorDisplayName(l10n),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppFormatters.fullDateTime(context, log.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colorScheme.primary,
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
          ElevatedButton(
            onPressed: onRetry,
            child: Text(context.l10n.t('common.retry')),
          ),
        ],
      ),
    );
  }
}
