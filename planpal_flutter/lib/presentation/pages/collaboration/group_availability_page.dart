import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planpal_flutter/core/dtos/collaboration_models.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/collaboration_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class GroupAvailabilityPage extends ConsumerWidget {
  final String groupId;
  final bool canManage;

  const GroupAvailabilityPage({
    super.key,
    required this.groupId,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final polls = ref.watch(availabilityPollsProvider(groupId));
    final hasPolls = polls.valueOrNull?.isNotEmpty == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.t('collaboration.availability_title')),
      ),
      body: ResponsiveContent(
        mediumMaxWidth: 820,
        expandedMaxWidth: 960,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.refresh(availabilityPollsProvider(groupId).future),
          child: polls.when(
            loading: () => const AppSkeleton.list(itemCount: 4),
            error: (error, _) => ListView(
              children: [
                const SizedBox(height: AppSpacing.xxl),
                AppError(
                  message: ErrorDisplayService.getUserFriendlyMessage(error),
                  onRetry: () =>
                      ref.invalidate(availabilityPollsProvider(groupId)),
                  retryLabel: context.l10n.t('common.retry'),
                ),
              ],
            ),
            data: (items) => items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: AppSpacing.xxl),
                      AppEmpty(
                        icon: Icons.event_available_outlined,
                        title: context.l10n.t('collaboration.no_polls'),
                        description: context.l10n.t(
                          'collaboration.availability_empty_hint',
                        ),
                        actionLabel: canManage
                            ? context.l10n.t('collaboration.create_poll')
                            : null,
                        onAction: canManage
                            ? () => _createPoll(context, ref)
                            : null,
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) =>
                        _buildPoll(context, ref, items[index]),
                  ),
          ),
        ),
      ),
      floatingActionButton: canManage && hasPolls
          ? FloatingActionButton.extended(
              onPressed: () => _createPoll(context, ref),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.t('collaboration.create_poll')),
            )
          : null,
    );
  }

  Widget _buildPoll(
    BuildContext context,
    WidgetRef ref,
    AvailabilityPollModel poll,
  ) {
    final theme = Theme.of(context);
    final bestOption = poll.options.isEmpty
        ? null
        : poll.options.reduce(
            (current, next) =>
                (next.voteCounts['available'] ?? 0) >
                    (current.voteCounts['available'] ?? 0)
                ? next
                : current,
          );

    return JourneySurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poll.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      context.l10n.t(
                        'collaboration.voter_count',
                        params: {'count': '${poll.totalVoters}'},
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (poll.isClosed)
                Chip(label: Text(context.l10n.t('collaboration.closed'))),
            ],
          ),
          if (bestOption != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      context.l10n.t(
                        'collaboration.best_match',
                        params: {
                          'date': DateFormat(
                            'EEE, dd/MM',
                          ).format(bestOption.startAt),
                        },
                      ),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 720
                ? _buildAvailabilityMatrix(context, ref, poll)
                : Column(
                    children: [
                      for (final option in poll.options) ...[
                        _buildOption(context, ref, poll, option),
                        if (option != poll.options.last)
                          const Divider(height: AppSpacing.xl),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityMatrix(
    BuildContext context,
    WidgetRef ref,
    AvailabilityPollModel poll,
  ) {
    final l10n = context.l10n;
    final votersById = <String, CollaborationUser>{};
    for (final option in poll.options) {
      for (final vote in option.votes) {
        votersById[vote.user.id] = vote.user;
      }
    }
    final voters = votersById.values.toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 64,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 64,
        horizontalMargin: AppSpacing.sm,
        columnSpacing: AppSpacing.lg,
        columns: [
          DataColumn(label: Text(l10n.t('collaboration.traveler'))),
          for (final option in poll.options)
            DataColumn(
              label: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label.isEmpty
                        ? DateFormat('EEE, dd/MM').format(option.startAt)
                        : option.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${DateFormat('HH:mm').format(option.startAt)} - '
                    '${DateFormat('HH:mm').format(option.endAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
        rows: [
          for (final voter in voters)
            DataRow(
              cells: [
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      voter.fullName.isNotEmpty
                          ? voter.fullName
                          : voter.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                for (final option in poll.options)
                  DataCell(
                    _AvailabilityStatus(status: _statusFor(option, voter.id)),
                  ),
              ],
            ),
          DataRow(
            cells: [
              DataCell(
                Text(
                  l10n.t('collaboration.your_availability'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final option in poll.options)
                DataCell(
                  _AvailabilityVoteMenu(
                    status: option.currentUserVote,
                    enabled: !poll.isClosed,
                    onSelected: (status) =>
                        _vote(context, ref, poll.id, option.id, status),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String? _statusFor(AvailabilityOptionModel option, String userId) {
    for (final vote in option.votes) {
      if (vote.user.id == userId) return vote.status;
    }
    return null;
  }

  Widget _buildOption(
    BuildContext context,
    WidgetRef ref,
    AvailabilityPollModel poll,
    AvailabilityOptionModel option,
  ) {
    final theme = Theme.of(context);
    final available = option.voteCounts['available'] ?? 0;
    final participation = poll.totalVoters == 0
        ? 0.0
        : (available / poll.totalVoters).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                option.label.isEmpty
                    ? DateFormat('EEE, dd/MM').format(option.startAt)
                    : option.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${DateFormat('HH:mm').format(option.startAt)} - ${DateFormat('HH:mm').format(option.endAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LinearProgressIndicator(value: participation, minHeight: 6),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final vote in const ['available', 'maybe', 'unavailable'])
              ChoiceChip(
                selected: option.currentUserVote == vote,
                onSelected: poll.isClosed
                    ? null
                    : (_) => _vote(context, ref, poll.id, option.id, vote),
                label: Text(
                  '${context.l10n.t('collaboration.vote_$vote')} ${option.voteCounts[vote] ?? 0}',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _vote(
    BuildContext context,
    WidgetRef ref,
    String pollId,
    String optionId,
    String status,
  ) async {
    try {
      await ref
          .read(collaborationRepositoryProvider)
          .vote(pollId, optionId, status);
      ref.invalidate(availabilityPollsProvider(groupId));
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _createPoll(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final first = DateTime.now().add(const Duration(days: 1));
    final options = <_AvailabilityDraftOption>[
      _AvailabilityDraftOption(first),
      _AvailabilityDraftOption(first.add(const Duration(days: 1))),
    ];
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.t('collaboration.create_poll'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: title,
                    decoration: InputDecoration(
                      labelText: context.l10n.t('collaboration.poll_question'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < options.length; i++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.event_outlined),
                              title: Text(
                                DateFormat(
                                  'EEEE, dd/MM/yyyy',
                                ).format(options[i].date),
                              ),
                              trailing: options.length > 2
                                  ? IconButton(
                                      tooltip: context.l10n.t('common.delete'),
                                      onPressed: () => setSheetState(
                                        () => options.removeAt(i),
                                      ),
                                      icon: const Icon(Icons.close),
                                    )
                                  : null,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 730),
                                  ),
                                  initialDate: options[i].date,
                                );
                                if (picked != null) {
                                  setSheetState(() => options[i].date = picked);
                                }
                              },
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: options[i].start,
                                      );
                                      if (picked != null) {
                                        setSheetState(
                                          () => options[i].start = picked,
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.schedule),
                                    label: Text(
                                      '${context.l10n.t('collaboration.start_time')} ${options[i].start.format(context)}',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: options[i].end,
                                      );
                                      if (picked != null) {
                                        setSheetState(
                                          () => options[i].end = picked,
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.schedule_outlined),
                                    label: Text(
                                      '${context.l10n.t('collaboration.end_time')} ${options[i].end.format(context)}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: options.length >= 10
                        ? null
                        : () => setSheetState(
                            () => options.add(
                              _AvailabilityDraftOption(
                                options.last.date.add(const Duration(days: 1)),
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.t('collaboration.add_option')),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: Text(context.l10n.t('common.create')),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (submitted != true || title.text.trim().isEmpty || !context.mounted) {
      title.dispose();
      return;
    }
    try {
      await ref.read(collaborationRepositoryProvider).createPoll(groupId, {
        'title': title.text.trim(),
        'options': options.map((option) {
          final start = option.startDateTime;
          return {
            'start_at': start.toUtc().toIso8601String(),
            'end_at': option.endDateTime.toUtc().toIso8601String(),
          };
        }).toList(),
      });
      ref.invalidate(availabilityPollsProvider(groupId));
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    } finally {
      title.dispose();
    }
  }
}

class _AvailabilityStatus extends StatelessWidget {
  const _AvailabilityStatus({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (status) {
      'available' => (
        Icons.check_circle_rounded,
        context.l10n.t('collaboration.vote_available'),
        colors.primary,
      ),
      'maybe' => (
        Icons.help_rounded,
        context.l10n.t('collaboration.vote_maybe'),
        colors.tertiary,
      ),
      'unavailable' => (
        Icons.cancel_rounded,
        context.l10n.t('collaboration.vote_unavailable'),
        colors.error,
      ),
      _ => (
        Icons.remove_rounded,
        context.l10n.t('collaboration.no_response'),
        colors.onSurfaceVariant,
      ),
    };
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

class _AvailabilityVoteMenu extends StatelessWidget {
  const _AvailabilityVoteMenu({
    required this.status,
    required this.enabled,
    required this.onSelected,
  });

  final String? status;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    enabled: enabled,
    tooltip: context.l10n.t('collaboration.choose_availability'),
    initialValue: status,
    onSelected: onSelected,
    itemBuilder: (context) => [
      _item(
        context,
        'available',
        Icons.check_circle_rounded,
        context.l10n.t('collaboration.vote_available'),
      ),
      _item(
        context,
        'maybe',
        Icons.help_rounded,
        context.l10n.t('collaboration.vote_maybe'),
      ),
      _item(
        context,
        'unavailable',
        Icons.cancel_rounded,
        context.l10n.t('collaboration.vote_unavailable'),
      ),
    ],
    child: SizedBox.square(
      dimension: 44,
      child: Center(child: _AvailabilityStatus(status: status)),
    ),
  );

  PopupMenuItem<String> _item(
    BuildContext context,
    String value,
    IconData icon,
    String label,
  ) => PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: AppSpacing.xs),
        Text(label),
      ],
    ),
  );
}

class _AvailabilityDraftOption {
  _AvailabilityDraftOption(this.date)
    : start = const TimeOfDay(hour: 8, minute: 0),
      end = const TimeOfDay(hour: 18, minute: 0);

  DateTime date;
  TimeOfDay start;
  TimeOfDay end;

  DateTime get startDateTime =>
      DateTime(date.year, date.month, date.day, start.hour, start.minute);

  DateTime get endDateTime =>
      DateTime(date.year, date.month, date.day, end.hour, end.minute);
}
