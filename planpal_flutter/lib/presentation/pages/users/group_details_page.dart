import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/dtos/group_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/riverpod/conversation_providers.dart';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/dtos/user_summary.dart';
import '../../../core/dtos/plan_summary.dart';
import '../../../core/dtos/group_membership.dart';
import '../../../core/dtos/group_requests.dart';
import '../../../core/dtos/conversation.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/error_display_service.dart';
import '../../widgets/common/refreshable_page_wrapper.dart';
import '../../widgets/audit/audit_log_list.dart';
import '../../../shared/ui_states/ui_states.dart';
import '../../../shared/widgets/widgets.dart';
import 'plan_form_page.dart';
import 'plan_details_page.dart';
import 'group_form_page.dart';
import 'group_invite_management_page.dart';
import '../chat/chat_page.dart';

class GroupDetailsPage extends ConsumerStatefulWidget {
  final String id;
  const GroupDetailsPage({super.key, required this.id});

  @override
  ConsumerState<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends ConsumerState<GroupDetailsPage>
    with RefreshablePage<GroupDetailsPage>, WidgetsBindingObserver {
  GroupModel? groupData;
  List<PlanSummary> groupPlans = [];
  bool isLoading = true;
  bool isLoadingPlans = false;
  bool _isDeletingGroup = false;
  int _auditRefreshSignal = 0;
  String? error;
  bool _hasChanges = false;
  WebSocketChannel? _groupChannel;
  StreamSubscription? _groupSubscription;
  Timer? _groupReconnectTimer;
  bool _manualGroupSocketDisconnect = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadGroupData(forceRefresh: true);
    _connectGroupRealtime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disconnectGroupRealtime();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadGroupData(forceRefresh: true, showLoading: false);
      _connectGroupRealtime();
    }
  }

  @override
  Future<void> onRefresh() async {
    await _loadGroupData(forceRefresh: true);
    if (mounted) {
      setState(() => _auditRefreshSignal++);
    }
  }

  Future<void> _connectGroupRealtime() async {
    final token = ref.read(authNotifierProvider).token;
    if (token == null || token.isEmpty) return;

    _manualGroupSocketDisconnect = false;
    await _groupSubscription?.cancel();
    await _groupChannel?.sink.close(ws_status.goingAway);

    try {
      final wsUrl = '$baseWsUrl/ws/groups/${widget.id}/?token=$token';
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await channel.ready;
      if (!mounted) {
        await channel.sink.close(ws_status.goingAway);
        return;
      }
      _groupChannel = channel;
      _groupSubscription = channel.stream.listen(
        _handleGroupRealtimeMessage,
        onError: (_) => _scheduleGroupRealtimeReconnect(),
        onDone: _scheduleGroupRealtimeReconnect,
      );
    } catch (_) {
      _scheduleGroupRealtimeReconnect();
    }
  }

  void _handleGroupRealtimeMessage(dynamic rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage as String);
      if (decoded is! Map) return;

      final eventType = decoded['event_type']?.toString();
      if (eventType != 'group.role_changed' &&
          eventType != 'group.member_added' &&
          eventType != 'group.member_removed') {
        return;
      }

      ref.read(groupRepositoryProvider).clearCacheEntry(widget.id);
      if (mounted) {
        _loadGroupData(forceRefresh: true, showLoading: false);
      }
    } catch (_) {
      // Ignore malformed realtime payloads; manual refresh still works.
    }
  }

  void _scheduleGroupRealtimeReconnect() {
    if (_manualGroupSocketDisconnect || !mounted) return;
    _groupReconnectTimer?.cancel();
    _groupReconnectTimer = Timer(
      const Duration(seconds: 2),
      _connectGroupRealtime,
    );
  }

  Future<void> _disconnectGroupRealtime() async {
    _manualGroupSocketDisconnect = true;
    _groupReconnectTimer?.cancel();
    await _groupSubscription?.cancel();
    await _groupChannel?.sink.close(ws_status.goingAway);
    _groupSubscription = null;
    _groupChannel = null;
  }

  Future<void> _loadGroupData({
    bool forceRefresh = false,
    bool showLoading = true,
  }) async {
    try {
      if (showLoading) {
        setState(() {
          isLoading = true;
          error = null;
        });
      }
      final repo = ref.read(groupRepositoryProvider);
      final data = await repo.getGroupDetail(
        widget.id,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        groupData = data;
        isLoading = false;
        error = null;
      });
      // Load plans after group data is loaded
      _loadGroupPlans();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _loadGroupPlans() async {
    try {
      setState(() => isLoadingPlans = true);
      final planRepo = ref.read(planRepositoryProvider);
      final result = await planRepo.getGroupPlansWithPermission(widget.id);
      final currentUserId = ref.read(authNotifierProvider).user?.id;
      setState(() {
        groupPlans = result.plans;
        final canCreatePlan =
            result.canCreatePlan ||
            (groupData?.canCreatePlanForUser(currentUserId) ?? false);
        if (groupData != null && groupData!.canCreatePlan != canCreatePlan) {
          groupData = groupData!.copyWith(canCreatePlan: canCreatePlan);
        }
        isLoadingPlans = false;
      });
    } catch (e) {
      setState(() => isLoadingPlans = false);
      if (mounted) {
        ErrorDisplayService.handleError(context, e);
      }
    }
  }

  Future<void> _updateCoverImage() async {
    final l10n = context.l10n;
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
              AppLoading(message: l10n.t('group_details.update_cover_loading')),
        );

        // Update group with new cover image using DTO (no changes to name/description)
        final req = UpdateGroupRequest();
        await ref
            .read(groupRepositoryProvider)
            .updateGroup(widget.id, req, coverImage: coverFile);

        // Close loading dialog
        if (!mounted) return;
        Navigator.of(context).pop();

        // Reload group data to show updated cover
        await _loadGroupData(forceRefresh: true);
        _hasChanges = true;
        if (mounted) {
          setState(() => _auditRefreshSignal++);
        }

        if (!mounted) return;
        ErrorDisplayService.showSuccessSnackbar(
          context,
          l10n.t('group_details.update_cover_success'),
        );
      }
    } catch (e) {
      // Close loading dialog if open
      if (!mounted) return;
      Navigator.of(context).pop();

      if (!mounted) return;
      ErrorDisplayService.handleError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Avoid nesting Scaffolds: return loading/error Scaffold directly.
    if (isLoading) return _buildLoading();
    if (error != null) return _buildError(context, error!);

    // Suppress deprecation warning for WillPopScope on older SDKs.
    // If you upgrade Flutter to v3.12+ we can replace this with PopScope.
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        // If changes were made on this page, return the updated group so
        // the caller can refresh its list without re-entering.
        if (_hasChanges && groupData != null) {
          Navigator.of(
            context,
          ).pop({'action': 'updated', 'group': groupData!.toJson()});
          return false; // we already popped
        }
        return true;
      },
      child: Scaffold(body: _buildContent(context, groupData!, theme)),
    );
  }

  Widget _buildLoading() {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: SizedBox.shrink(),
              title: Text(context.l10n.t('group_details.title')),
              centerTitle: true,
            ),
          ),
        ],
        body: const AppSkeleton.card(),
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
            flexibleSpace: FlexibleSpaceBar(
              background: SizedBox.shrink(),
              title: Text(context.l10n.t('group_details.title')),
              centerTitle: true,
            ),
          ),
        ],
        body: AppError(
          message: error,
          onRetry: () => _loadGroupData(forceRefresh: true),
          retryLabel: context.l10n.t('common.retry'),
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
                tooltip: context.l10n.t('group_details.chat_tooltip'),
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
                tooltip: context.l10n.t('group_details.update_cover_tooltip'),
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
                            name.isNotEmpty
                                ? name
                                : context.l10n.t('group_details.unnamed'),
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
                _buildInfoCard(
                  context.l10n.t('plan.description'),
                  desc!,
                  Icons.description_outlined,
                ),
              const SizedBox(height: 16),
              _buildMembersCard(membersCount, members),
              const SizedBox(height: 16),
              _buildPlansCard(g),
              const SizedBox(height: 16),
              AuditLogList(
                title: context.l10n.t('group_details.audit_log_title'),
                resourceType: 'group',
                resourceId: g.id,
                refreshSignal: _auditRefreshSignal,
              ),
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
    return InfoCard(
      icon: icon,
      title: title,
      content: content,
      accentColor: AppColors.primary,
    );
  }

  Widget _buildMembersCard(int membersCount, List<UserSummary> members) {
    final currentUser = ref.read(authNotifierProvider).user;
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
                Expanded(
                  child: SectionHeader(
                    title: context.l10n.t('group_details.members_title'),
                    icon: Icons.people_alt_outlined,
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
                // NÃºt thÃªm thÃ nh viÃªn cho admin
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _openInviteManagement,
                    icon: const Icon(Icons.link),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withAlpha(25),
                      foregroundColor: AppColors.primary,
                    ),
                    tooltip: context.l10n.t(
                      'group_details.invite_codes_tooltip',
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _showAddMemberDialog,
                    icon: const Icon(Icons.person_add),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withAlpha(25),
                      foregroundColor: AppColors.primary,
                    ),
                    tooltip: context.l10n.t('group_details.add_member'),
                  ),
                ],
              ],
            ),
            if (members.isNotEmpty) ...[
              // Instruction for admin
              if (isAdmin) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.blue[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.t('group_details.tap_member_remove'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: members.take(12).map((member) {
                  final membership = _membershipForUser(member.id);
                  final role =
                      membership?.role ??
                      (member.id == groupData!.admin.id ? 'admin' : 'member');
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
                  final isCurrentUserAdmin = groupData?.canEdit == true;
                  final currentUserId = ref.read(authNotifierProvider).user?.id;
                  final isSelf = member.id == currentUserId;
                  final isMemberAdmin = role == 'admin';
                  final isPlanCreator = role == 'plan_creator';

                  final canManageThisMember =
                      isCurrentUserAdmin && !isSelf && !isMemberAdmin;

                  return GestureDetector(
                    onTap: canManageThisMember
                        ? () => _showMemberOptions(member, role)
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: canManageThisMember
                            ? Border.all(
                                color: Colors.grey.withValues(alpha: 0.3),
                              )
                            : null,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
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
                              // Admin badge
                              if (isMemberAdmin)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(
                                      Icons.star,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              if (isPlanCreator)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(
                                      Icons.event_note,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              // Remove indicator for admin
                              if (isCurrentUserAdmin && !isSelf)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(
                                      Icons.remove,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
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
                          Text(
                            _roleLabel(role),
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: isMemberAdmin
                                  ? Colors.orange
                                  : isPlanCreator
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              fontWeight: isMemberAdmin || isPlanCreator
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          if (canManageThisMember)
                            SizedBox(
                              width: 72,
                              child: Text(
                                context.l10n.t('group_details.tap_to_remove'),
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (members.length > 12)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    context.l10n.t(
                      'group_details.other_members',
                      params: {'count': '${members.length - 12}'},
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  GroupMembership? _membershipForUser(String userId) {
    final memberships = groupData?.memberships ?? const <GroupMembership>[];
    for (final membership in memberships) {
      if (membership.user.id == userId) return membership;
    }
    return null;
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return context.l10n.t('group_details.role_admin');
      case 'plan_creator':
        return context.l10n.t('group_details.role_plan_creator');
      default:
        return context.l10n.t('group_details.role_member');
    }
  }

  Widget _buildAdminCard(String avatarUrl, String name, String initials) {
    final colorScheme = Theme.of(context).colorScheme;

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
              backgroundColor: colorScheme.surface,
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
                  Text(
                    context.l10n.t('group_details.admin_label'),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    name.isNotEmpty ? name : context.l10n.t('common.unknown'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: colorScheme.onSurface,
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
    final currentUserId = ref.read(authNotifierProvider).user?.id;
    final canCreatePlan = g.canCreatePlanForUser(currentUserId);

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
                Expanded(
                  child: SectionHeader(
                    title: context.l10n.t(
                      'group_details.plans_title',
                      params: {'count': '${groupPlans.length}'},
                    ),
                    icon: Icons.event_note_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (canCreatePlan) ...[
              ElevatedButton.icon(
                onPressed: () => _navigateToCreatePlan(g),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.t('group_details.create_plan')),
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
            ],
            if (isLoadingPlans)
              Padding(
                padding: EdgeInsets.all(8),
                child: AppLoading(
                  inline: true,
                  message: context.l10n.t('group_details.loading_plans'),
                ),
              )
            else if (groupPlans.isEmpty)
              AppEmpty(
                icon: Icons.event_note_outlined,
                title: context.l10n.t('group_details.empty_plans_title'),
                description: context.l10n.t(
                  'group_details.empty_plans_description',
                ),
                actionLabel: canCreatePlan
                    ? context.l10n.t('group_details.create_plan')
                    : null,
                onAction: canCreatePlan ? () => _navigateToCreatePlan(g) : null,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.t('group_details.plans_list'),
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
          if (mounted) {
            setState(() => _auditRefreshSignal++);
          }
        });
  }

  void _navigateToPlanDetail(PlanSummary plan) {
    // debug: log plan id before navigating to details
    // ignore: avoid_print
    print('GroupDetails: navigating to plan id=${plan.id}');
    Navigator.of(context)
        .push<Map<String, dynamic>>(
          MaterialPageRoute(builder: (context) => PlanDetailsPage(id: plan.id)),
        )
        .then((result) {
          if (!mounted) return;
          if (result == null) return;

          if (result['action'] == 'delete' && result['id'] == plan.id) {
            setState(() {
              groupPlans = groupPlans.where((p) => p.id != plan.id).toList();
              _auditRefreshSignal++;
            });
          }

          if ((result['action'] == 'updated' || result['action'] == 'edit') &&
              result['plan'] is Map) {
            try {
              final updated = PlanSummary.fromJson(
                Map<String, dynamic>.from(result['plan'] as Map),
              );
              setState(() {
                groupPlans = groupPlans
                    .map((p) => p.id == updated.id ? updated : p)
                    .toList();
                _auditRefreshSignal++;
              });
            } catch (_) {}
          }
        });
  }

  void _navigateToGroupChat(GroupModel group) async {
    try {
      // Load conversations and find the one for this group
      await ref.read(conversationListProvider.notifier).refresh();

      final conversations =
          ref.read(conversationListProvider).valueOrNull ?? [];
      // Find conversation by group ID
      final conversation = conversations.firstWhere(
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
        ErrorDisplayService.handleError(context, e);
      }
    }
  }

  Widget _buildPlanItem(PlanSummary plan) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mutedColor = colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _navigateToPlanDetail(plan),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.18 : 0.05,
                ),
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.event, size: 16, color: mutedColor),
                        const SizedBox(width: 4),
                        Text(
                          context.l10n.activityCountLabel(plan.activitiesCount),
                          style: TextStyle(fontSize: 12, color: mutedColor),
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.info_outline, size: 16, color: mutedColor),
                        const SizedBox(width: 4),
                        Text(
                          context.l10n.planStatusLabel(plan.status),
                          style: TextStyle(fontSize: 12, color: mutedColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: mutedColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, GroupModel g) {
    final currentUser = ref.read(authNotifierProvider).user;
    final isAdmin = g.admin.id == currentUser?.id;

    if (isAdmin) {
      // Admin cÃ³ thá»ƒ chá»‰nh sá»­a, xÃ³a nhÃ³m vÃ  rá»i nhÃ³m
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FloatingActionButton.extended(
                  onPressed: () => _navigateToEditGroup(g),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.edit),
                  label: Text(context.l10n.t('common.edit')),
                  heroTag: 'edit_group',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FloatingActionButton.extended(
                  onPressed: _isDeletingGroup
                      ? null
                      : () => _confirmDeleteGroup(g),
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  icon: _isDeletingGroup
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    _isDeletingGroup
                        ? context.l10n.t('group_details.delete_loading')
                        : context.l10n.t('common.delete'),
                  ),
                  heroTag: 'delete_group',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showLeaveGroupDialog(g),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.exit_to_app),
              label: Text(context.l10n.t('group_details.leave_action')),
            ),
          ),
        ],
      );
    } else {
      // ThÃ nh viÃªn thÆ°á»ng chá»‰ cÃ³ thá»ƒ rá»i nhÃ³m
      return SizedBox(
        width: double.infinity,
        child: FloatingActionButton.extended(
          onPressed: () => _showLeaveGroupDialog(g),
          backgroundColor: Colors.redAccent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.exit_to_app),
          label: Text(context.l10n.t('group_details.leave_action')),
          heroTag: 'leave_group',
        ),
      );
    }
  }

  Future<void> _navigateToEditGroup(GroupModel group) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => GroupFormPage(
          initial: {
            'id': group.id,
            'name': group.name,
            'description': group.description,
            'visibility': group.visibility,
            'avatar_url': group.avatarUrl,
            'cover_image_url': group.coverImageUrl,
            'member_count': group.memberCount,
          },
        ),
      ),
    );

    if (!mounted || result == null || result['action'] != 'updated') return;

    await _loadGroupData(forceRefresh: true);
    if (!mounted) return;
    _hasChanges = true;
    setState(() => _auditRefreshSignal++);
    ErrorDisplayService.showSuccessSnackbar(
      context,
      context.l10n.t('group_details.update_success'),
    );
  }

  Future<void> _openInviteManagement() async {
    final group = groupData;
    if (group == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupInviteManagementPage(
          groupId: group.id,
          groupName: group.name,
          groupVisibility: group.visibility,
        ),
      ),
    );

    if (!mounted) return;
    await _loadGroupData(forceRefresh: true, showLoading: false);
    if (mounted) {
      setState(() => _auditRefreshSignal++);
    }
  }

  Future<void> _confirmDeleteGroup(GroupModel group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('group_details.delete_title')),
        content: Text(
          context.l10n.t(
            'group_details.delete_confirm',
            params: {'group': group.name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('common.cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.t('common.delete')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingGroup = true);
    try {
      await ref.read(groupRepositoryProvider).deleteGroup(group.id);
      ref.read(groupRepositoryProvider).clearCacheEntry(group.id);

      if (!mounted) return;
      Navigator.of(context).pop({'action': 'deleted', 'id': group.id});
    } catch (e) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, e, showDialog: true);
    } finally {
      if (mounted) {
        setState(() => _isDeletingGroup = false);
      }
    }
  }

  Future<void> _showAddMemberDialog() async {
    final friendRepo = ref.read(friendRepositoryProvider);

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

    if (!context.mounted) return;

    // Filter out users who are already members
    final currentMemberIds = groupData!.members.map((m) => m.id).toSet();
    final availableFriends = friends
        .where((friend) => !currentMemberIds.contains(friend.id))
        .toList();

    final pageContext = context;
    showDialog(
      context: pageContext,
      builder: (dialogContext) => AddMemberDialog(
        availableFriends: availableFriends,
        loading: loading,
        error: error,
        onAddMember: (friendId) async {
          final navigator = Navigator.of(dialogContext);

          try {
            final req = AddMemberRequest(userId: friendId);
            await ref.read(groupRepositoryProvider).addMember(widget.id, req);
            if (!pageContext.mounted) return;
            navigator.pop();
            await _loadGroupData(forceRefresh: true); // Reload group data
            _hasChanges = true;
            if (mounted) {
              setState(() => _auditRefreshSignal++);
            }
            if (!pageContext.mounted) return;
            ErrorDisplayService.showSuccessSnackbar(
              pageContext,
              pageContext.l10n.t('group_details.add_member_success'),
            );
          } catch (e) {
            if (!pageContext.mounted) return;
            ErrorDisplayService.handleError(pageContext, e);
          }
        },
      ),
    );
  }

  // Dialog xÃ¡c nháº­n rá»i nhÃ³m
  Future<void> _showLeaveGroupDialog(GroupModel group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('group_details.leave_title')),
        content: Text(
          context.l10n.t(
            'group_details.leave_confirm',
            params: {'group': group.name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.l10n.t('group_details.leave_action')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _leaveGroup(group);
    }
  }

  // Dialog tÃ¹y chá»n cho thÃ nh viÃªn (admin sá»­ dá»¥ng)
  Future<void> _showMemberOptions(
    UserSummary member,
    String currentRole,
  ) async {
    final isPlanCreator = currentRole == 'plan_creator';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  backgroundImage: member.avatarUrl?.isNotEmpty == true
                      ? CachedNetworkImageProvider(member.avatarUrl!)
                      : null,
                  child: member.avatarUrl?.isEmpty != false
                      ? Text(
                          member.initials,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.fullName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '@${member.username}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),

            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPlanCreator ? Icons.event_busy : Icons.event_note,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              title: Text(
                isPlanCreator
                    ? context.l10n.t('group_details.revoke_plan_creator')
                    : context.l10n.t('group_details.grant_plan_creator'),
              ),
              subtitle: Text(
                isPlanCreator
                    ? context.l10n.t(
                        'group_details.revoke_plan_creator_description',
                      )
                    : context.l10n.t(
                        'group_details.grant_plan_creator_description',
                      ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _changeMemberRole(
                  member,
                  isPlanCreator ? 'member' : 'plan_creator',
                );
              },
            ),

            const SizedBox(height: 10),

            // Remove member option
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_remove,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              title: Text(
                context.l10n.t('group_details.member_options_remove'),
                style: TextStyle(color: Colors.red),
              ),
              subtitle: Text(
                context.l10n.t(
                  'group_details.member_options_remove_description',
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _showRemoveMemberDialog(member);
              },
            ),

            const SizedBox(height: 10),

            // Cancel button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.t('common.cancel')),
              ),
            ),

            // Safe area bottom
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  // Dialog xÃ¡c nháº­n xÃ³a thÃ nh viÃªn
  Future<void> _showRemoveMemberDialog(UserSummary member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('group_details.remove_member_title')),
        content: Text(
          context.l10n.t(
            'group_details.remove_member_confirm',
            params: {'name': member.fullName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.l10n.t('common.delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeMember(member);
    }
  }

  Future<void> _changeMemberRole(UserSummary member, String role) async {
    try {
      final request = ChangeMemberRoleRequest(userId: member.id, role: role);
      await ref
          .read(groupRepositoryProvider)
          .changeMemberRole(widget.id, request);

      if (!mounted) return;
      await _loadGroupData(forceRefresh: true);
      _hasChanges = true;
      if (!mounted) return;
      setState(() => _auditRefreshSignal++);

      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t(
          role == 'plan_creator'
              ? 'group_details.grant_plan_creator_success'
              : 'group_details.revoke_plan_creator_success',
          params: {'name': member.fullName},
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, e, showDialog: true);
    }
  }

  // Thá»±c hiá»‡n rá»i nhÃ³m
  Future<void> _leaveGroup(GroupModel group) async {
    try {
      final navigator = Navigator.of(context);
      await ref.read(groupRepositoryProvider).leaveGroup(group.id);

      if (!mounted) return;
      _hasChanges = true;
      navigator.pop({'action': 'left', 'id': group.id});

      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('group_details.leave_success'),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, e, showDialog: true);
    }
  }

  // Thá»±c hiá»‡n xÃ³a thÃ nh viÃªn
  Future<void> _removeMember(UserSummary member) async {
    try {
      final request = RemoveMemberRequest(userId: member.id);
      await ref.read(groupRepositoryProvider).removeMember(widget.id, request);

      if (!mounted) return;
      await _loadGroupData(forceRefresh: true); // Reload group data
      _hasChanges = true;
      if (!mounted) return;
      setState(() => _auditRefreshSignal++);

      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t(
          'group_details.remove_member_success',
          params: {'name': member.fullName},
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, e, showDialog: true);
    }
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
        title: Text(context.l10n.t('group_details.add_member_dialog_title')),
        content: SizedBox(
          height: 100,
          child: AppLoading(
            message: context.l10n.t('group_details.add_member_loading'),
          ),
        ),
      );
    }

    if (widget.error != null) {
      return AlertDialog(
        title: Text(context.l10n.t('common.error')),
        content: Text(
          context.l10n.t(
            'group_details.add_member_error',
            params: {'error': widget.error ?? ''},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('common.close')),
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
      title: Text(context.l10n.t('group_details.add_member_dialog_title')),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            // Search field
            TextField(
              decoration: InputDecoration(
                hintText: context.l10n.t(
                  'group_details.add_member_search_hint',
                ),
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
                  ? Center(
                      child: Text(
                        context.l10n.t('group_details.add_member_empty'),
                      ),
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
          child: Text(context.l10n.t('common.close')),
        ),
      ],
    );
  }
}
