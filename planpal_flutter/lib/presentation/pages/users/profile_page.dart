import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planpal_flutter/core/dtos/user_model.dart';
import 'package:planpal_flutter/core/dtos/plan_summary.dart';
import 'package:planpal_flutter/core/localization/app_formatters.dart';
import 'package:planpal_flutter/core/localization/app_locale.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/repositories/user_repository.dart';
import 'package:planpal_flutter/core/riverpod/providers.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/pages/friends/friends_page.dart';
import 'package:planpal_flutter/presentation/widgets/common/x_file_image.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';

import '../../../shared/ui_states/ui_states.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  static const double _avatarRadius = 54.0;
  static const double _editIconSize = 20.0;
  static const EdgeInsets _pagePadding = EdgeInsets.all(AppSpacing.lg);

  UserRepository get _repo => ref.read(userRepositoryProvider);

  Future<bool> _refreshProfile({bool showError = true}) async {
    try {
      await _repo.getProfile();
      return true;
    } catch (_) {
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.t('profile.refresh_error')),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;
    final user = ref.watch(authNotifierProvider).user;
    final recentPlans =
        ref.watch(plansNotifierProvider).valueOrNull?.items.take(3).toList() ??
        const <PlanSummary>[];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('profile.title')), centerTitle: true),
      body: user == null
          ? AppLoading(message: l10n.t('profile.loading'))
          : RefreshIndicator(
              onRefresh: () async {
                await _refreshProfile();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: _pagePadding,
                child: ResponsiveContent(
                  mediumMaxWidth: 760,
                  expandedMaxWidth: 1080,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildIdentityHero(context, user, theme, colorScheme),
                      const SizedBox(height: AppSpacing.lg),
                      _buildStatistics(context, user),
                      const SizedBox(height: AppSpacing.lg),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final journeys = _buildRecentJourneys(
                            context,
                            recentPlans,
                          );
                          final preferences = _buildPreferences(context, user);
                          if (constraints.maxWidth < 820) {
                            return Column(
                              children: [
                                journeys,
                                const SizedBox(height: AppSpacing.md),
                                preferences,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: journeys),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(flex: 2, child: preferences),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _buildLogoutButton(context),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildIdentityHero(
    BuildContext context,
    UserModel user,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final displayName = user.fullName.isNotEmpty
        ? user.fullName
        : user.username;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      child: JourneyPathBackdrop(
        color: colorScheme.onPrimary,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              _buildAvatarSection(user, colorScheme),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '@${user.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimary.withValues(alpha: .78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection(UserModel user, ColorScheme colorScheme) {
    final avatarPalette = AppColors.avatarPalette(
      user.id.isNotEmpty ? user.id : user.username,
      Theme.of(context).brightness,
    );
    return Stack(
      children: [
        CircleAvatar(
          backgroundColor: colorScheme.surfaceContainerHighest,
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
                    errorWidget: (context, url, error) =>
                        _buildAvatarFallback(user.initials, avatarPalette),
                  )
                : _buildAvatarFallback(user.initials, avatarPalette),
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

  Widget _buildAvatarFallback(String initials, AvatarPalette palette) {
    return Container(
      color: palette.background,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: palette.foreground,
          ),
        ),
      ),
    );
  }

  Widget _buildStatistics(BuildContext context, UserModel user) {
    final l10n = context.l10n;
    return JourneyMetricStrip(
      metrics: [
        JourneyMetricData(
          icon: Icons.travel_explore,
          label: l10n.t('profile.stats.plans'),
          value: '${user.plansCount}',
          emphasis: true,
        ),
        JourneyMetricData(
          icon: Icons.group,
          label: l10n.t('profile.stats.groups'),
          value: '${user.groupsCount}',
        ),
        JourneyMetricData(
          icon: Icons.people,
          label: l10n.t('profile.stats.friends'),
          value: '${user.friendsCount}',
        ),
      ],
    );
  }

  Widget _buildRecentJourneys(BuildContext context, List<PlanSummary> plans) {
    final l10n = context.l10n;
    return JourneySurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: JourneySectionHeader(
              title: l10n.t('profile.recent_journeys'),
              subtitle: l10n.t('profile.recent_journeys_hint'),
              icon: Icons.route_outlined,
              trailing: TextButton(
                onPressed: () => context.go('/plans'),
                child: Text(l10n.t('common.view_all')),
              ),
            ),
          ),
          if (plans.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.map_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.t('profile.no_recent_journeys'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (var index = 0; index < plans.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer,
                child: const Icon(Icons.near_me_outlined),
              ),
              title: Text(
                plans[index].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_planDateLabel(context, plans[index])),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/plans/${plans[index].id}'),
            ),
          ],
        ],
      ),
    );
  }

  String _planDateLabel(BuildContext context, PlanSummary plan) {
    if (plan.startDate == null) return context.l10n.t('plan.no_date');
    final start = AppFormatters.shortDate(context, plan.startDate!);
    if (plan.endDate == null) return start;
    return '$start - ${AppFormatters.shortDate(context, plan.endDate!)}';
  }

  Widget _buildPreferences(BuildContext context, UserModel user) {
    final l10n = context.l10n;
    final themeMode = ref.watch(themeNotifierProvider);
    final language = ref.watch(currentAppLanguageProvider);
    return JourneySurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              l10n.t('profile.preferences'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline_rounded),
            title: Text(l10n.t('profile.stats.friends')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FriendsPage())),
          ),
          if (user.isStaff) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: Text(l10n.t('profile.system_analytics')),
              subtitle: Text(l10n.t('profile.system_analytics_hint')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/analytics'),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: Text(l10n.t('profile.account_details')),
            subtitle: Text(l10n.t('profile.account_details_hint')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showAccountDetailsSheet(context, user),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.contrast_rounded),
            title: Text(l10n.t('profile.appearance')),
            subtitle: Text(
              themeMode == ThemeMode.dark
                  ? l10n.t('profile.theme_dark')
                  : themeMode == ThemeMode.light
                  ? l10n.t('profile.theme_light')
                  : l10n.t('profile.theme_system'),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showThemeSheet(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(l10n.t('common.language')),
            subtitle: Text(l10n.languageName(language.code)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showLanguageSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    final l10n = context.l10n;
    return OutlinedButton.icon(
      onPressed: () async {
        await ref.read(authNotifierProvider).logout();
        if (context.mounted) context.go('/login');
      },
      icon: const Icon(Icons.logout_rounded),
      label: Text(l10n.t('profile.logout')),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: AppColors.error,
        side: const BorderSide(color: AppColors.error),
      ),
    );
  }

  Future<void> _showThemeSheet(BuildContext context) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: RadioGroup<ThemeMode>(
          groupValue: ref.read(themeNotifierProvider),
          onChanged: (value) async {
            if (value == null) return;
            await ref.read(themeNotifierProvider.notifier).setThemeMode(value);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ThemeMode.values.map((mode) {
              final label = mode == ThemeMode.dark
                  ? l10n.t('profile.theme_dark')
                  : mode == ThemeMode.light
                  ? l10n.t('profile.theme_light')
                  : l10n.t('profile.theme_system');
              return RadioListTile<ThemeMode>(value: mode, title: Text(label));
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _showLanguageSheet(BuildContext context) async {
    final l10n = context.l10n;
    final current = ref.read(currentAppLanguageProvider);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: RadioGroup<AppLanguage>(
          groupValue: current,
          onChanged: (value) async {
            if (value == null) return;
            await ref.read(localeNotifierProvider.notifier).setLanguage(value);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppLanguage.values.map((language) {
              return RadioListTile<AppLanguage>(
                value: language,
                title: Text(l10n.languageName(language.code)),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _showAccountDetailsSheet(
    BuildContext pageContext,
    UserModel user,
  ) async {
    final l10n = pageContext.l10n;
    await showModalBottomSheet<void>(
      context: pageContext,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JourneySectionHeader(
              title: l10n.t('profile.account_details'),
              subtitle: l10n.t('profile.account_details_hint'),
              icon: Icons.manage_accounts_outlined,
            ),
            const SizedBox(height: AppSpacing.md),
            _buildInfoRow(l10n.t('profile.username'), user.username),
            _buildInfoRow(l10n.t('auth.email'), user.email ?? ''),
            _buildInfoRow(l10n.t('profile.phone'), user.phoneNumber ?? ''),
            _buildInfoRow(
              l10n.t('profile.birth_date'),
              user.dateOfBirth != null
                  ? AppFormatters.shortDate(pageContext, user.dateOfBirth!)
                  : l10n.t('profile.not_updated'),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                Future<void>.delayed(Duration.zero, () async {
                  if (mounted) await _showEditProfileDialog(context, user);
                });
              },
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.t('profile.edit_info')),
            ),
          ],
        ),
      ),
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
    final scaffoldMessenger = ScaffoldMessenger.of(pageContext);
    final authProvider = ref.read(authNotifierProvider);

    final updated = await showDialog<UserModel>(
      context: pageContext,
      builder: (_) => _EditProfileDialog(user: user, repository: _repo),
    );

    if (!mounted || updated == null) return;
    authProvider.setUser(updated);
    await _refreshProfile(showError: false);
    if (!mounted) return;
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(l10n.t('profile.updated_success')),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.user, required this.repository});

  final UserModel user;
  final UserRepository repository;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _bioController;
  final ImagePicker _picker = ImagePicker();

  XFile? _selectedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.user.fullName);
    _phoneController = TextEditingController(
      text: widget.user.phoneNumber ?? '',
    );
    _bioController = TextEditingController(text: widget.user.bio ?? '');
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (!mounted || image == null) return;
    setState(() => _selectedImage = image);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final updated = await widget.repository.updateProfile(
        fullName: _fullNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        bio: _bioController.text.trim(),
        avatar: _selectedImage,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('profile.updated_error')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(l10n.t('profile.edit_info')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MouseRegion(
              cursor: _isSaving
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _isSaving ? null : _pickAvatar,
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  child: _selectedImage != null
                      ? ClipOval(
                          child: XFileImage(
                            file: _selectedImage!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        )
                      : (widget.user.avatarUrl != null &&
                                widget.user.avatarUrl!.isNotEmpty
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: widget.user.avatarUrl!,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const SizedBox(
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
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fullNameController,
              enabled: !_isSaving,
              decoration: InputDecoration(
                labelText: l10n.t('profile.full_name'),
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              enabled: !_isSaving,
              decoration: InputDecoration(
                labelText: l10n.t('profile.phone'),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioController,
              enabled: !_isSaving,
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
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.t('common.cancel')),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.t('common.save')),
        ),
      ],
    );
  }
}
