import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:planpal_flutter/core/riverpod/groups_notifier.dart';
import 'package:planpal_flutter/presentation/pages/users/group_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/group_form_page.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import '../../../core/dtos/group_summary.dart';
import '../../../core/services/error_display_service.dart';
import '../../../shared/ui_states/ui_states.dart';

class GroupPage extends ConsumerStatefulWidget {
  const GroupPage({super.key});

  @override
  ConsumerState<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends ConsumerState<GroupPage>
    with RefreshablePage<GroupPage> {
  @override
  Future<void> onRefresh() async {
    await ref.read(groupsNotifierProvider.notifier).refresh();
  }

  void _onCreateGroup() async {
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
      ErrorDisplayService.showSuccessSnackbar(context, 'Tạo nhóm thành công');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text(
              'Nhóm',
              style: TextStyle(fontWeight: FontWeight.w600),
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
        label: const Text('Tạo nhóm'),
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final groupsAsync = ref.watch(groupsNotifierProvider);

    return groupsAsync.when(
      loading: () => const AppSkeleton.list(itemCount: 6),
      error: (error, _) => AppError(
        message: 'Lỗi tải nhóm: $error',
        onRetry: onRefresh,
        retryLabel: 'Thử lại',
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
            final g = groups[index];
            return _buildGroupCard(g, index, theme);
          },
        );
      },
    );
  }

  Widget _buildGroupCard(GroupSummary g, int index, ThemeData theme) {
    final name = g.name.isNotEmpty ? g.name : 'Nhóm không tên';
    final desc = g.description;
    final membersCount = g.memberCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _handleGroupTap(g),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    // Avatar: prefer backend avatar_thumb for list view,
                    // fallback to initials if no avatar.
                    Builder(
                      builder: (_) {
                        final avatar = g.avatarUrl;
                        final initials = name
                            .trim()
                            .split(RegExp(r'\s+'))
                            .take(2)
                            .map((e) => e.isNotEmpty ? e[0] : '')
                            .join()
                            .toUpperCase();

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
                                color: AppColors.getCardColor(
                                  index,
                                ).withAlpha(25),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.getCardColor(
                                    index,
                                  ).withAlpha(25),
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
                              ),
                            ),
                          );
                        }

                        // Fallback to initials
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
                      },
                    ),
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
                          if (desc != null && desc.isNotEmpty)
                            Text(
                              desc,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
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

                // Members Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
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
                        '$membersCount thành viên',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[400],
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

  Future<void> _handleGroupTap(GroupSummary g) async {
    final id = g.id;
    if (id.isEmpty) return;

    final action = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => GroupDetailsPage(id: id)),
    );

    // Xử lý các action trả về từ group details page
    if (!mounted || action == null) return;

    // Nếu user rời nhóm, xóa khỏi danh sách
    if (action['action'] == 'left' && action['id'] == id) {
      ref.read(groupsNotifierProvider.notifier).removeGroup(id);
      ErrorDisplayService.showSuccessSnackbar(
        context,
        'Đã rời nhóm thành công',
      );
    }
    // Nếu có cập nhật thông tin nhóm, update shared state
    else if (action['action'] == 'updated' && action['group'] is Map) {
      try {
        final updatedGroupRaw = Map<String, dynamic>.from(
          action['group'] as Map,
        );
        final updatedSummary = GroupSummary.fromJson(updatedGroupRaw);
        ref.read(groupsNotifierProvider.notifier).updateGroup(updatedSummary);
      } catch (_) {
        // Nếu parse lỗi, reload toàn bộ danh sách
        await ref.read(groupsNotifierProvider.notifier).refresh();
      }
    }
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        AppEmpty(
          icon: Icons.group_outlined,
          title: 'Chưa có nhóm nào',
          description: 'Tạo nhóm đầu tiên để bắt đầu lập kế hoạch cùng nhau',
        ),
      ],
    );
  }
}
