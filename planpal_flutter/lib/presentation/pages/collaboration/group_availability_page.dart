import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/collaboration_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.t('collaboration.availability_title')),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(availabilityPollsProvider(groupId).future),
        child: polls.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 180),
              Center(child: Text(context.l10n.t('common.error'))),
            ],
          ),
          data: (items) => items.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 180),
                    Icon(
                      Icons.event_available_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(context.l10n.t('collaboration.no_polls')),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final poll = items[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    poll.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (poll.isClosed)
                                  Chip(
                                    label: Text(
                                      context.l10n.t('collaboration.closed'),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.l10n.t(
                                'collaboration.voter_count',
                                params: {'count': '${poll.totalVoters}'},
                              ),
                            ),
                            const SizedBox(height: 14),
                            for (final option in poll.options) ...[
                              Text(
                                option.label.isEmpty
                                    ? DateFormat(
                                        'EEE, dd/MM · HH:mm',
                                      ).format(option.startAt)
                                    : option.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${DateFormat('HH:mm').format(option.startAt)} – ${DateFormat('HH:mm').format(option.endAt)}',
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final vote in const [
                                    'available',
                                    'maybe',
                                    'unavailable',
                                  ])
                                    ChoiceChip(
                                      selected: option.currentUserVote == vote,
                                      onSelected: poll.isClosed
                                          ? null
                                          : (_) => _vote(
                                              context,
                                              ref,
                                              poll.id,
                                              option.id,
                                              vote,
                                            ),
                                      label: Text(
                                        '${context.l10n.t('collaboration.vote_$vote')} ${option.voteCounts[vote] ?? 0}',
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _createPoll(context, ref),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.t('collaboration.create_poll')),
            )
          : null,
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
