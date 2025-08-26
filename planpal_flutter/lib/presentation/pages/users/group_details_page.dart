import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/group_repository.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/models/group_detail.dart';
import '../../../core/models/user_summary.dart';

class GroupDetailsPage extends StatefulWidget {
  final String id;
  const GroupDetailsPage({super.key, required this.id});

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  late final GroupRepository repo;
  GroupDetail? groupData;
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    repo = GroupRepository(context.read<AuthProvider>());
    _loadGroupData();
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
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
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

        // Update group with new cover image
  await repo.updateGroup(widget.id, {}, coverImage: coverFile);

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

    return Scaffold(
      body: isLoading
          ? _buildLoading()
          : error != null
          ? _buildError(context, error!)
          : _buildContent(context, groupData!, theme),
    );
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

  Widget _buildContent(BuildContext context, GroupDetail g, ThemeData theme) {
    final name = g.name;
    final desc = g.description;
    final membersCount = g.memberCount;
  final members = g.members;
  final UserSummary? admin = g.admin;
  final adminName = admin?.displayName.isNotEmpty == true
    ? admin!.displayName
    : (admin?.username ?? '');
  final adminAvatar = admin?.avatarUrl ?? '';
  final adminInitials = (admin?.initials.isNotEmpty == true)
    ? admin!.initials.toUpperCase()
    : (adminName.isNotEmpty
      ? (adminName.trim().split(RegExp(r'\s+')).first[0] +
        (adminName.trim().split(RegExp(r'\s+')).length > 1
          ? adminName.trim().split(RegExp(r'\s+')).last[0]
          : (adminName.length > 1 ? adminName[1] : '?')))
        .toUpperCase()
      : '?');
    final coverUrl = g.coverImageUrl ?? '';

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          actions: [
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
            centerTitle: true,
            title: Text(
              name.isNotEmpty ? name : 'Nhóm không tên',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
                final groupAvatarUrl = g.avatarThumb ?? '';
                final groupInitials = name.isNotEmpty
                  ? (name.trim().split(RegExp(r'\s+')).first[0] +
                      (name.trim().split(RegExp(r'\s+')).length > 1
                        ? name.trim().split(RegExp(r'\s+')).last[0]
                        : (name.length > 1 ? name[1] : '?')))
                    .toUpperCase()
                  : '?';

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildAdminCard(adminAvatar, adminName, adminInitials),
            const SizedBox(height: 16),
            if (desc.isNotEmpty)
              _buildInfoCard('Mô tả', desc, Icons.description_outlined),
            const SizedBox(height: 16),
            _buildMembersCard(membersCount, members),
            const SizedBox(height: 24),
            _buildActionButtons(context, g),
            const SizedBox(height: 100), // Extra space for scrolling
          ],
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

  Widget _buildMembersCard(int membersCount, List<dynamic> members) {
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
              ],
            ),
            if (members.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
        children: members.take(12).map((member) {
          // members already parsed to User objects
          final display = member.displayName?.isNotEmpty == true
            ? member.displayName!
            : (member.username ?? '');
          final initials = (member.initials?.isNotEmpty == true)
            ? member.initials!.toUpperCase()
            : (display.isNotEmpty
              ? (display.trim().split(RegExp(r'\s+')).first[0] +
                (display.trim().split(RegExp(r'\s+')).length > 1
                  ? display
                    .trim()
                    .split(RegExp(r'\s+'))
                    .last[0]
                  : (display.length > 1
                    ? display[1]
                    : '?')))
                .toUpperCase()
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

  Widget _buildActionButtons(BuildContext context, GroupDetail g) {
    return Row(
      children: [
        Expanded(
          child: FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).pop({'action': 'edit', 'group': {
                'id': g.id,
                'name': g.name,
                'description': g.description,
                'avatar_thumb': g.avatarThumb,
                'cover_image_url': g.coverImageUrl,
                'members_count': g.memberCount,
              }});
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

  // Helper removed: use backend-provided 'initials' when available; inline fallback computed where needed.
}
