import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/experience_models.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/experience_providers.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class GroupPollsPage extends ConsumerWidget {
  const GroupPollsPage({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final polls = ref.watch(groupPollsProvider(groupId));
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('polls.title'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(groupPollsProvider(groupId).future),
        child: polls.when(
          loading: () => const AppSkeleton.list(itemCount: 4),
          error: (error, _) => AppError(
            message: ErrorDisplayService.getUserFriendlyMessage(error),
            onRetry: () => ref.invalidate(groupPollsProvider(groupId)),
            retryLabel: context.l10n.t('common.retry'),
          ),
          data: (items) => items.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * .18),
                    AppEmpty(
                      icon: Icons.poll_outlined,
                      title: context.l10n.t('polls.empty_title'),
                      description: context.l10n.t('polls.empty_hint'),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, index) => _PollCard(
                    poll: items[index],
                    onChanged: () =>
                        ref.invalidate(groupPollsProvider(groupId)),
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _CreatePollSheet(groupId: groupId),
          );
          if (created == true) ref.invalidate(groupPollsProvider(groupId));
        },
        icon: const Icon(Icons.add),
        label: Text(context.l10n.t('polls.create')),
      ),
    );
  }
}

class _PollCard extends ConsumerStatefulWidget {
  const _PollCard({required this.poll, required this.onChanged});
  final GroupPollModel poll;
  final VoidCallback onChanged;

  @override
  ConsumerState<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends ConsumerState<_PollCard> {
  late Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.poll.selectedOptionIds};
  }

  @override
  void didUpdateWidget(covariant _PollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll != widget.poll) {
      _selected = {...widget.poll.selectedOptionIds};
    }
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final theme = Theme.of(context);
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
                    poll.question,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!poll.isClosed &&
                    poll.createdById == ref.read(authNotifierProvider).user?.id)
                  IconButton(
                    tooltip: context.l10n.t('polls.close'),
                    onPressed: _saving ? null : _close,
                    icon: const Icon(Icons.lock_outline),
                  ),
                if (poll.isClosed)
                  Chip(label: Text(context.l10n.t('polls.closed'))),
              ],
            ),
            const SizedBox(height: 8),
            for (final option in poll.options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(option.text),
                subtitle: LinearProgressIndicator(
                  value: poll.totalVotes == 0
                      ? 0
                      : option.voteCount / poll.totalVotes,
                  borderRadius: BorderRadius.circular(99),
                ),
                secondary: Text('${option.voteCount}'),
                value: _selected.contains(option.id),
                onChanged: poll.isClosed
                    ? null
                    : (checked) {
                        setState(() {
                          if (!poll.allowMultiple) _selected.clear();
                          if (checked == true) {
                            _selected.add(option.id);
                          } else {
                            _selected.remove(option.id);
                          }
                        });
                      },
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  context.l10n.t(
                    'polls.vote_count',
                    params: {'count': poll.totalVotes.toString()},
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                if (!poll.isClosed)
                  FilledButton(
                    onPressed: _saving || _selected.isEmpty ? null : _vote,
                    child: Text(context.l10n.t('polls.vote')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _vote() async {
    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(experienceRepositoryProvider)
          .vote(widget.poll.id, _selected);
      if (!mounted) return;
      if (updated == null) {
        ErrorDisplayService.showWarningSnackbar(
          context,
          context.l10n.t('offline.queued'),
        );
      } else {
        widget.onChanged();
      }
    } catch (error) {
      if (mounted) {
        ErrorDisplayService.showErrorSnackbar(
          context,
          ErrorDisplayService.getUserFriendlyMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _close() async {
    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(experienceRepositoryProvider)
          .closePoll(widget.poll.id);
      if (!mounted) return;
      if (updated == null) {
        ErrorDisplayService.showWarningSnackbar(
          context,
          context.l10n.t('offline.queued'),
        );
      } else {
        widget.onChanged();
      }
    } catch (error) {
      if (mounted) {
        ErrorDisplayService.showErrorSnackbar(
          context,
          ErrorDisplayService.getUserFriendlyMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CreatePollSheet extends ConsumerStatefulWidget {
  const _CreatePollSheet({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends ConsumerState<_CreatePollSheet> {
  final _question = TextEditingController();
  final _options = List.generate(2, (_) => TextEditingController());
  bool _multiple = false;
  bool _saving = false;

  @override
  void dispose() {
    _question.dispose();
    for (final controller in _options) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('polls.create'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _question,
            maxLength: 240,
            decoration: InputDecoration(
              labelText: context.l10n.t('polls.question'),
              prefixIcon: const Icon(Icons.help_outline),
            ),
          ),
          for (var index = 0; index < _options.length; index++) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _options[index],
              decoration: InputDecoration(
                labelText: context.l10n.t(
                  'polls.option',
                  params: {'number': '${index + 1}'},
                ),
              ),
            ),
          ],
          TextButton.icon(
            onPressed: _options.length >= 10
                ? null
                : () => setState(() => _options.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: Text(context.l10n.t('polls.add_option')),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.t('polls.multiple')),
            value: _multiple,
            onChanged: (value) => setState(() => _multiple = value),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(context.l10n.t('polls.create')),
          ),
        ],
      ),
    ),
  );

  Future<void> _submit() async {
    final options = _options
        .map((item) => item.text.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (_question.text.trim().isEmpty || options.length < 2) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('polls.validation'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await ref
          .read(experienceRepositoryProvider)
          .createPoll(widget.groupId, {
            'question': _question.text.trim(),
            'options': options,
            'allow_multiple': _multiple,
          });
      if (mounted && created == null) {
        ErrorDisplayService.showWarningSnackbar(
          context,
          context.l10n.t('offline.queued'),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ErrorDisplayService.showErrorSnackbar(
          context,
          ErrorDisplayService.getUserFriendlyMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
