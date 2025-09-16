import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/friend_repository.dart';
import '../../../core/dtos/user_summary.dart';
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
        // Map backend status values to frontend expected values
        _friendshipStatus = _mapBackendStatusToFrontend(status);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Set default status when API fails - assume no relationship exists
        _friendshipStatus = 'none';
        _loading = false;
      });
    }
  }

  /// Maps backend status response to frontend expected values
  String? _mapBackendStatusToFrontend(String? backendStatus) {
    switch (backendStatus) {
      case 'friends':
        return 'accepted';
      case 'pending_sent':
      case 'pending_received':
        return 'pending';
      case 'blocked':
        return 'blocked';
      default:
        return 'none'; 
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã gửi lời mời kết bạn')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _unfriend() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận'),
        content: Text(
          'Bạn có chắc muốn hủy kết bạn với ${widget.user.fullName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      await _friendRepo.unfriend(widget.user.id);
      if (!mounted) return;
      setState(() {
        _friendshipStatus = 'none';
        _actionLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã hủy kết bạn')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _blockUser() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận chặn'),
        content: Text(
          'Bạn có chắc muốn chặn ${widget.user.fullName}? Họ sẽ không thể gửi tin nhắn hoặc lời mời kết bạn cho bạn nữa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Chặn'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      await _friendRepo.blockUser(widget.user.id);
      if (!mounted) return;
      setState(() {
        _friendshipStatus = 'blocked';
        _actionLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã chặn người dùng')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _unblockUser() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ chặn'),
        content: Text('Bạn có muốn bỏ chặn ${widget.user.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bỏ chặn'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);
    try {
      await _friendRepo.unblockUser(widget.user.id);
      if (!mounted) return;

      // Refresh status from server instead of hardcoding
      await _loadFriendshipStatus();
      if (!mounted) return;

      setState(() => _actionLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã bỏ chặn người dùng')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionLoading = false);
      if (!mounted) return;
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
        title: Text(widget.user.fullName),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: !isOwnProfile
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
                      const PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            Icon(Icons.block, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Chặn người dùng'),
                          ],
                        ),
                      ),
                    if (_friendshipStatus == 'blocked')
                      const PopupMenuItem(
                        value: 'unblock',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Bỏ chặn'),
                          ],
                        ),
                      ),
                  ],
                ),
              ]
            : null,
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
                    widget.user.fullName,
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

    switch (_friendshipStatus) {
      case 'accepted':
        // Hiển thị "Bạn bè" và nút "Hủy kết bạn" kế bên
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Nút "Bạn bè" (chỉ hiển thị, không có action)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Bạn bè',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Nút "Hủy kết bạn"
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
              label: const Text('Hủy kết bạn'),
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
                elevation: 2,
              ),
            ),
          ],
        );
      case 'pending':
        return ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.schedule),
          label: const Text('Đã gửi lời mời'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.orange,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 2,
          ),
        );
      case 'blocked':
        return ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.block),
          label: const Text('Đã chặn'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 2,
          ),
        );
      default:
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
          label: const Text('Kết bạn'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 2,
          ),
        );
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
                    widget.user.fullName,
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
                  const Divider(),
                  _buildInfoRow(
                    Icons.calendar_today,
                    'Tham gia',
                    _formatDate(widget.user.dateJoined),
                  ),
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
