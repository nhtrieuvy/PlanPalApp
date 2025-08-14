import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/models/user.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:getwidget/getwidget.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:planpal_flutter/core/repositories/user_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Constants
  static const double _avatarRadius = 54.0;
  static const double _editIconSize = 20.0;
  static const EdgeInsets _pagePadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 32,
  );

  // Repo & API result
  late final UserRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = UserRepository(context.read<AuthProvider>());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Use Selector instead of watch so only this subtree rebuilds on user changes
    return Scaffold(
      appBar: AppBar(title: const Text('Trang cá nhân'), centerTitle: true),
      body: Selector<AuthProvider, User?>(
        selector: (_, p) => p.user,
        builder: (context, user, _) {
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: _pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(child: _buildAvatarSection(user, colorScheme)),
                const SizedBox(height: 24),
                ..._buildStatisticsCards(user, colorScheme, theme),
                const SizedBox(height: 24),
                _buildUserNameSection(user, theme, colorScheme),
                const SizedBox(height: 24),
                _buildPersonalInfoCard(user, theme, colorScheme),
                const SizedBox(height: 32),
                _buildLogoutButton(context),
              ],
            ),
          );
        },
      ),
    );
  }

  // Widget builders
  Widget _buildAvatarSection(User user, ColorScheme colorScheme) {
    return Stack(
      children: [
        GFAvatar(
          backgroundImage: user.avatarUrl != null && user.avatarUrl != ''
              ? NetworkImage(user.avatarUrl!)
              : null,
          backgroundColor: colorScheme.primary.withAlpha(30),
          radius: _avatarRadius,
          child: (user.avatarUrl == null || user.avatarUrl == '')
              ? Text(
                  user.initials,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                )
              : null,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Material(
            color: colorScheme.primary,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                final user = context.read<AuthProvider>().user;
                if (user != null) await _showEditProfileDialog(context, user);
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  Icons.edit,
                  color: Colors.white,
                  size: _editIconSize,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserNameSection(
    User user,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Text(
      user.displayName.isNotEmpty
          ? user.displayName
          : (user.username.isNotEmpty ? user.username : ''),
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      textAlign: TextAlign.center,
    );
  }

  List<Widget> _buildStatisticsCards(
    User user,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final statisticsData = [
      {
        'icon': Icons.travel_explore,
        'label': 'Kế hoạch',
        'count': user.plansCount,
        'color': colorScheme.primary,
        'containerColor': colorScheme.primaryContainer,
      },
      {
        'icon': Icons.group,
        'label': 'Nhóm',
        'count': user.groupsCount,
        'color': colorScheme.secondary,
        'containerColor': colorScheme.secondaryContainer,
      },
      {
        'icon': Icons.people,
        'label': 'Bạn bè',
        'count': user.friendsCount,
        'color': colorScheme.tertiary,
        'containerColor': colorScheme.tertiaryContainer,
      },
    ];

    return statisticsData.map((stat) {
      return Column(
        children: [
          GFCard(
            color: stat['containerColor'] as Color,
            elevation: 1,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            content: Row(
              children: [
                Icon(
                  stat['icon'] as IconData,
                  color: stat['color'] as Color,
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    stat['label'] as String,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${stat['count']}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: stat['color'] as Color,
                  ),
                ),
              ],
            ),
          ),
          if (statisticsData.indexOf(stat) < statisticsData.length - 1)
            const SizedBox(height: 12),
        ],
      );
    }).toList();
  }

  Widget _buildPersonalInfoCard(
    User user,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return GFCard(
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thông tin cá nhân',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Tên đăng nhập', user.username),
          _buildInfoRow('Họ tên', user.displayName),
          _buildInfoRow('Email', user.email ?? ''),
          _buildInfoRow('Số điện thoại', user.phoneNumber ?? ''),
          _buildInfoRow('Ngày sinh', user.dateOfBirth ?? ''),
          const SizedBox(height: 8),
          _buildInfoRow('Giới thiệu', user.bio ?? ''),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return GFButton(
      onPressed: () async {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        await authProvider.logout();
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      },
      text: 'Đăng xuất',
      icon: const Icon(Icons.logout, color: Colors.white),
      type: GFButtonType.solid,
      shape: GFButtonShape.pills,
      size: GFSize.LARGE,
      color: AppColors.error,
      fullWidthButton: true,
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: const TextStyle(fontWeight: FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods
  Future<void> _showEditProfileDialog(BuildContext context, User user) async {
    final TextEditingController firstNameController = TextEditingController(
      text: user.firstName,
    );
    final TextEditingController lastNameController = TextEditingController(
      text: user.lastName,
    );
    final TextEditingController emailController = TextEditingController(
      text: user.email ?? '',
    );
    final TextEditingController phoneController = TextEditingController(
      text: user.phoneNumber ?? '',
    );
    final TextEditingController bioController = TextEditingController(
      text: user.bio ?? '',
    );

    File? selectedImage;
    final ImagePicker picker = ImagePicker();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Chỉnh sửa thông tin'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 800,
                      maxHeight: 800,
                      imageQuality: 85,
                    );
                    if (image != null) {
                      setState(() {
                        selectedImage = File(image.path);
                      });
                    }
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage: selectedImage != null
                        ? FileImage(selectedImage!)
                        : (user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                              ? NetworkImage(user.avatarUrl!)
                              : null),
                    child:
                        selectedImage == null &&
                            (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                        ? const Icon(Icons.camera_alt, size: 30)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: firstNameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Họ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bioController,
                  decoration: const InputDecoration(
                    labelText: 'Giới thiệu bản thân',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final updated = await _repo.updateProfile(
                    firstName: firstNameController.text.trim(),
                    lastName: lastNameController.text.trim(),
                    email: emailController.text.trim(),
                    phoneNumber: phoneController.text.trim(),
                    bio: bioController.text.trim(),
                    avatar: selectedImage,
                  );
                  if (context.mounted) {
                    // Update provider state so all listeners get refreshed
                    try {
                      context.read<AuthProvider>().setUser(updated);
                    } catch (_) {}
                    Navigator.of(context).pop();
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Cập nhật thông tin thành công'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Đã xảy ra lỗi. Vui lòng thử lại.'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}
