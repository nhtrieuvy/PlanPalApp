import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';

class UserProfilePage extends ConsumerStatefulWidget {
  final UserSummary user;

  const UserProfilePage({super.key, required this.user});

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage>
    with WidgetsBindingObserver {
  late UserSummary _user;
  String? _friendshipStatus;
  String? _friendshipId;
  bool _loading = false;
  bool _actionLoading = false;
  bool _profileAccessDenied = false;
  String? _accessDeniedMessage;
  List<Map<String, dynamic>> _publications = const [];
  bool _publicationsLoading = true;
  bool _publicationsError = false;
  String? _nextPublicationsUrl;
  bool _loadingMorePublications = false;
  bool _checkingProfileAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _user = widget.user;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkProfileAccess();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkProfileAccess(silent: true);
  }

  Future<void> _checkProfileAccess({bool silent = false}) async {
    if (_checkingProfileAccess) return;
    _checkingProfileAccess = true;
    final l10n = context.l10n;
    if (!silent) setState(() => _loading = true);
    try {
      final profile = await ref
          .read(friendRepositoryProvider)
          .getUserProfile(widget.user.id);
      if (!mounted) return;
      setState(() {
        _user = profile;
        _profileAccessDenied = false;
        _accessDeniedMessage = null;
      });
      await _syncFriendshipStatus(stopLoading: !silent);
      await _loadPublications(silent: silent);
    } catch (error) {
      if (!mounted) return;

      final is403Error =
          (error is DioException && error.response?.statusCode == 403) ||
          (error is ApiException && error.statusCode == 403);

      if (is403Error) {
        setState(() {
          _profileAccessDenied = true;
          _accessDeniedMessage = l10n.t('user_profile.access_denied');
          _loading = false;
        });
        return;
      }

      if (!silent) setState(() => _loading = false);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.t(
                'user_profile.load_error',
                params: {
                  'error': ErrorDisplayService.getUserFriendlyMessage(error),
                },
              ),
            ),
          ),
        );
      }
    } finally {
      _checkingProfileAccess = false;
    }
  }

  Future<void> _loadPublications({bool silent = false}) async {
    if (!silent && mounted) setState(() => _publicationsLoading = true);
    try {
      final data = await ref
          .read(friendRepositoryProvider)
          .getPublishedProfile(widget.user.id);
      if (!mounted) return;
      setState(() {
        _publications = (data['publications'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _nextPublicationsUrl = data['next']?.toString();
        _publicationsLoading = false;
        _publicationsError = false;
      });
    } catch (_) {
      if (mounted && !silent) {
        setState(() {
          _publicationsLoading = false;
          _publicationsError = true;
        });
      }
    }
  }

  Future<void> _loadMorePublications() async {
    final nextUrl = _nextPublicationsUrl;
    if (nextUrl == null || _loadingMorePublications) return;
    setState(() => _loadingMorePublications = true);
    try {
      final data = await ref
          .read(friendRepositoryProvider)
          .getPublishedProfile(_user.id, nextPageUrl: nextUrl);
      if (!mounted) return;
      setState(() {
        _publications.addAll(
          (data['publications'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _nextPublicationsUrl = data['next']?.toString();
        _loadingMorePublications = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMorePublications = false);
      ErrorDisplayService.showErrorSnackbar(
        context,
        ErrorDisplayService.getUserFriendlyMessage(error),
      );
    }
  }

  Future<void> _inviteToTrip() async {
    final controller = TextEditingController();
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.t('friend_trip.invite_title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(context.l10n.t('friend_trip.invite_hint')),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: context.l10n.t('friend_trip.name'),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(sheetContext, value);
              },
              child: Text(context.l10n.t('friend_trip.send')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      await ref
          .read(friendRepositoryProvider)
          .inviteFriendToTrip(_user.id, name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('friend_trip.sent'))),
      );
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.showErrorSnackbar(
        context,
        ErrorDisplayService.getUserFriendlyMessage(error),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _loadFriendshipStatus() async {
    await _syncFriendshipStatus(stopLoading: true);
  }

  Future<bool> _syncFriendshipStatus({bool stopLoading = false}) async {
    try {
      final details = await ref
          .read(friendRepositoryProvider)
          .getFriendshipDetails(widget.user.id);
      if (!mounted) return false;

      setState(() {
        _applyFriendshipDetails(details);
        if (stopLoading) {
          _loading = false;
        }
      });

      return true;
    } catch (_) {
      if (!mounted) return false;

      if (stopLoading) {
        setState(() {
          _loading = false;
        });
      }

      // Keep the previous state on transient errors to avoid showing a wrong action.
      return false;
    }
  }

  void _applyFriendshipDetails(Map<String, dynamic>? details) {
    if (details == null) {
      _friendshipStatus = 'none';
      _friendshipId = null;
      return;
    }

    _friendshipStatus = _mapBackendStatusToFrontend(
      _extractBackendStatus(details),
    );
    _friendshipId = _extractFriendshipId(details);
  }

  String? _extractBackendStatus(Map<String, dynamic> details) {
    final rawStatus =
        details['status'] ??
        details['friendship_status'] ??
        details['friendshipStatus'];
    return rawStatus?.toString();
  }

  String? _extractFriendshipId(Map<String, dynamic> details) {
    final rawId = details['friendship_id'] ?? details['friendshipId'];
    return rawId?.toString();
  }

  String _mapBackendStatusToFrontend(String? backendStatus) {
    switch (backendStatus?.trim().toLowerCase()) {
      case 'accepted':
      case 'friend':
      case 'friends':
        return 'accepted';
      case 'pending':
      case 'request_sent':
      case 'pending_sent':
        return 'pending_sent';
      case 'request_received':
      case 'pending_received':
        return 'pending_received';
      case 'blocked':
      case 'blocked_by_me':
      case 'blocked_by_them':
        return 'blocked';
      case null:
      case '':
      case 'none':
      default:
        return 'none';
    }
  }

  String _extractErrorMessage(Object error) {
    return ErrorDisplayService.getUserFriendlyMessage(error);
  }

  bool _isAlreadyFriendsError(Object error) {
    final message = _extractErrorMessage(error).toLowerCase();
    return message.contains('already friends') ||
        message.contains('da la ban be') ||
        message.contains('đã là bạn bè');
  }

  Future<void> _sendFriendRequest() async {
    final l10n = context.l10n;
    setState(() => _actionLoading = true);
    try {
      await ref
          .read(friendRepositoryProvider)
          .sendFriendRequest(widget.user.id);
      if (!mounted) return;
      setState(() {
        _friendshipStatus = 'pending_sent';
        _actionLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('user_profile.request_sent'))),
      );
    } catch (error) {
      if (!mounted) return;

      final alreadyFriends = _isAlreadyFriendsError(error);
      await _syncFriendshipStatus();
      if (!mounted) return;

      if (alreadyFriends || _friendshipStatus == 'accepted') {
        setState(() {
          _friendshipStatus = 'accepted';
          _friendshipId = null;
          _actionLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.t('user_profile.friends'))));
        return;
      }

      if (_friendshipStatus == 'pending_sent') {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('user_profile.pending_sent'))),
        );
        return;
      }

      setState(() => _actionLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'user_profile.error',
              params: {'error': _extractErrorMessage(error)},
            ),
          ),
        ),
      );
    }
  }

  Future<void> _acceptFriendRequest() async {
    final l10n = context.l10n;
    if (_friendshipId == null) return;

    setState(() => _actionLoading = true);
    try {
      final success = await ref
          .read(friendRepositoryProvider)
          .acceptFriendRequest(_friendshipId!);
      if (!mounted) return;
      if (success) {
        setState(() {
          _friendshipStatus = 'accepted';
          _friendshipId = null;
          _actionLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('user_profile.accept_success'))),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'user_profile.error',
              params: {
                'error': ErrorDisplayService.getUserFriendlyMessage(error),
              },
            ),
          ),
        ),
      );
    }
  }

  Future<void> _declineFriendRequest() async {
    final l10n = context.l10n;
    if (_friendshipId == null) return;

    setState(() => _actionLoading = true);
    try {
      final success = await ref
          .read(friendRepositoryProvider)
          .rejectFriendRequest(_friendshipId!);
      if (!mounted) return;
      if (success) {
        setState(() {
          _friendshipStatus = 'none';
          _friendshipId = null;
          _actionLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('user_profile.reject_success'))),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'user_profile.error',
              params: {
                'error': ErrorDisplayService.getUserFriendlyMessage(error),
              },
            ),
          ),
        ),
      );
    }
  }

  Future<void> _unfriend() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('common.confirm')),
        content: Text(
          l10n.t(
            'user_profile.unfriend_confirm',
            params: {'name': _user.fullName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.t('common.confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      await ref.read(friendRepositoryProvider).unfriend(widget.user.id);
      if (!mounted) return;
      setState(() {
        _friendshipStatus = 'none';
        _actionLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('user_profile.unfriend_success'))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'user_profile.error',
              params: {
                'error': ErrorDisplayService.getUserFriendlyMessage(error),
              },
            ),
          ),
        ),
      );
    }
  }

  Future<void> _blockUser() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('user_profile.block_title')),
        content: Text(
          l10n.t(
            'user_profile.block_confirm',
            params: {'name': _user.fullName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.t('user_profile.block_action')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      await ref.read(friendRepositoryProvider).blockUser(widget.user.id);
      if (!mounted) return;
      setState(() {
        _friendshipStatus = 'blocked';
        _actionLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('user_profile.block_success'))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'user_profile.error',
              params: {
                'error': ErrorDisplayService.getUserFriendlyMessage(error),
              },
            ),
          ),
        ),
      );
    }
  }

  Future<void> _unblockUser() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('user_profile.unblock_title')),
        content: Text(
          l10n.t(
            'user_profile.unblock_confirm',
            params: {'name': _user.fullName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('user_profile.unblock_action')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      await ref.read(friendRepositoryProvider).unblockUser(widget.user.id);
      if (!mounted) return;
      await _loadFriendshipStatus();
      if (!mounted) return;
      setState(() => _actionLoading = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.t('user_profile.unblock_success'))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'user_profile.error',
              params: {
                'error': ErrorDisplayService.getUserFriendlyMessage(error),
              },
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.read(authNotifierProvider).user;
    final isOwnProfile = currentUser?.id == _user.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(_user.fullName),
        actions: !isOwnProfile && !_profileAccessDenied
            ? [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'unfriend':
                        _unfriend();
                        break;
                      case 'block':
                        _blockUser();
                        break;
                      case 'unblock':
                        _unblockUser();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (_friendshipStatus == 'accepted')
                      PopupMenuItem(
                        value: 'unfriend',
                        child: Text(context.l10n.t('user_profile.unfriend')),
                      ),
                    if (_friendshipStatus != 'blocked')
                      PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            Icon(
                              Icons.block,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(context.l10n.t('user_profile.menu_block')),
                          ],
                        ),
                      ),
                    if (_friendshipStatus == 'blocked')
                      PopupMenuItem(
                        value: 'unblock',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 8),
                            Text(context.l10n.t('user_profile.menu_unblock')),
                          ],
                        ),
                      ),
                  ],
                ),
              ]
            : null,
      ),
      body: ResponsiveContent(
        mediumMaxWidth: 760,
        expandedMaxWidth: 960,
        child: _profileAccessDenied
            ? _buildAccessDeniedView()
            : _buildProfileContent(),
      ),
    );
  }

  Widget _buildAccessDeniedView() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 72, color: colors.error),
            const SizedBox(height: 24),
            Text(
              _accessDeniedMessage ??
                  l10n.t('user_profile.access_denied_default'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.t('user_profile.access_denied_description'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: Text(l10n.t('user_profile.back')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileContent() {
    final currentUser = ref.read(authNotifierProvider).user;
    final isOwnProfile = currentUser?.id == _user.id;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.sheet),
            ),
            child: JourneyPathBackdrop(
              color: Colors.white,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAvatar(),
                  const SizedBox(height: 16),
                  Text(
                    _user.fullName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${_user.username}',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  if (_user.isOnline && _friendshipStatus == 'accepted')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        context.l10n.t('user_profile.online'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!isOwnProfile) ...[
            const SizedBox(height: 24),
            _buildActionButton(),
          ],
          const SizedBox(height: 24),
          _buildProfileInfo(),
          _buildPublishedJourneys(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    const size = 80.0;
    final initials = _user.initials;
    final avatarUrl = _user.avatarForDisplay;

    if (avatarUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
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
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    if (_loading) {
      return const CircularProgressIndicator();
    }

    if (_friendshipStatus == null) {
      return OutlinedButton.icon(
        onPressed: _actionLoading
            ? null
            : () async {
                setState(() => _loading = true);
                await _loadFriendshipStatus();
              },
        icon: const Icon(Icons.refresh),
        label: Text(l10n.t('common.retry')),
      );
    }

    switch (_friendshipStatus) {
      case 'accepted':
        return FilledButton.icon(
          onPressed: _actionLoading ? null : _inviteToTrip,
          icon: const Icon(Icons.route_outlined),
          label: Text(l10n.t('friend_trip.plan_together')),
        );
      case 'pending_sent':
        return OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.schedule),
          label: Text(l10n.t('user_profile.pending_sent')),
        );
      case 'pending_received':
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _actionLoading ? null : _acceptFriendRequest,
              icon: _actionLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(l10n.t('user_profile.pending_received')),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _actionLoading ? null : _declineFriendRequest,
              icon: _actionLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : const Icon(Icons.close),
              label: Text(l10n.t('user_profile.pending_decline')),
            ),
          ],
        );
      case 'blocked':
        return OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.block),
          label: Text(l10n.t('user_profile.blocked')),
        );
      case 'none':
        return FilledButton.icon(
          onPressed: _actionLoading ? null : _sendFriendRequest,
          icon: _actionLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.person_add),
          label: Text(l10n.t('user_profile.add_friend')),
        );
      default:
        return OutlinedButton.icon(
          onPressed: _actionLoading
              ? null
              : () async {
                  setState(() => _loading = true);
                  await _loadFriendshipStatus();
                },
          icon: const Icon(Icons.refresh),
          label: Text(l10n.t('common.retry')),
        );
    }
  }

  Widget _buildProfileInfo() {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isOwnProfile = ref.read(authNotifierProvider).user?.id == _user.id;
    final canSeePresence = isOwnProfile || _friendshipStatus == 'accepted';

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: JourneySurface(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(
            l10n.t('user_profile.personal_info'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(l10n.t('user_profile.personal_info_hint')),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    Icons.person,
                    l10n.t('user_profile.display_name'),
                    _user.fullName,
                  ),
                  const Divider(),
                  _buildInfoRow(
                    Icons.alternate_email,
                    l10n.t('profile.username'),
                    '@${_user.username}',
                  ),
                  if (isOwnProfile && _user.email != null) ...[
                    const Divider(),
                    _buildInfoRow(
                      Icons.email,
                      l10n.t('auth.email'),
                      _user.email!,
                    ),
                  ],
                  if (canSeePresence) ...[
                    const Divider(),
                    _buildInfoRow(
                      Icons.circle,
                      l10n.t('user_profile.status'),
                      _user.isOnline
                          ? l10n.t('user_profile.online')
                          : l10n.t('friends.offline'),
                      valueColor: _user.isOnline
                          ? AppColors.success
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                  const Divider(),
                  _buildInfoRow(
                    Icons.calendar_today,
                    l10n.t('user_profile.joined'),
                    _formatDate(_user.dateJoined),
                  ),
                  if (canSeePresence &&
                      _user.lastSeen != null &&
                      !_user.isOnline) ...[
                    const Divider(),
                    _buildInfoRow(
                      Icons.access_time,
                      l10n.t('user_profile.last_active'),
                      _formatDate(_user.lastSeen!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublishedJourneys() {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('published.journeys'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l10n.t('published.profile_hint')),
          const SizedBox(height: 16),
          if (_publicationsLoading)
            const Center(child: CircularProgressIndicator())
          else if (_publicationsError)
            OutlinedButton.icon(
              onPressed: _loadPublications,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.t('common.retry')),
            )
          else if (_publications.isEmpty)
            JourneySurface(child: Text(l10n.t('published.empty')))
          else
            ..._publications.map((item) {
              final highlights = (item['highlights'] as List? ?? const []);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: JourneySurface(
                  onTap: () => context.push('/journeys/${item['id']}'),
                  semanticLabel: item['title']?.toString() ?? '',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['destination']?.toString() ?? '',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item['title']?.toString() ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(item['summary']?.toString() ?? ''),
                      if (highlights.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...highlights.map((highlight) {
                          final data = Map<String, dynamic>.from(
                            highlight as Map,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('- ${data['title']}'),
                          );
                        }),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(l10n.t('published.view_journey')),
                          const Spacer(),
                          const Icon(Icons.arrow_forward_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (_nextPublicationsUrl != null)
            TextButton(
              onPressed: _loadingMorePublications
                  ? null
                  : _loadMorePublications,
              child: Text(l10n.t('published.load_more')),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? colors.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return AppFormatters.shortDate(context, date);
    }
    if (difference.inDays > 0) {
      return l10n.t(
        'common.days_ago',
        params: {'count': '${difference.inDays}'},
      );
    }
    if (difference.inHours > 0) {
      return l10n.t(
        'common.hours_ago',
        params: {'count': '${difference.inHours}'},
      );
    }
    if (difference.inMinutes > 0) {
      return l10n.t(
        'common.minutes_ago',
        params: {'count': '${difference.inMinutes}'},
      );
    }
    return l10n.t('common.just_now');
  }
}
