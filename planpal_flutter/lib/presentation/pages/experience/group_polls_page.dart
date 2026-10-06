import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/experience_models.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/experience_providers.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class GroupPollsPage extends ConsumerWidget {
  const GroupPollsPage({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final polls = ref.watch(groupPollsProvider(groupId));
    final hasPolls = polls.valueOrNull?.isNotEmpty == true;
    return Scaffold(
      appBar: AppBar(),
      body: ResponsiveContent(
        mediumMaxWidth: 760,
        expandedMaxWidth: 900,
        child: Column(
          children: [
            JourneyPageHeader(
              eyebrow: context.l10n.t('polls.group_subtitle'),
              title: context.l10n.t('polls.title'),
              subtitle: context.l10n.t('polls.empty_hint'),
              leadingIcon: Icons.how_to_vote_outlined,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(groupPollsProvider(groupId).future),
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
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * .12,
                            ),
                            AppEmpty(
                              icon: Icons.poll_outlined,
                              title: context.l10n.t('polls.empty_title'),
                              description: context.l10n.t('polls.empty_hint'),
                              actionLabel: context.l10n.t('polls.create'),
                              onAction: () => _createPoll(context, ref),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.xs,
                            AppSpacing.lg,
                            104,
                          ),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (_, index) => _PollCard(
                            poll: items[index],
                            onChanged: () =>
                                ref.invalidate(groupPollsProvider(groupId)),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: hasPolls
          ? FloatingActionButton.extended(
              onPressed: () => _createPoll(context, ref),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.t('polls.create')),
            )
          : null,
    );
  }

  Future<void> _createPoll(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreatePollSheet(groupId: groupId),
    );
    if (created == true) ref.invalidate(groupPollsProvider(groupId));
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
    return JourneySurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Icon(
                  Icons.ballot_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poll.question,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      context.l10n.t(
                        'polls.vote_count',
                        params: {'count': poll.totalVotes.toString()},
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!poll.isClosed &&
                  poll.createdById == ref.read(authNotifierProvider).user?.id)
                IconButton(
                  tooltip: context.l10n.t('polls.close'),
                  onPressed: _saving ? null : _close,
                  icon: const Icon(Icons.more_horiz_rounded),
                )
              else if (poll.isClosed)
                Chip(
                  avatar: const Icon(Icons.lock_outline_rounded, size: 16),
                  label: Text(context.l10n.t('polls.closed')),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final option in poll.options) ...[
            _PollOption(
              option: option,
              totalVotes: poll.totalVotes,
              selected: _selected.contains(option.id),
              multiple: poll.allowMultiple,
              enabled: !poll.isClosed && !_saving,
              onTap: () {
                setState(() {
                  if (!poll.allowMultiple) _selected.clear();
                  if (_selected.contains(option.id)) {
                    _selected.remove(option.id);
                  } else {
                    _selected.add(option.id);
                  }
                });
              },
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (!poll.isClosed) ...[
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _selected.isEmpty ? null : _vote,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.how_to_vote_rounded),
                label: Text(context.l10n.t('polls.vote')),
              ),
            ),
          ],
        ],
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

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.option,
    required this.totalVotes,
    required this.selected,
    required this.multiple,
    required this.enabled,
    required this.onTap,
  });

  final GroupPollOptionModel option;
  final int totalVotes;
  final bool selected;
  final bool multiple;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ratio = totalVotes == 0 ? 0.0 : option.voteCount / totalVotes;
    return Semantics(
      button: true,
      selected: selected,
      label: option.text,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: AnimatedContainer(
          duration: AppMotion.standard,
          curve: AppMotion.enter,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer.withValues(alpha: 0.5)
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    multiple
                        ? selected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded
                        : selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      option.text,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${option.voteCount}',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: ratio),
                duration: AppMotion.emphasized,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
              if (option.voters.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _VoterAvatarStack(voters: option.voters),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VoterAvatarStack extends StatelessWidget {
  const _VoterAvatarStack({required this.voters});

  final List<GroupPollVoterModel> voters;

  @override
  Widget build(BuildContext context) {
    final visible = voters.take(5).toList();
    final overflow = voters.length - visible.length;
    const avatarSize = 28.0;
    const overlap = 19.0;
    final itemCount = visible.length + (overflow > 0 ? 1 : 0);

    return Semantics(
      label: context.l10n.t(
        'polls.participants',
        params: {'count': voters.length.toString()},
      ),
      child: SizedBox(
        height: avatarSize,
        width: avatarSize + (itemCount - 1) * overlap,
        child: Stack(
          children: [
            for (var index = 0; index < visible.length; index++)
              Positioned(
                left: index * overlap,
                child: Tooltip(
                  message: visible[index].displayName,
                  child: CircleAvatar(
                    radius: avatarSize / 2,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    backgroundImage: visible[index].avatarUrl.isNotEmpty
                        ? CachedNetworkImageProvider(visible[index].avatarUrl)
                        : null,
                    child: visible[index].avatarUrl.isEmpty
                        ? Text(
                            _initials(visible[index].displayName),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          )
                        : null,
                  ),
                ),
              ),
            if (overflow > 0)
              Positioned(
                left: visible.length * overlap,
                child: CircleAvatar(
                  radius: avatarSize / 2,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  child: Text(
                    '+$overflow',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
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

  Widget _buildTravelTemplates(BuildContext context) {
    final templates = [
      ('polls.template_stay', Icons.hotel_outlined),
      ('polls.template_eat', Icons.restaurant_outlined),
      ('polls.template_do', Icons.local_activity_outlined),
      ('polls.template_when', Icons.calendar_month_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t('polls.templates_title'),
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final template in templates)
              ActionChip(
                avatar: Icon(template.$2, size: 18),
                label: Text(context.l10n.t(template.$1)),
                onPressed: () {
                  _question.text = context.l10n.t('${template.$1}_question');
                  _question.selection = TextSelection.collapsed(
                    offset: _question.text.length,
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xs,
      AppSpacing.lg,
      MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JourneySectionHeader(
            title: context.l10n.t('polls.create'),
            subtitle: context.l10n.t('polls.empty_hint'),
            icon: Icons.add_chart_rounded,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildTravelTemplates(context),
          const SizedBox(height: AppSpacing.lg),
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
