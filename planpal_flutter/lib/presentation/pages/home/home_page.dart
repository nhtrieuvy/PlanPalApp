import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:getwidget/getwidget.dart';
import '../../../core/providers/theme_provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _HomeContent();
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(context),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGreetingSection(context),
                  const SizedBox(height: 24),
                  _buildQuickActions(context),
                  const SizedBox(height: 24),
                  _buildRecentPlans(context),
                  const SizedBox(height: 24),
                  _buildActiveGroups(context),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Main UI components
  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDrawerHeader(),
            _buildDrawerMenuItems(context),
            const Spacer(),
            _buildDrawerFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200.0,
      floating: false,
      pinned: true,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      actions: [
        Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return IconButton(
              icon: Icon(
                themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: Colors.white,
              ),
              onPressed: () => themeProvider.toggleTheme(),
            );
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'PlanPal',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.primaryGradient,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 60,
                right: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
              Positioned(
                bottom: -30,
                left: -30,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Drawer components
  Widget _buildDrawerHeader() {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final user = auth.user;
        return DrawerHeader(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white,
                backgroundImage:
                    user != null &&
                        user['avatar_url'] != null &&
                        user['avatar_url'].toString().isNotEmpty
                    ? NetworkImage(user['avatar_url'])
                    : null,
                child:
                    (user == null ||
                        user['avatar_url'] == null ||
                        user['avatar_url'].toString().isEmpty)
                    ? Text(
                        user != null && user['initials'] != null
                            ? user['initials']
                            : '',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                () {
                  if (user != null) {
                    final fullName = user['full_name']?.toString() ?? '';
                    if (fullName.isNotEmpty) {
                      return fullName;
                    } else if (user['username'] != null &&
                        user['username'].toString().isNotEmpty) {
                      return user['username'];
                    }
                  }
                  return 'Chưa đăng nhập';
                }(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (user != null &&
                  user['email'] != null &&
                  user['email'].toString().isNotEmpty)
                Text(
                  user['email'],
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawerMenuItems(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.groups),
          title: const Text('Nhóm'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/group');
          },
        ),
        ListTile(
          leading: const Icon(Icons.event_note),
          title: const Text('Kế hoạch'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/plan');
          },
        ),
        ListTile(
          leading: const Icon(Icons.person),
          title: const Text('Cá nhân'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/profile');
          },
        ),
      ],
    );
  }

  Widget _buildDrawerFooter() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        '© 2025 PlanPal',
        style: TextStyle(color: Colors.grey, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  // Content sections
  Widget _buildGreetingSection(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting;
    IconData greetingIcon;

    if (hour < 12) {
      greeting = 'Chào buổi sáng!';
      greetingIcon = Icons.wb_sunny;
    } else if (hour < 17) {
      greeting = 'Chào buổi chiều!';
      greetingIcon = Icons.wb_sunny_outlined;
    } else {
      greeting = 'Chào buổi tối!';
      greetingIcon = Icons.nights_stay;
    }

    return GFCard(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(0),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(greetingIcon, color: AppColors.primary, size: 28),
              const SizedBox(width: 12),
              Text(
                greeting,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sẵn sàng cho chuyến phiêu lưu tiếp theo chưa?',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hành động nhanh',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                'Tạo kế hoạch',
                Icons.add_location_alt,
                AppColors.primary,
                () {
                  // Navigate to create plan
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                'Tham gia nhóm',
                Icons.group_add,
                AppColors.secondary,
                () {
                  // Navigate to join group
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                'Khám phá',
                Icons.explore,
                AppColors.success,
                () {
                  // Navigate to explore
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                'Bản đồ',
                Icons.map,
                AppColors.warning,
                () {
                  // Navigate to map
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentPlans(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Kế hoạch gần đây',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // Navigate to all plans
              },
              child: const Text('Xem tất cả'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            itemBuilder: (context, index) {
              return _buildPlanCard(context, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActiveGroups(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Nhóm hoạt động',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // Navigate to all groups
              },
              child: const Text('Xem tất cả'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          itemBuilder: (context, index) {
            return _buildGroupCard(context, index);
          },
        ),
      ],
    );
  }

  // Card widgets
  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, int index) {
    final colors = AppColors.cardColors;
    final color = colors[index % colors.length];

    return Container(
      width: 280,
      margin: EdgeInsets.only(right: index == 4 ? 0 : 16),
      child: GFCard(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.all(0),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.location_on, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chuyến đi ${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${index + 1}-${index + 3} tháng 8',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Khám phá những địa điểm tuyệt vời và tạo những kỷ niệm đáng nhớ cùng bạn bè.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.group, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${index + 2} thành viên',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Đang diễn ra',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(BuildContext context, int index) {
    final colors = AppColors.cardColors;
    final color = colors[index % colors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GFCard(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.all(0),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.group, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nhóm ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(index + 2) * 3} thành viên • ${index + 1} kế hoạch',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
