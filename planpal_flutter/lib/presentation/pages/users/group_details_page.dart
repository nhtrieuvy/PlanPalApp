import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/dtos/group_model.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/providers/conversation_provider.dart';
import 'package:planpal_flutter/core/repositories/group_repository.dart';
import 'package:planpal_flutter/core/repositories/friend_repository.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/dtos/user_summary.dart';
import '../../../core/dtos/plan_summary.dart';
import '../../../core/dtos/group_requests.dart';
import '../../../core/dtos/conversation.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import 'plan_form_page.dart';
import 'plan_details_page.dart';
import '../chat/chat_page.dart';

class GroupDetailsPage extends StatefulWidget {
  final String id;
  const GroupDetailsPage({super.key, required this.id});

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage>
    with RefreshablePage<GroupDetailsPage> {
  late final GroupRepository repo;
  late final PlanRepository planRepo;
  GroupModel? groupData;
  List<PlanSummary> groupPlans = [];
  bool isLoading = true;
  bool isLoadingPlans = false;
  String? error;

  @override
  void initState() {
    super.initState();
    repo = GroupRepository(context.read<AuthProvider>());
    planRepo = PlanRepository(context.read<AuthProvider>());
    _loadGroupData();
  }

  @override
  Future<void> onRefresh() async {
    await _loadGroupData();
  }

  Future<void> _loadGroupData() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });
      final data = await repo.getGroupDetail(widget.id);
      setState(() {
        groupData = data;
        isLoading = false;
      });
      // Load plans after group data is loaded
      _loadGroupPlans();
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _loadGroupPlans() async {
    try {
      setState(() => isLoadingPlans = true);
      final plans = await planRepo.getGroupPlans(widget.id);
      setState(() {
        groupPlans = plans;
        isLoadingPlans = false;
      });
    } catch (e) {
      setState(() => isLoadingPlans = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thể tải kế hoạch: $e')));
      }
    }
  }

  Future<void> _updateCoverImage() async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 400,
        imageQuality: 85,
      );

      if (picked != null) {
        final coverFile = File(picked.path);

        // Show loading dialog
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );

        // Update group with new cover image using DTO (no changes to name/description)
        final req = UpdateGroupRequest();
        await repo.updateGroup(widget.id, req, coverImage: coverFile);

        // Close loading dialog
        if (!mounted) return;
        Navigator.of(context).pop();

        // Reload group data to show updated cover
        await _loadGroupData();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ảnh bìa đã được cập nhật')),
        );
      }
    } catch (e) {
      // Close loading dialog if open
      if (!mounted) return;
      Navigator.of(context).pop();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Avoid nesting Scaffolds: return loading/error Scaffold directly.
    if (isLoading) return _buildLoading();
    if (error != null) return _buildError(context, error!);

    return Scaffold(body: _buildContent(context, groupData!, theme));
  }

  Widget _buildLoading() {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: const FlexibleSpaceBar(
              background: SizedBox.shrink(),
              title: Text('Chi tiết nhóm'),
              centerTitle: true,
            ),
          ),
        ],
        body: const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildError(BuildContext context, String error) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: const FlexibleSpaceBar(
              background: SizedBox.shrink(),
              title: Text('Chi tiết nhóm'),
              centerTitle: true,
            ),
          ),
        ],
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                Text(
                  'Đã xảy ra lỗi',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Quay lại'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, GroupModel g, ThemeData theme) {
    final name = g.name;
    final desc = g.description;
    final membersCount = g.memberCount;
    final members = g.members;
    final UserSummary admin = g.admin;
    final adminName = admin.fullName;
    final adminAvatar = admin.avatarUrl ?? '';
    final adminInitials = admin.initials;
    final coverUrl = g.coverImageUrl;

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton.filled(
                onPressed: () => _navigateToGroupChat(g),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.chat),
                tooltip: 'Chat nhóm',
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton.filled(
                onPressed: _updateCoverImage,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.photo_camera),
                tooltip: 'Cập nhật ảnh bìa',
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: coverUrl.isNotEmpty
                  ? BoxDecoration(
                      image: DecorationImage(
                        image: CachedNetworkImageProvider(coverUrl),
                        fit: BoxFit.cover,
                      ),
                    )
                  : const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppColors.primaryGradient,
                      ),
                    ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.white,
                          child: Builder(
                            builder: (context) {
                              final groupAvatarUrl = g.avatarUrl;
                              final groupInitials = g.initials.isNotEmpty
                                  ? g.initials
                                  : (name.isNotEmpty
                                        ? ((name
                                                      .trim()
                                                      .split(RegExp(r'\s+'))
                                                      .first[0] +
                                                  (name
                                                              .trim()
                                                              .split(
                                                                RegExp(r'\s+'),
                                                              )
                                                              .length >
                                                          1
                                                      ? name
                                                            .trim()
                                                            .split(
                                                              RegExp(r'\s+'),
                                                            )
                                                            .last[0]
                                                      : (name.length > 1
                                                            ? name[1]
                                                            : '?')))
                                              .toUpperCase())
                                        : '?');

                              if (groupAvatarUrl.isNotEmpty) {
                                return CircleAvatar(
                                  radius: 34,
                                  backgroundImage: CachedNetworkImageProvider(
                                    groupAvatarUrl,
                                  ),
                                );
                              }

                              return CircleAvatar(
                                radius: 34,
                                backgroundColor: AppColors.primary.withValues(
                                  alpha: 0.1,
                                ),
                                child: Text(
                                  groupInitials,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            name.isNotEmpty ? name : 'Nhóm không tên',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      body: RefreshablePageWrapper(
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildAdminCard(adminAvatar, adminName, adminInitials),
              const SizedBox(height: 16),
              if (desc?.isNotEmpty == true)
                _buildInfoCard('Mô tả', desc!, Icons.description_outlined),
              const SizedBox(height: 16),
              _buildMembersCard(membersCount, members),
              const SizedBox(height: 16),
              _buildPlansCard(g),
              const SizedBox(height: 24),
              _buildActionButtons(context, g),
              const SizedBox(height: 100), // Extra space for scrolling
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String content, IconData icon) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              content,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersCard(int membersCount, List<UserSummary> members) {
    final currentUser = context.read<AuthProvider>().user;
    final isAdmin = groupData!.admin.id == currentUser?.id;

    return Card(
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.people_alt_outlined,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Thành viên',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$membersCount',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Nút thêm thành viên cho admin
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _showAddMemberDialog,
                    icon: const Icon(Icons.person_add),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withAlpha(25),
                      foregroundColor: AppColors.primary,
                    ),
                    tooltip: 'Thêm thành viên',
                  ),
                ],
              ],
            ),
            if (members.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: members.take(12).map((member) {
                  // members already parsed to UserSummary objects
                  final display = member.fullName;
                  final initials = member.initials.isNotEmpty
                      ? member.initials.toUpperCase()
                      : (display.isNotEmpty
                            ? ((display.trim().split(RegExp(r'\s+')).first[0] +
                                      (display
                                                  .trim()
                                                  .split(RegExp(r'\s+'))
                                                  .length >
                                              1
                                          ? display
                                                .trim()
                                                .split(RegExp(r'\s+'))
                                                .last[0]
                                          : (display.length > 1
                                                ? display[1]
                                                : '?')))
                                  .toUpperCase())
                            : '?');
                  final avatar = member.avatarUrl ?? '';
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.1,
                        ),
                        backgroundImage: avatar.isNotEmpty
                            ? CachedNetworkImageProvider(avatar)
                            : null,
                        child: avatar.isEmpty
                            ? Text(
                                initials,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 72,
                        child: Text(
                          display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              if (members.length > 12)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '... và ${members.length - 12} thành viên khác',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdminCard(String avatarUrl, String name, String initials) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Colors.white,
              child: CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                backgroundImage: avatarUrl.isNotEmpty
                    ? CachedNetworkImageProvider(avatarUrl)
                    : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        initials,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quản trị viên',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    name.isNotEmpty ? name : 'Không rõ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlansCard(GroupModel g) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.event_note_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kế hoạch nhóm (${groupPlans.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _navigateToCreatePlan(g),
              icon: const Icon(Icons.add),
              label: const Text('Tạo kế hoạch mới'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
            const SizedBox(height: 16),
            if (isLoadingPlans)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (groupPlans.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_note_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Chưa có kế hoạch nào',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hãy tạo kế hoạch đầu tiên cho nhóm',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Danh sách kế hoạch:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...groupPlans.map((plan) => _buildPlanItem(plan)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToCreatePlan(GroupModel group) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => PlanFormPage(
              initial: {
                'group_id': group.id,
                'group_name': group.name,
                'plan_type': 'group',
              },
            ),
          ),
        )
        .then((_) {
          // Refresh plans list after creating a new plan
          _loadGroupPlans();
        });
  }

  void _navigateToPlanDetail(PlanSummary plan) {
    Navigator.of(context)
        .push<Map<String, dynamic>>(
          MaterialPageRoute(builder: (context) => PlanDetailsPage(id: plan.id)),
        )
        .then((result) {
          if (!mounted) return;
          if (result == null) return;

          if (result['action'] == 'delete' && result['id'] == plan.id) {
            setState(
              () => groupPlans = groupPlans
                  .where((p) => p.id != plan.id)
                  .toList(),
            );
          }

          if ((result['action'] == 'updated' || result['action'] == 'edit') &&
              result['plan'] is Map) {
            try {
              final updated = PlanSummary.fromJson(
                Map<String, dynamic>.from(result['plan'] as Map),
              );
              setState(
                () => groupPlans = groupPlans
                    .map((p) => p.id == updated.id ? updated : p)
                    .toList(),
              );
            } catch (_) {}
          }
        });
  }

  void _navigateToGroupChat(GroupModel group) async {
    try {
      // Load conversations and find the one for this group
      final conversationProvider = context.read<ConversationProvider>();
      await conversationProvider.loadConversations();

      // Find conversation by group ID
      final conversation = conversationProvider.conversations.firstWhere(
        (conv) =>
            conv.conversationType == ConversationType.group &&
            conv.group?.id == group.id,
        orElse: () => throw Exception('No conversation found for this group'),
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatPage(conversation: conversation),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tìm thấy cuộc trò chuyện: $e')),
        );
      }
    }
  }

  Widget _buildPlanItem(PlanSummary plan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _navigateToPlanDetail(plan),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.event, size: 16, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '${plan.activitiesCount} hoạt động',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          plan.statusDisplay,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, GroupModel g) {
    return Row(
      children: [
        Expanded(
          child: FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).pop({
                'action': 'edit',
                'group': {
                  'id': g.id,
                  'name': g.name,
                  'description': g.description,
                  'avatar_url': g.avatarUrl,
                  'cover_image_url': g.coverImageUrl,
                  'member_count': g.memberCount,
                },
              });
            },
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.edit),
            label: const Text('Chỉnh sửa'),
            heroTag: 'edit_group',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).pop({'action': 'delete', 'id': g.id});
            },
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Xóa nhóm'),
            heroTag: 'delete_group',
          ),
        ),
      ],
    );
  }

  Future<void> _showAddMemberDialog() async {
    final friendRepo = FriendRepository(context.read<AuthProvider>());

    // Load friends list
    List<UserSummary> friends = [];
    bool loading = true;
    String? error;

    try {
      friends = await friendRepo.getFriends();
      loading = false;
    } catch (e) {
      error = e.toString();
      loading = false;
    }

    if (!mounted) return;

    // Filter out users who are already members
    final currentMemberIds = groupData!.members.map((m) => m.id).toSet();
    final availableFriends = friends
        .where((friend) => !currentMemberIds.contains(friend.id))
        .toList();

    showDialog(
      context: context,
      builder: (context) => AddMemberDialog(
        availableFriends: availableFriends,
        loading: loading,
        error: error,
        onAddMember: (friendId) async {
          final scaffoldMessenger = ScaffoldMessenger.of(context);
          final navigator = Navigator.of(context);

          try {
            final req = AddMemberRequest(userId: friendId);
            await repo.addMember(widget.id, req);
            if (!mounted) return;
            navigator.pop();
            _loadGroupData(); // Reload group data
            if (!mounted) return;
            scaffoldMessenger.showSnackBar(
              const SnackBar(content: Text('Đã thêm thành viên thành công')),
            );
          } catch (e) {
            if (!mounted) return;
            scaffoldMessenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
          }
        },
      ),
    );
  }

  // Helper removed: use backend-provided 'initials' when available; inline fallback computed where needed.
}

