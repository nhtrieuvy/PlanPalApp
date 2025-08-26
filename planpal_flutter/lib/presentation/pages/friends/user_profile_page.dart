import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/friend_repository.dart';
import '../../../core/models/user_summary.dart';
import '../../../core/theme/app_colors.dart';

class UserProfilePage extends StatefulWidget {
  final UserSummary user;

  const UserProfilePage({super.key, required this.user});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late final FriendRepository _friendRepo;
  String? _friendshipStatus;
  bool _loading = false;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _friendRepo = FriendRepository(context.read<AuthProvider>());
    _loadFriendshipStatus();
  }

  Future<void> _loadFriendshipStatus() async {
    setState(() => _loading = true);
    try {
      final status = await _friendRepo.getFriendshipStatus(widget.user.id);
      if (!mounted) return;
      setState(() {
        _friendshipStatus = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _sendFriendRequest() async {
    setState(() => _actionLoading = true);
    try {
      await _friendRepo.sendFriendRequest(widget.user.id);
      if (!mounted) return;
      setState(() {
        _friendshipStatus = 'pending';
        _actionLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã gửi lời mời kết bạn')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = context.read<AuthProvider>().user;
    final isOwnProfile = currentUser?.id == widget.user.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user.displayName),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Cover/Header section
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
                  // Avatar
                  _buildAvatar(),
                  const SizedBox(height: 16),
                  // Name
                  Text(
                    widget.user.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Username
                  Text(
                    '@${widget.user.username}',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  // Online status
                  if (widget.user.isOnline)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Đang online',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Action button section
            if (!isOwnProfile) ...[
              const SizedBox(height: 24),
              _buildActionButton(),
            ],

            // Profile info section
            const SizedBox(height: 24),
            _buildProfileInfo(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    const size = 80.0;
    final initials = widget.user.initials;
    final avatarUrl = widget.user.avatarForDisplay;

    if (avatarUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: size,
            height: size,
            color: Colors.white.withValues(alpha: 0.2),
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
          ),
          errorWidget: (context, url, error) => Container(
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
          ),
        ),
      );
    }

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
    if (_loading) {
      return const CircularProgressIndicator();
    }

    Widget button;
    String text;
    Color color;
    VoidCallback? onPressed;

    switch (_friendshipStatus) {
      case 'accepted':
        text = 'Đã là bạn bè';
        color = Colors.green;
        onPressed = null; // Disabled
        break;
      case 'pending':
        text = 'Đã gửi lời mời';
        color = Colors.orange;
        onPressed = null; // Disabled
        break;
      case 'blocked':
        text = 'Đã chặn';
        color = Colors.red;
        onPressed = null; // Disabled
        break;
      default:
        text = 'Kết bạn';
        color = AppColors.primary;
        onPressed = _actionLoading ? null : _sendFriendRequest;
    }

    button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: _actionLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(_getButtonIcon()),
      label: Text(text),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 2,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: button,
    );
  }

  IconData _getButtonIcon() {
    switch (_friendshipStatus) {
      case 'accepted':
        return Icons.check;
      case 'pending':
        return Icons.schedule;
      case 'blocked':
        return Icons.block;
      default:
        return Icons.person_add;
    }
  }

  Widget _buildProfileInfo(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thông tin cá nhân',
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
                    'Tên hiển thị',
                    widget.user.displayName,
                  ),
                  const Divider(),
                  _buildInfoRow(
                    Icons.alternate_email,
                    'Username',
                    '@${widget.user.username}',
                  ),
                  if (widget.user.fullName.isNotEmpty) ...[
                    const Divider(),
                    _buildInfoRow(
                      Icons.badge,
                      'Họ và tên',
                      widget.user.fullName,
                    ),
                  ],
                  if (widget.user.email != null) ...[
                    const Divider(),
                    _buildInfoRow(Icons.email, 'Email', widget.user.email!),
                  ],
                  const Divider(),
                  _buildInfoRow(
                    Icons.circle,
                    'Trạng thái',
                    widget.user.statusText,
                    valueColor: widget.user.isOnline
                        ? Colors.green
                        : Colors.grey,
                  ),
                  if (widget.user.dateJoined != null) ...[
                    const Divider(),
                    _buildInfoRow(
                      Icons.calendar_today,
                      'Tham gia',
                      _formatDate(widget.user.dateJoined!),
                    ),
                  ],
                  if (widget.user.lastSeen != null &&
                      !widget.user.isOnline) ...[
                    const Divider(),
                    _buildInfoRow(
                      Icons.access_time,
                      'Hoạt động cuối',
                      _formatDate(widget.user.lastSeen!),
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
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} phút trước';
    } else {
      return 'Vừa xong';
    }
  }
}
