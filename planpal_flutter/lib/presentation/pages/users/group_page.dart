import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/group_summary.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/groups_notifier.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/presentation/pages/users/group_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/group_form_page.dart';

import '../../widgets/common/refreshable_page_wrapper.dart';
import '../../../shared/ui_states/ui_states.dart';

class GroupPage extends ConsumerStatefulWidget {
  const GroupPage({super.key});

  @override
  ConsumerState<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends ConsumerState<GroupPage>
    with RefreshablePage<GroupPage>, WidgetsBindingObserver {
  bool _didInitialResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_didInitialResume) {
      ref.read(groupsNotifierProvider.notifier).refreshSilently();
    } else {
      _didInitialResume = true;
    }
  }

  @override
  Future<void> onRefresh() async {
    await ref.read(groupsNotifierProvider.notifier).refresh();
  }

  Future<void> _onCreateGroup() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const GroupFormPage()),
    );
    if (result != null &&
        result['action'] == 'created' &&
        result['group'] != null) {
      final raw = Map<String, dynamic>.from(result['group'] as Map);
      GroupSummary? created;
      try {
        created = GroupSummary.fromJson(raw);
      } catch (_) {}
      if (!mounted || created == null) return;
      ref.read(groupsNotifierProvider.notifier).addGroup(created);
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('groups.created_success'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(
              l10n.t('groups.title'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            centerTitle: true,
            floating: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ],
        body: RefreshablePageWrapper(onRefresh: onRefresh, child: _buildBody()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onCreateGroup,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 8,
        icon: const Icon(Icons.group_add),
        label: Text(l10n.t('groups.create')),
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final groupsAsync = ref.watch(groupsNotifierProvider);

    return groupsAsync.when(
      loading: () => const AppSkeleton.list(itemCount: 6),
      error: (error, _) => AppError(
        message: l10n.t(
          'groups.load_error',
          params: {'error': ErrorDisplayService.getUserFriendlyMessage(error)},
        ),
        onRetry: onRefresh,
        retryLabel: l10n.t('common.retry'),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return _buildEmpty();
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            return _buildGroupCard(groups[index], index, theme);
          },
        );
      },
    );
  }

  Widget _buildGroupCard(GroupSummary group, int index, ThemeData theme) {
    final l10n = context.l10n;
    final colorScheme = theme.colorScheme;
    final name = group.name.isNotEmpty ? group.name : l10n.t('groups.unnamed');
    final description = group.description;
    final membersCount = group.memberCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _handleGroupTap(group),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildAvatar(group, name, index),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (description != null && description.isNotEmpty)
                            Text(
                              description,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.people_alt_outlined,
                        size: 20,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.memberCountLabel(membersCount),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(GroupSummary group, String name, int index) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.isNotEmpty ? part[0] : '')
        .join()
        .toUpperCase();
    final avatar = group.avatarUrl;

    if (avatar.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: avatar,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 56,
            height: 56,
            color: AppColors.getCardColor(index).withAlpha(25),
          ),
          errorWidget: (context, url, error) =>
              _buildAvatarFallback(initials, index),
        ),
      );
    }

    return _buildAvatarFallback(initials, index);
  }

  Widget _buildAvatarFallback(String initials, int index) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.getCardColor(index).withAlpha(25),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: AppColors.getCardColor(index),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Future<void> _handleGroupTap(GroupSummary group) async {
    final id = group.id;
    if (id.isEmpty) return;

    final action = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => GroupDetailsPage(id: id)),
    );

    if (!mounted) return;
    await ref.read(groupsNotifierProvider.notifier).refreshSilently();
    if (!mounted || action == null) return;

    if (action['action'] == 'left' && action['id'] == id) {
      ref.read(groupsNotifierProvider.notifier).removeGroup(id);
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('groups.left_success'),
      );
    } else if (action['action'] == 'updated' && action['group'] is Map) {
      try {
        final updatedSummary = GroupSummary.fromJson(
          Map<String, dynamic>.from(action['group'] as Map),
        );
        ref.read(groupsNotifierProvider.notifier).updateGroup(updatedSummary);
      } catch (_) {
        await ref.read(groupsNotifierProvider.notifier).refresh();
      }
    }
  }

  Widget _buildEmpty() {
    final l10n = context.l10n;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        AppEmpty(
          icon: Icons.group_outlined,
          title: l10n.t('groups.empty_title'),
          description: l10n.t('groups.empty_description'),
        ),
      ],
    );
  }
}
