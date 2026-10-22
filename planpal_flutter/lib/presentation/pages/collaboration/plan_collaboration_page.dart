import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planpal_flutter/core/dtos/plan_model.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/collaboration_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';

class PlanCollaborationPage extends ConsumerWidget {
  final PlanModel plan;
  const PlanCollaborationPage({super.key, required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(planCollaborationEventsProvider(plan.id), (_, next) {
      final event = next.valueOrNull;
      if (event == null) return;
      if (event.rawEventType.contains('work_item')) {
        ref.invalidate(planWorkItemsProvider(plan.id));
      }
      if (event.rawEventType.contains('comment') ||
          event.rawEventType.contains('reaction')) {
        ref.invalidate(planCommentsProvider(plan.id));
      }
    });

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.t('collaboration.title')),
          bottom: TabBar(
            tabs: [
              Tab(text: context.l10n.t('collaboration.tasks')),
              Tab(text: context.l10n.t('collaboration.checklist')),
              Tab(text: context.l10n.t('collaboration.discussion')),
            ],
          ),
        ),
        body: ResponsiveContent(
          mediumMaxWidth: 880,
          expandedMaxWidth: 1080,
          child: TabBarView(
            children: [
              _WorkItemsTab(plan: plan, type: 'task'),
              _WorkItemsTab(plan: plan, type: 'checklist'),
              _CommentsTab(plan: plan),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkItemsTab extends ConsumerWidget {
  final PlanModel plan;
  final String type;
  const _WorkItemsTab({required this.plan, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(planWorkItemsProvider(plan.id));
    final currentUserId = ref.watch(authNotifierProvider).user?.id;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(planWorkItemsProvider(plan.id).future),
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: [
              const SizedBox(height: 180),
              Center(child: Text(context.l10n.t('common.error'))),
            ],
          ),
          data: (all) {
            final items = all.where((item) => item.itemType == type).toList();
            if (items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 180),
                  Icon(
                    type == 'task'
                        ? Icons.assignment_outlined
                        : Icons.checklist_rounded,
                    size: 64,
                  ),
                  Center(
                    child: Text(
                      context.l10n.t(
                        type == 'task'
                            ? 'collaboration.no_tasks'
                            : 'collaboration.no_checklist',
                      ),
                    ),
                  ),
                ],
              );
            }
            final completed = items
                .where((item) => item.status == 'done')
                .length;
            final progress = completed / items.length;
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return JourneySurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.t(
                            'collaboration.progress',
                            params: {
                              'done': '$completed',
                              'total': '${items.length}',
                            },
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ],
                    ),
                  );
                }
                final item = items[index - 1];
                final canToggle =
                    plan.canEdit || item.assignee?.id == currentUserId;
                return JourneySurface(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Checkbox(
                      value: item.status == 'done',
                      onChanged: !canToggle
                          ? null
                          : (checked) => _setStatus(
                              context,
                              ref,
                              item.id,
                              checked == true ? 'done' : 'todo',
                            ),
                    ),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        decoration: item.status == 'done'
                            ? TextDecoration.lineThrough
                            : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.assignee != null)
                          Text(
                            '${context.l10n.t('collaboration.assignee')}: ${item.assignee!.fullName}',
                          ),
                        if (item.dueAt != null)
                          Text(
                            '${context.l10n.t('collaboration.deadline')}: ${DateFormat('dd/MM/yyyy HH:mm').format(item.dueAt!)}',
                          ),
                      ],
                    ),
                    trailing: canToggle
                        ? PopupMenuButton<String>(
                            onSelected: (value) => value == 'delete'
                                ? _delete(context, ref, item.id)
                                : _setStatus(context, ref, item.id, value),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'todo',
                                child: Text(
                                  context.l10n.t('collaboration.status_todo'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'in_progress',
                                child: Text(
                                  context.l10n.t(
                                    'collaboration.status_in_progress',
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'done',
                                child: Text(
                                  context.l10n.t('collaboration.status_done'),
                                ),
                              ),
                              if (plan.canEdit)
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(context.l10n.t('common.delete')),
                                ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: plan.canEdit
          ? FloatingActionButton(
              onPressed: () => _create(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    String id,
    String status,
  ) async {
    try {
      await ref.read(collaborationRepositoryProvider).updateWorkItem(id, {
        'status': status,
      });
      ref.invalidate(planWorkItemsProvider(plan.id));
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(collaborationRepositoryProvider).deleteWorkItem(id);
      ref.invalidate(planWorkItemsProvider(plan.id));
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final draft = await showModalBottomSheet<_WorkItemDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateWorkItemSheet(plan: plan, type: type),
    );
    if (draft == null || !context.mounted) return;

    try {
      await ref.read(collaborationRepositoryProvider).createWorkItem(plan.id, {
        'title': draft.title,
        'item_type': type,
        'assignee_id': draft.assigneeId,
        if (draft.dueAt != null)
          'due_at': draft.dueAt!.toUtc().toIso8601String(),
      });
      ref.invalidate(planWorkItemsProvider(plan.id));
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }
}

class _WorkItemDraft {
  const _WorkItemDraft({
    required this.title,
    required this.assigneeId,
    required this.dueAt,
  });

  final String title;
  final String? assigneeId;
  final DateTime? dueAt;
}

class _CreateWorkItemSheet extends StatefulWidget {
  const _CreateWorkItemSheet({required this.plan, required this.type});

  final PlanModel plan;
  final String type;

  @override
  State<_CreateWorkItemSheet> createState() => _CreateWorkItemSheetState();
}

class _CreateWorkItemSheetState extends State<_CreateWorkItemSheet> {
  final _titleController = TextEditingController();
  String? _assigneeId;
  DateTime? _dueAt;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _selectDeadline() async {
    final today = DateTime.now();
    final lastDate =
        widget.plan.endDate != null && widget.plan.endDate!.isAfter(today)
        ? widget.plan.endDate!
        : today.add(const Duration(days: 730));
    final preferred = _dueAt ?? widget.plan.startDate ?? today;
    final initialDate = preferred.isBefore(today)
        ? today
        : (preferred.isAfter(lastDate) ? lastDate : preferred);
    final date = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: lastDate,
      initialDate: initialDate,
    );
    if (date != null && mounted) setState(() => _dueAt = date);
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(
      context,
    ).pop(_WorkItemDraft(title: title, assigneeId: _assigneeId, dueAt: _dueAt));
  }

  @override
  Widget build(BuildContext context) {
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
              context.l10n.t(
                widget.type == 'task'
                    ? 'collaboration.add_task'
                    : 'collaboration.add_checklist',
              ),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: context.l10n.t('collaboration.item_title'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.t('collaboration.assignee')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(context.l10n.t('collaboration.unassigned')),
                  selected: _assigneeId == null,
                  onSelected: (_) => setState(() => _assigneeId = null),
                ),
                for (final member in widget.plan.collaborators)
                  ChoiceChip(
                    label: Text(member.fullName),
                    selected: _assigneeId == member.id,
                    onSelected: (_) => setState(() => _assigneeId = member.id),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(
                _dueAt == null
                    ? context.l10n.t('collaboration.set_deadline')
                    : DateFormat('dd/MM/yyyy').format(_dueAt!),
              ),
              onTap: _selectDeadline,
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: Text(context.l10n.t('common.create')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentsTab extends ConsumerStatefulWidget {
  final PlanModel plan;
  const _CommentsTab({required this.plan});

  @override
  ConsumerState<_CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends ConsumerState<_CommentsTab> {
  final TextEditingController _input = TextEditingController();
  String? _activityId;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(planCommentsProvider(widget.plan.id));
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.refresh(planCommentsProvider(widget.plan.id).future),
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => ListView(
                children: [
                  const SizedBox(height: 180),
                  Center(child: Text(context.l10n.t('common.error'))),
                ],
              ),
              data: (comments) => comments.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 180),
                        const Icon(Icons.forum_outlined, size: 64),
                        Center(
                          child: Text(
                            context.l10n.t('collaboration.no_comments'),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: comments.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (context, index) {
                        final comment = comments[index];
                        return JourneySurface(
                          selected: comment.isPinned,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xxs),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      child: Text(
                                        comment.author.fullName.isEmpty
                                            ? '?'
                                            : comment.author.fullName[0]
                                                  .toUpperCase(),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        comment.author.fullName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (comment.isPinned)
                                      const Icon(Icons.push_pin, size: 18),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(comment.body),
                                if (comment.activityTitle != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '↳ ${comment.activityTitle}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    for (final reaction in const [
                                      'like',
                                      'love',
                                      'celebrate',
                                      'helpful',
                                    ])
                                      ActionChip(
                                        backgroundColor:
                                            comment.currentUserReaction ==
                                                reaction
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer
                                            : null,
                                        label: Text(
                                          '${_reactionIcon(reaction)} ${comment.reactionCounts[reaction] ?? 0}',
                                        ),
                                        onPressed: () => _react(
                                          context,
                                          ref,
                                          comment.id,
                                          comment.currentUserReaction ==
                                                  reaction
                                              ? null
                                              : reaction,
                                        ),
                                      ),
                                    if (widget.plan.canEdit)
                                      IconButton(
                                        tooltip: context.l10n.t(
                                          'collaboration.pin',
                                        ),
                                        icon: Icon(
                                          comment.isPinned
                                              ? Icons.push_pin
                                              : Icons.push_pin_outlined,
                                        ),
                                        onPressed: () =>
                                            _pin(context, comment.id),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.plan.activities.isNotEmpty)
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ChoiceChip(
                          label: Text(
                            context.l10n.t('collaboration.whole_plan'),
                          ),
                          selected: _activityId == null,
                          onSelected: (_) => setState(() => _activityId = null),
                        ),
                        const SizedBox(width: 6),
                        for (final activity in widget.plan.activities)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(activity.title),
                              selected: _activityId == activity.id,
                              onSelected: (_) =>
                                  setState(() => _activityId = activity.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: context.l10n.t(
                            'collaboration.write_comment',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.send),
                      onPressed: () => _send(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _reactionIcon(String reaction) =>
      const {
        'like': '👍',
        'love': '❤️',
        'celebrate': '🎉',
        'helpful': '💡',
      }[reaction] ??
      '👍';

  Future<void> _send(BuildContext context) async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    final mentionIds = widget.plan.collaborators
        .where(
          (member) =>
              body.toLowerCase().contains('@${member.username.toLowerCase()}'),
        )
        .map((member) => member.id)
        .toList();
    try {
      await ref
          .read(collaborationRepositoryProvider)
          .createComment(widget.plan.id, {
            'body': body,
            'mention_user_ids': mentionIds,
            if (_activityId != null) 'activity_id': _activityId,
          });
      _input.clear();
      ref.invalidate(planCommentsProvider(widget.plan.id));
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _react(
    BuildContext context,
    WidgetRef ref,
    String id,
    String? reaction,
  ) async {
    try {
      await ref.read(collaborationRepositoryProvider).react(id, reaction);
      ref.invalidate(planCommentsProvider(widget.plan.id));
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _pin(BuildContext context, String id) async {
    try {
      await ref.read(collaborationRepositoryProvider).togglePin(id);
      ref.invalidate(planCommentsProvider(widget.plan.id));
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }
}
