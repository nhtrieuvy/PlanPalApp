import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:getwidget/getwidget.dart';
import '../../../core/providers/theme_provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/dtos/user.dart';
import 'package:planpal_flutter/core/dtos/plan_summary.dart';
import 'package:planpal_flutter/core/dtos/group_summary.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/repositories/group_repository.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:planpal_flutter/presentation/pages/users/group_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';
import 'package:planpal_flutter/presentation/pages/friends/friend_search_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _HomeContent();
  }
}

class _HomeContent extends StatefulWidget {
  const _HomeContent();

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  late final GroupRepository _groupRepo;
  late final PlanRepository _planRepo;
  bool _loading = false;
  String? _error;
  List<PlanSummary> _recentPlans = const <PlanSummary>[];
  List<GroupSummary> _activeGroups = const <GroupSummary>[];

  @override
  void initState() {
    super.initState();
    _groupRepo = GroupRepository(context.read<AuthProvider>());
    _planRepo = PlanRepository(context.read<AuthProvider>());
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await _planRepo.getPlans();
      final groups = await _groupRepo.getGroups();
      if (!mounted) return;
      setState(() {
        _recentPlans = plans.take(5).toList();
        _activeGroups = groups.take(5).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Lỗi: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _handleQuickCreatePlan() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const PlanFormPage()),
    );
    if (!mounted) return;
    if (result != null &&
        result['action'] == 'created' &&
        result['plan'] != null) {
      try {
        final map = Map<String, dynamic>.from(result['plan'] as Map);
        final summary = PlanSummary.fromJson(map);
        setState(
          () => _recentPlans = [summary, ..._recentPlans].take(5).toList(),
        );
      } catch (_) {
        // ignore malformed return
      }
    }
  }

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
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 60.0, bottom: 120),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 80),
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(height: 8),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _loadData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    )
                  : Column(
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

  // Drawer components
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

  Widget _buildDrawerHeader() {
    return Selector<AuthProvider, User?>(
      selector: (_, auth) => auth.user,
      builder: (context, user, _) {
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
              // Avatar: use CachedNetworkImage to show placeholder / error states
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: ClipOval(
                  child: user != null && user.avatarUrl != null
                      ? CachedNetworkImage(
                          imageUrl: user.avatarUrl!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          placeholder: (c, u) => Container(
                            color: Colors.grey[200],
                            child: const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (c, u, e) => Container(
                            color: Colors.grey[100],
                            child: Center(
                              child: Text(
                                user.initials.isNotEmpty ? user.initials : '?',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey[100],
                          child: Center(
                            child: Text(
                              user?.initials ?? '?',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user?.fullName ?? 'Chưa đăng nhập',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (user != null && user.email != null && user.email!.isNotEmpty)
                Text(
                  user.email!,
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

  // Content sections using loaded data
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
              child: GestureDetector(
                onTap: _handleQuickCreatePlan,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: const [
                      Icon(
                        Icons.add_location_alt,
                        color: AppColors.primary,
                        size: 32,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tạo kế hoạch',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/group'),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: const [
                      Icon(
                        Icons.group_add,
                        color: AppColors.secondary,
                        size: 32,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tham gia nhóm',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const FriendSearchPage(),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: const [
                      Icon(
                        Icons.person_search,
                        color: AppColors.success,
                        size: 32,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tìm bạn bè',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.map, color: AppColors.warning, size: 32),
                      SizedBox(height: 8),
                      Text(
                        'Bản đồ',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
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
              onPressed: () => Navigator.of(context).pushNamed('/plan'),
              child: const Text('Xem tất cả'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_recentPlans.isEmpty)
          const Text('Chưa có kế hoạch', style: TextStyle(color: Colors.grey))
        else
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _recentPlans.length,
              itemBuilder: (context, index) {
                final p = _recentPlans[index];
                return GestureDetector(
                  onTap: () {
                    final id = p.id;
                    if (id.isNotEmpty) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlanDetailsPage(id: id),
                        ),
                      );
                    }
                  },
                  child: _buildPlanCardItem(context, index, p),
                );
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
              onPressed: () => Navigator.of(context).pushNamed('/group'),
              child: const Text('Xem tất cả'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_activeGroups.isEmpty)
          const Text('Chưa có nhóm', style: TextStyle(color: Colors.grey))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _activeGroups.length,
            itemBuilder: (context, index) {
              final g = _activeGroups[index];
              return GestureDetector(
                onTap: () {
                  final id = g.id;
                  if (id.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupDetailsPage(id: id),
                      ),
                    );
                  }
                },
                child: _buildGroupCardItem(context, index, g),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPlanCardItem(BuildContext context, int index, PlanSummary p) {
    final colors = AppColors.cardColors;
    final color = colors[index % colors.length];
    final name = p.title.isNotEmpty ? p.title : 'Kế hoạch';

    return Container(
      width: 280,
      margin: EdgeInsets.only(right: index == _recentPlans.length - 1 ? 0 : 16),
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
                  child: Icon(Icons.event, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (p.startDate != null || p.endDate != null)
                        Text(
                          p.dateRange,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (p.groupName != null && p.groupName!.isNotEmpty)
              Text(
                'Nhóm: ${p.groupName}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.event_note, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  p.activitiesCountText,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: p.isUpcoming
                        ? AppColors.warning.withValues(alpha: 0.1)
                        : p.isOngoing
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    p.statusDisplay,
                    style: TextStyle(
                      color: p.isUpcoming
                          ? AppColors.warning
                          : p.isOngoing
                          ? AppColors.success
                          : AppColors.info,
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

  Widget _buildGroupCardItem(BuildContext context, int index, GroupSummary g) {
    final colors = AppColors.cardColors;
    final color = colors[index % colors.length];
    final name = g.name.isNotEmpty ? g.name : 'Nhóm';

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
              child: g.avatarForDisplay.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: g.avatarForDisplay,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Icon(Icons.group, color: color, size: 24),
                        errorWidget: (context, url, error) =>
                            Icon(Icons.group, color: color, size: 24),
                      ),
                    )
                  : Center(
                      child: Text(
                        g.initials,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    g.memberCountText,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
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
