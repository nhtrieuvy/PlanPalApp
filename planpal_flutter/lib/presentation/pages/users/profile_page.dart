import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:getwidget/getwidget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planpal_flutter/core/dtos/user_model.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/repositories/user_repository.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/presentation/pages/friends/friends_page.dart';

import '../../../shared/ui_states/ui_states.dart';
import '../../../shared/widgets/widgets.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  static const double _avatarRadius = 54.0;
  static const double _editIconSize = 20.0;
  static const EdgeInsets _pagePadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 32,
  );

  UserRepository get _repo => ref.read(userRepositoryProvider);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;
    final user = ref.watch(authNotifierProvider).user;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('profile.title')), centerTitle: true),
      body: user == null
          ? AppLoading(message: l10n.t('profile.loading'))
          : SingleChildScrollView(
              padding: _pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Center(child: _buildAvatarSection(user, colorScheme)),
                  const SizedBox(height: 24),
                  ..._buildStatisticsCards(context, user, colorScheme),
                  const SizedBox(height: 24),
                  _buildUserNameSection(user, theme, colorScheme),
                  const SizedBox(height: 24),
                  _buildPersonalInfoCard(context, user, theme, colorScheme),
                  const SizedBox(height: 32),
                  _buildLogoutButton(context),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatarSection(UserModel user, ColorScheme colorScheme) {
    return Stack(
      children: [
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
                    placeholder: (context, url) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => _buildAvatarFallback(
                      user.initials,
                      colorScheme,
                    ),
                  )
                : _buildAvatarFallback(user.initials, colorScheme),
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
                final currentUser = ref.read(authNotifierProvider).user;
                if (currentUser != null) {
                  await _showEditProfileDialog(context, currentUser);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
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

  Widget _buildAvatarFallback(String initials, ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
      ),
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
    BuildContext context,
    UserModel user,
    ColorScheme colorScheme,
  ) {
    final l10n = context.l10n;
    final statisticsData = [
      (
        icon: Icons.travel_explore,
        label: l10n.t('profile.stats.plans'),
        count: user.plansCount,
        color: colorScheme.primary,
        background: colorScheme.primaryContainer,
      ),
      (
        icon: Icons.group,
        label: l10n.t('profile.stats.groups'),
        count: user.groupsCount,
        color: colorScheme.secondary,
        background: colorScheme.secondaryContainer,
      ),
      (
        icon: Icons.people,
        label: l10n.t('profile.stats.friends'),
        count: user.friendsCount,
        color: colorScheme.tertiary,
        background: colorScheme.tertiaryContainer,
      ),
    ];

    return statisticsData.asMap().entries.map((entry) {
      final index = entry.key;
      final stat = entry.value;
      final isFriendsCard = stat.label == l10n.t('profile.stats.friends');
      final card = StatCard(
        icon: stat.icon,
        label: stat.label,
        value: '${stat.count}',
        color: stat.color,
        backgroundColor: stat.background,
        onTap: isFriendsCard
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FriendsPage()),
                );
              }
            : null,
      );

      return Column(
        children: [
          card,
          if (index < statisticsData.length - 1) const SizedBox(height: 12),
        ],
      );
    }).toList();
  }

  Widget _buildPersonalInfoCard(
    BuildContext context,
    UserModel user,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final l10n = context.l10n;
    return GFCard(
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('profile.personal_info'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(l10n.t('profile.username'), user.username),
          _buildInfoRow(l10n.t('profile.full_name'), user.fullName),
          _buildInfoRow(l10n.t('auth.email'), user.email ?? ''),
          _buildInfoRow(l10n.t('profile.phone'), user.phoneNumber ?? ''),
          _buildInfoRow(
            l10n.t('profile.birth_date'),
            user.dateOfBirth != null
                ? AppFormatters.shortDate(context, user.dateOfBirth!)
                : l10n.t('profile.not_updated'),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(l10n.t('profile.bio'), user.bio ?? ''),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    final l10n = context.l10n;
    return GFButton(
      onPressed: () async {
        await ref.read(authNotifierProvider).logout();
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      },
      text: l10n.t('profile.logout'),
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

  Future<void> _showEditProfileDialog(
    BuildContext pageContext,
    UserModel user,
  ) async {
    final l10n = pageContext.l10n;
    final firstNameController = TextEditingController(text: user.firstName);
    final lastNameController = TextEditingController(text: user.lastName);
    final emailController = TextEditingController(text: user.email ?? '');
    final phoneController = TextEditingController(text: user.phoneNumber ?? '');
    final bioController = TextEditingController(text: user.bio ?? '');

    File? selectedImage;
    final picker = ImagePicker();
    final scaffoldMessenger = ScaffoldMessenger.of(pageContext);
    final pageNavigator = Navigator.of(pageContext);
    final authProvider = ref.read(authNotifierProvider);

    await showDialog(
      context: pageContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.t('profile.edit_info')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final image = await picker.pickImage(
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
                    backgroundColor:
                        Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
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
                                    placeholder: (context, url) =>
                                        const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                    errorWidget: (context, url, error) =>
                                        const Icon(Icons.error),
                                  ),
                                )
                              : const Icon(Icons.camera_alt, size: 30)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: l10n.t('auth.email'),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: l10n.t('profile.phone'),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bioController,
                  decoration: InputDecoration(
                    labelText: l10n.t('profile.bio_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.t('common.cancel')),
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
                  authProvider.setUser(updated);
                  pageNavigator.pop();
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.t('profile.updated_success')),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } catch (_) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.t('profile.updated_error')),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Text(l10n.t('common.save')),
            ),
          ],
        ),
      ),
    );
  }
}
