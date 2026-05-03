import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

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
    _checkProfileAccess();
  }

  Future<void> _checkProfileAccess() async {
    final l10n = context.l10n;
    setState(() => _loading = true);
    try {
      final profile = await ref
          .read(friendRepositoryProvider)
          .getUserProfile(widget.user.id);
      if (!mounted) return;
      setState(() {
        _user = profile;
      });
      await _loadFriendshipStatus();
    } catch (error) {
      if (!mounted) return;

      final is403Error = error is DioException
          ? error.response?.statusCode == 403
          : error.toString().contains('403') ||
                error.toString().toLowerCase().contains('forbidden');

      if (is403Error) {
        setState(() {
          _profileAccessDenied = true;
          _accessDeniedMessage = l10n.t('user_profile.access_denied');
          _loading = false;
        });
        return;
      }

      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.t(
                'user_profile.load_error',
                params: {'error': error.toString()},
              ),
            ),
          ),
        );
      }
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
    if (error is ApiException) {
      return error.message;
    }

    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail'] ?? data['message'] ?? data['error'];
        if (detail != null) {
          return detail.toString();
        }
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
    }

    return error.toString();
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
            l10n.t('user_profile.error', params: {'error': error.toString()}),
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
            l10n.t('user_profile.error', params: {'error': error.toString()}),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
            l10n.t('user_profile.error', params: {'error': error.toString()}),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
            l10n.t('user_profile.error', params: {'error': error.toString()}),
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
            l10n.t('user_profile.error', params: {'error': error.toString()}),
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
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: !isOwnProfile && !_profileAccessDenied
            ? [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'block':
                        _blockUser();
                        break;
                      case 'unblock':
                        _unblockUser();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (_friendshipStatus != 'blocked')
                      PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            const Icon(Icons.block, color: Colors.red),
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
                            const Icon(Icons.check_circle, color: Colors.green),
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
      body: _profileAccessDenied
          ? _buildAccessDeniedView()
          : _buildProfileContent(),
    );
  }

  Widget _buildAccessDeniedView() {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 80, color: Colors.red),
            const SizedBox(height: 24),
            Text(
              _accessDeniedMessage ??
                  l10n.t('user_profile.access_denied_default'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.t('user_profile.access_denied_description'),
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: Text(l10n.t('user_profile.back')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
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
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.8),
                ],
              ),
            ),
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
                if (_user.isOnline)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
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
          if (!isOwnProfile) ...[
            const SizedBox(height: 24),
            _buildActionButton(),
          ],
          const SizedBox(height: 24),
          _buildProfileInfo(),
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
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    l10n.t('user_profile.friends'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _actionLoading ? null : _unfriend,
              icon: _actionLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.person_remove),
              label: Text(l10n.t('user_profile.unfriend')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        );
      case 'pending_sent':
        return ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.schedule),
          label: Text(l10n.t('user_profile.pending_sent')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.orange,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        );
      case 'pending_received':
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _actionLoading ? null : _declineFriendRequest,
              icon: _actionLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                      ),
                    )
                  : const Icon(Icons.close),
              label: Text(l10n.t('user_profile.pending_decline')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        );
      case 'blocked':
        return ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.block),
          label: Text(l10n.t('user_profile.blocked')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        );
      case 'none':
        return ElevatedButton.icon(
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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('user_profile.personal_info'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                  if (_user.email != null) ...[
                    const Divider(),
                    _buildInfoRow(
                      Icons.email,
                      l10n.t('auth.email'),
                      _user.email!,
                    ),
                  ],
                  const Divider(),
                  _buildInfoRow(
                    Icons.circle,
                    l10n.t('user_profile.status'),
                    _user.isOnline
                        ? l10n.t('user_profile.online')
                        : l10n.t('friends.offline'),
                    valueColor: _user.isOnline
                        ? Colors.green
                        : Colors.grey,
                  ),
                  const Divider(),
                  _buildInfoRow(
                    Icons.calendar_today,
                    l10n.t('user_profile.joined'),
                    _formatDate(_user.dateJoined),
                  ),
                  if (_user.lastSeen != null && !_user.isOnline) ...[
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? Colors.black87,
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