class AddMemberDialog extends StatefulWidget {
  final List<UserSummary> availableFriends;
  final bool loading;
  final String? error;
  final Function(String) onAddMember;

  const AddMemberDialog({
    super.key,
    required this.availableFriends,
    required this.loading,
    this.error,
    required this.onAddMember,
  });

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  String _searchQuery = '';
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return AlertDialog(
        title: const Text('Thêm thành viên'),
        content: const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (widget.error != null) {
      return AlertDialog(
        title: const Text('Lỗi'),
        content: Text('Không thể tải danh sách bạn bè: ${widget.error}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      );
    }

    final filteredFriends = widget.availableFriends.where((friend) {
      return friend.fullName.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          friend.username.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return AlertDialog(
      title: const Text('Thêm thành viên'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            // Search field
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm kiếm bạn bè...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),
            // Friends list
            Expanded(
              child: filteredFriends.isEmpty
                  ? const Center(
                      child: Text('Không có bạn bè nào để thêm vào nhóm'),
                    )
                  : ListView.builder(
                      itemCount: filteredFriends.length,
                      itemBuilder: (context, index) {
                        final friend = filteredFriends[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: friend.avatarForDisplay.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    friend.avatarForDisplay,
                                  )
                                : null,
                            child: friend.avatarForDisplay.isEmpty
                                ? Text(friend.initials)
                                : null,
                          ),
                          title: Text(friend.fullName),
                          subtitle: Text('@${friend.username}'),
                          trailing: _adding
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () async {
                                    setState(() {
                                      _adding = true;
                                    });
                                    await widget.onAddMember(friend.id);
                                    setState(() {
                                      _adding = false;
                                    });
                                  },
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
