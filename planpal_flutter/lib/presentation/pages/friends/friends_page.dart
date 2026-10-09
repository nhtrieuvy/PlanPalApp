import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/friendship.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/repositories/friend_repository.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/services/notification_websocket_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/pages/friends/friend_search_page.dart';
import 'package:planpal_flutter/presentation/pages/friends/user_profile_page.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';

import '../../widgets/common/refreshable_page_wrapper.dart';
import '../../../shared/ui_states/ui_states.dart';

class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({super.key});

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        RefreshablePage<FriendsPage> {
  late final TabController _tabController;
  final NotificationWebSocketService _presenceSocket =
      NotificationWebSocketService();
  StreamSubscription<NotificationSocketEvent>? _presenceSubscription;
  Timer? _presenceRefreshTimer;

  bool _loadingFriends = false;
  bool _loadingRequests = false;
  String? _friendsError;
  String? _requestsError;
  List<UserSummary> _friends = [];
  List<Friendship> _friendRequests = [];
  List<Friendship> _sentRequests = [];
  List<Map<String, dynamic>> _tripInvitations = [];

  FriendRepository get _friendRepo => ref.read(friendRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _setupPresenceUpdates();
    _startPresenceRefreshTimer();
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceRefreshTimer?.cancel();
    unawaited(_presenceSubscription?.cancel() ?? Future<void>.value());
    _presenceSocket.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _connectPresenceSocket();
    _loadData();
  }

  void _setupPresenceUpdates() {
    _connectPresenceSocket();
    _presenceSubscription = _presenceSocket.eventStream.listen(
      _handlePresenceEvent,
    );
  }

  void _startPresenceRefreshTimer() {
    _presenceRefreshTimer?.cancel();
    _presenceRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      unawaited(_loadFriends(silent: true));
    });
  }

  void _connectPresenceSocket() {
    final token = ref.read(authNotifierProvider).token;
    if (token == null || token.isEmpty) return;
    unawaited(_presenceSocket.connect(token));
  }

  void _handlePresenceEvent(NotificationSocketEvent event) {
    if (!mounted) return;
    if (event.type != NotificationSocketEventType.userOnline &&
        event.type != NotificationSocketEventType.userOffline) {
      return;
    }

    final userId = event.userId;
    final isOnline = event.isOnline;
    if (userId == null || isOnline == null) return;

    setState(() {
      _friends = [
        for (final friend in _friends)
          if (friend.id == userId)
            friend.copyWith(
              isOnline: isOnline,
              onlineStatus: isOnline ? 'online' : 'offline',
              lastSeen: event.lastSeen,
            )
          else
            friend,
      ];
    });
  }

  @override
  Future<void> onRefresh() async {
    await _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadFriends(),
      _loadFriendRequests(),
      _loadSentRequests(),
      _loadTripInvitations(),
    ]);
  }

  Future<void> _loadSentRequests() async {
    try {
      final requests = await _friendRepo.getSentRequests();
      if (mounted) setState(() => _sentRequests = requests);
    } catch (_) {
      // Incoming requests and friends remain usable during a partial failure.
    }
  }

  Future<void> _loadTripInvitations() async {
    try {
      final invitations = await _friendRepo.getTripInvitations();
      if (mounted) setState(() => _tripInvitations = invitations);
    } catch (_) {
      // Keep previously loaded invitations on transient network errors.
    }
  }

  Future<void> _decideTrip(String id, String decision) async {
    try {
      await _friendRepo.decideTripInvitation(id, decision);
      await _loadTripInvitations();
      if (!mounted) return;
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('friend_trip.updated'),
      );
    } catch (error) {
      if (mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _cancelSentRequest(Friendship request) async {
    try {
      await _friendRepo.cancelFriendRequest(request.id);
      if (mounted) {
        setState(() => _sentRequests.removeWhere((r) => r.id == request.id));
      }
    } catch (error) {
      if (mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _loadFriends({bool silent = false}) async {
    if (silent && _loadingFriends) return;
    if (!silent) {
      setState(() {
        _loadingFriends = true;
        _friendsError = null;
      });
    }
    try {
      final friends = await _friendRepo.getFriends();
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _loadingFriends = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _loadingFriends = false;
        _friendsError = ErrorDisplayService.getUserFriendlyMessage(error);
      });
    }
  }

  Future<void> _loadFriendRequests() async {
    setState(() {
      _loadingRequests = true;
      _requestsError = null;
    });
    try {
      final requests = await _friendRepo.getPendingRequests();
      if (!mounted) return;
      setState(() {
        _friendRequests = requests.toList();
        _loadingRequests = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRequests = false;
        _requestsError = ErrorDisplayService.getUserFriendlyMessage(error);
      });
    }
  }

  Future<void> _acceptFriendRequest(Friendship request) async {
    try {
      final success = await _friendRepo.acceptFriendRequest(request.id);
      if (!mounted) return;
      if (success) {
        setState(() {
          _friendRequests.removeWhere((item) => item.id == request.id);
          _friends.add(request.friend);
        });
        ErrorDisplayService.showSuccessSnackbar(
          context,
          context.l10n.t('friends.accept_success'),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _rejectFriendRequest(Friendship request) async {
    try {
      final success = await _friendRepo.rejectFriendRequest(request.id);
      if (!mounted) return;
      if (success) {
        setState(() {
          _friendRequests.removeWhere((item) => item.id == request.id);
        });
        ErrorDisplayService.showSuccessSnackbar(
          context,
          context.l10n.t('friends.reject_success'),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _onUserTap(UserSummary user) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfilePage(user: user)),
    );
    if (!mounted) return;
    await _loadFriends();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('friends.title')),
        actions: [
          IconButton(
            tooltip: l10n.t('friend_search.title'),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FriendSearchPage())),
            icon: const Icon(Icons.person_search_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: l10n.t(
                'friends.tab_friends',
                params: {'count': '${_friends.length}'},
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.t('friends.tab_requests')),
                  if (_friendRequests.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '${_friendRequests.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: ResponsiveContent(
        mediumMaxWidth: 860,
        expandedMaxWidth: 1080,
        child: TabBarView(
          controller: _tabController,
          children: [_buildFriendsList(), _buildRequestsList()],
        ),
      ),
    );
  }

  Widget _buildFriendsList() {
    final l10n = context.l10n;
    if (_loadingFriends) {
      return const AppSkeleton.list();
    }

    if (_friendsError != null) {
      return AppError(
        message: l10n.t('friends.load_friends_error'),
        onRetry: _loadFriends,
        retryLabel: l10n.t('common.retry'),
      );
    }

    if (_friends.isEmpty) {
      return AppEmpty(
        icon: Icons.people_outline,
        title: l10n.t('friends.empty_title'),
        description: l10n.t('friends.empty_description'),
      );
    }

    return RefreshablePageWrapper(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760 ? 2 : 1;
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: AppSpacing.xs,
              mainAxisSpacing: AppSpacing.xs,
              mainAxisExtent: 92,
            ),
            itemCount: _friends.length,
            itemBuilder: (context, index) => _buildFriendTile(_friends[index]),
          );
        },
      ),
    );
  }

  Widget _buildRequestsList() {
    final l10n = context.l10n;
    if (_loadingRequests) {
      return const AppSkeleton.list(itemCount: 4);
    }

    if (_requestsError != null) {
      return AppError(
        message: l10n.t('friends.load_requests_error'),
        onRetry: _loadFriendRequests,
        retryLabel: l10n.t('common.retry'),
      );
    }

    if (_friendRequests.isEmpty &&
        _sentRequests.isEmpty &&
        _tripInvitations.where((item) => item['status'] == 'pending').isEmpty) {
      return AppEmpty(
        icon: Icons.inbox_outlined,
        title: l10n.t('friends.empty_requests_title'),
        description: l10n.t('friends.empty_requests_description'),
      );
    }

    final myId = ref.read(authNotifierProvider).user?.id;
    final pendingTrips = _tripInvitations
        .where((item) => item['status'] == 'pending')
        .toList();
    return RefreshablePageWrapper(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (pendingTrips.isNotEmpty) ...[
            Text(
              l10n.t('friend_trip.pending'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ...pendingTrips.map((item) {
              final sentByMe = (item['sender'] as Map?)?['id'] == myId;
              final peer = Map<String, dynamic>.from(
                (sentByMe ? item['recipient'] : item['sender']) as Map,
              );
              final name = peer['name'];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: JourneySurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name']?.toString() ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(name?.toString() ?? ''),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: sentByMe
                            ? [
                                OutlinedButton(
                                  onPressed: () =>
                                      _decideTrip(item['id'], 'cancel'),
                                  child: Text(l10n.t('common.cancel')),
                                ),
                              ]
                            : [
                                FilledButton(
                                  onPressed: () =>
                                      _decideTrip(item['id'], 'accept'),
                                  child: Text(l10n.t('friends.accept')),
                                ),
                                OutlinedButton(
                                  onPressed: () =>
                                      _decideTrip(item['id'], 'decline'),
                                  child: Text(l10n.t('friends.decline')),
                                ),
                              ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_friendRequests.isNotEmpty) ...[
            Text(
              l10n.t('friends.tab_requests'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._friendRequests.map(_buildRequestTile),
          ],
          if (_sentRequests.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.t('friends.sent_requests'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._sentRequests.map(
              (request) => ListTile(
                title: Text(request.friend.fullName),
                subtitle: Text(l10n.t('user_profile.pending_sent')),
                trailing: TextButton(
                  onPressed: () => _cancelSentRequest(request),
                  child: Text(l10n.t('common.cancel')),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFriendTile(UserSummary friend) {
    final l10n = context.l10n;
    return JourneySurface(
      padding: EdgeInsets.zero,
      onTap: () => _onUserTap(friend),
      semanticLabel: friend.fullName,
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: _buildAvatar(friend),
        title: Text(
          friend.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '@${friend.username}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: friend.isOnline
                      ? AppColors.success
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  friend.isOnline
                      ? l10n.t('friends.online')
                      : l10n.t('friends.offline'),
                  style: TextStyle(
                    color: friend.isOnline
                        ? AppColors.success
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_rounded, size: 20),
      ),
    );
  }

  Widget _buildRequestTile(Friendship request) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: JourneySurface(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Column(
            children: [
              Row(
                children: [
                  _buildAvatar(request.friend),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.friend.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '@${request.friend.username}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.t('friends.request_sent'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _rejectFriendRequest(request),
                      child: Text(l10n.t('friends.decline')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _acceptFriendRequest(request),
                      child: Text(l10n.t('friends.accept')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(UserSummary user) {
    const size = 48.0;
    final initials = user.initials;

    if (user.avatarForDisplay.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: user.avatarForDisplay,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildAvatarFallback(initials, size),
          errorWidget: (context, url, error) =>
              _buildAvatarFallback(initials, size),
        ),
      );
    }

    return _buildAvatarFallback(initials, size);
  }

  Widget _buildAvatarFallback(String initials, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
