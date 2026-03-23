import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/dtos/user_model.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:getwidget/getwidget.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:planpal_flutter/core/repositories/user_repository.dart';
import 'package:planpal_flutter/presentation/pages/friends/friends_page.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/ui_states/ui_states.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  // Constants
  static const double _avatarRadius = 54.0;
  static const double _editIconSize = 20.0;
  static const EdgeInsets _pagePadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 32,
  );

  // Repo & API result
  UserRepository get _repo => ref.read(userRepositoryProvider);

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Watch auth provider for user changes via Riverpod
    final user = ref.watch(authNotifierProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('Trang cá nhân'), centerTitle: true),
      body: user == null
          ? const AppLoading(message: 'Đang tải hồ sơ')
          : SingleChildScrollView(
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
            ),
    );
  }

  // Widget builders
  Widget _buildAvatarSection(UserModel user, ColorScheme colorScheme) {
    return Stack(
      children: [
        // Avatar with placeholder and error handling
        GFAvatar(
          backgroundColor: colorScheme.primary.withAlpha(30),
          radius: _avatarRadius,
          child: ClipOval(
            child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: user.avatarUrl!,
                    width: _avatarRadius * 2,
                    height: _avatarRadius * 2,
                    fit: BoxFit.cover,
                    placeholder: (c, u) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (c, u, e) => Container(
                      color: Colors.grey[100],
                      child: Center(
                        child: Text(
                          user.initials,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      user.initials,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
          ),
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
                final user = ref.read(authNotifierProvider).user;
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
    UserModel user,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Text(
      user.fullName.isNotEmpty
          ? user.fullName
          : (user.username.isNotEmpty ? user.username : ''),
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      textAlign: TextAlign.center,
    );
  }

  List<Widget> _buildStatisticsCards(
    UserModel user,
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

    return statisticsData.asMap().entries.map((entry) {
      final index = entry.key;
      final stat = entry.value;
      final isFriendsCard = stat['label'] == 'Bạn bè';
      final cardWidget = StatCard(
        icon: stat['icon'] as IconData,
        label: stat['label'] as String,
        value: '${stat['count']}',
        color: stat['color'] as Color,
        backgroundColor: stat['containerColor'] as Color,
        onTap: isFriendsCard
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const FriendsPage()),
                );
              }
            : null,
      );

      return Column(
        children: [
          cardWidget,
          if (index < statisticsData.length - 1) const SizedBox(height: 12),
        ],
      );
    }).toList();
  }

  Widget _buildPersonalInfoCard(
    UserModel user,
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
          _buildInfoRow('Họ tên', user.fullName),
          _buildInfoRow('Email', user.email ?? ''),
          _buildInfoRow('Số điện thoại', user.phoneNumber ?? ''),
          _buildInfoRow(
            'Ngày sinh',
            user.dateOfBirth != null
                ? '${user.dateOfBirth!.day}/${user.dateOfBirth!.month}/${user.dateOfBirth!.year}'
                : 'Chưa cập nhật',
          ),
          const SizedBox(height: 8),
          _buildInfoRow('Giới thiệu', user.bio ?? ''),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return GFButton(
      onPressed: () async {
        final authProvider = ref.read(authNotifierProvider);
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
  Future<void> _showEditProfileDialog(
    BuildContext pageContext,
    UserModel user,
  ) async {
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

    final scaffoldMessenger = ScaffoldMessenger.of(pageContext);
    final pageNavigator = Navigator.of(pageContext);
    final authProvider = ref.read(authNotifierProvider);

    await showDialog(
      context: pageContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
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
                    backgroundColor: Colors.grey[200],
                    child: selectedImage != null
                        ? ClipOval(
                            child: Image.file(
                              selectedImage!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          )
                        : (user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                              ? ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: user.avatarUrl!,
                                    width: 80,
                                    height: 80,
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
                                    errorWidget: (c, u, e) =>
                                        const Icon(Icons.error),
                                  ),
                                )
                              : const Icon(Icons.camera_alt, size: 30)),
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
              onPressed: () => Navigator.of(dialogContext).pop(),
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

                  if (!mounted) return;

                  try {
                    authProvider.setUser(updated);
                  } catch (_) {}
                  // Close the dialog using the page navigator we captured
                  pageNavigator.pop();
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Cập nhật thông tin thành công'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } catch (e) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Đã xảy ra lỗi. Vui lòng thử lại.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
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
