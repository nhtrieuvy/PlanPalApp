import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/repositories/friend_repository.dart';
import '../../../core/dtos/user_summary.dart';
import '../../../core/dtos/friendship.dart';
import '../../../core/theme/app_colors.dart';
import 'user_profile_page.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage>
    with SingleTickerProviderStateMixin {
  late final FriendRepository _friendRepo;
  late final TabController _tabController;

  bool _loadingFriends = false;
  bool _loadingRequests = false;
  List<UserSummary> _friends = [];
  List<Friendship> _friendRequests = [];

  @override
  void initState() {
    super.initState();
    _friendRepo = FriendRepository(context.read<AuthProvider>());
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadFriends(), _loadFriendRequests()]);
  }

  Future<void> _loadFriends() async {
    setState(() => _loadingFriends = true);
    try {
      final friends = await _friendRepo.getFriends();
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _loadingFriends = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingFriends = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi tải danh sách bạn bè: $e')));
    }
  }

  Future<void> _loadFriendRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final requests = await _friendRepo.getPendingRequests();
      if (!mounted) return;
      setState(() {
        // Convert from pending friendships to friend request detail objects
        _friendRequests = requests.toList();
        _loadingRequests = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRequests = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi tải lời mời kết bạn: $e')));
    }
  }

  Future<void> _acceptFriendRequest(Friendship request) async {
    try {
      final success = await _friendRepo.acceptFriendRequest(request.id);
      if (!mounted) return;

      if (success) {
        setState(() {
          _friendRequests.removeWhere((r) => r.id == request.id);
          _friends.add(
            request.friend,
          ); // friend field represents the other user (initiator in this case)
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã chấp nhận lời mời kết bạn')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _rejectFriendRequest(Friendship request) async {
    try {
      final success = await _friendRepo.rejectFriendRequest(request.id);
      if (!mounted) return;

      if (success) {
        setState(() {
          _friendRequests.removeWhere((r) => r.id == request.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã từ chối lời mời kết bạn')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  void _onUserTap(UserSummary user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => UserProfilePage(user: user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bạn bè'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Bạn bè (${_friends.length})'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Lời mời'),
                  if (_friendRequests.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
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
      body: TabBarView(
        controller: _tabController,
        children: [_buildFriendsList(), _buildRequestsList()],
      ),
    );
  }

  Widget _buildFriendsList() {
    if (_loadingFriends) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_friends.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Chưa có bạn bè',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Hãy tìm kiếm và kết bạn với những người bạn biết',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFriends,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _friends.length,
        itemBuilder: (context, index) {
          final friend = _friends[index];
          return _buildFriendTile(friend);
        },
      ),
    );
  }

  Widget _buildRequestsList() {
    if (_loadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_friendRequests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Không có lời mời nào',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Các lời mời kết bạn sẽ xuất hiện ở đây',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFriendRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _friendRequests.length,
        itemBuilder: (context, index) {
          final request = _friendRequests[index];
          return _buildRequestTile(request);
        },
      ),
    );
  }

  Widget _buildFriendTile(UserSummary friend) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: friend.isOnline ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  friend.isOnline ? 'Đang online' : 'Offline',
                  style: TextStyle(
                    color: friend.isOnline ? Colors.green : Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey[400],
        ),
        onTap: () => _onUserTap(friend),
      ),
    );
  }

  Widget _buildRequestTile(Friendship request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _buildAvatar(
                  request.friend,
                ), // friend field represents the initiator in friend requests
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
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Đã gửi lời mời kết bạn',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Từ chối'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptFriendRequest(request),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Chấp nhận'),
                  ),
                ),
              ],
            ),
          ],
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
          placeholder: (context, url) => Container(
            width: size,
            height: size,
            color: AppColors.primary.withValues(alpha: 0.1),
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
          ),
          errorWidget: (context, url, error) => Container(
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
          ),
        ),
      );
    }

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
