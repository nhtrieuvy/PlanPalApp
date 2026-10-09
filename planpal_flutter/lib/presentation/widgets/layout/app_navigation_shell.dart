import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/responsive/app_breakpoints.dart';
import 'package:planpal_flutter/core/riverpod/providers.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/pages/users/group_form_page.dart';
import 'package:planpal_flutter/presentation/pages/users/group_invite_code_join_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/planpal_brand.dart';

class AppNavigationShell extends ConsumerWidget {
  const AppNavigationShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  String get _landingPath => kIsWeb ? '/' : '/welcome';

  static final _primaryDestinations = <_ShellDestination>[
    _ShellDestination(
      '/home',
      PhosphorIcons.house(),
      PhosphorIcons.house(PhosphorIconsStyle.fill),
      'navigation.home',
    ),
    _ShellDestination(
      '/plans',
      PhosphorIcons.suitcaseRolling(),
      PhosphorIcons.suitcaseRolling(PhosphorIconsStyle.fill),
      'navigation.trips',
    ),
    _ShellDestination(
      '/explore',
      PhosphorIcons.compass(),
      PhosphorIcons.compass(PhosphorIconsStyle.fill),
      'search.explore',
    ),
    _ShellDestination(
      '/groups',
      PhosphorIcons.usersThree(),
      PhosphorIcons.usersThree(PhosphorIconsStyle.fill),
      'navigation.groups',
    ),
    _ShellDestination(
      '/conversations',
      PhosphorIcons.chatsCircle(),
      PhosphorIcons.chatsCircle(PhosphorIconsStyle.fill),
      'navigation.messages',
    ),
  ];

  static final _utilityDestinations = <_ShellDestination>[
    _ShellDestination(
      '/notifications',
      PhosphorIcons.bell(),
      PhosphorIcons.bell(PhosphorIconsStyle.fill),
      'home.notifications',
    ),
    _ShellDestination(
      '/profile',
      PhosphorIcons.userCircle(),
      PhosphorIcons.userCircle(PhosphorIconsStyle.fill),
      'home.profile',
    ),
  ];

  int? get _primarySelectedIndex {
    final index = _primaryDestinations.indexWhere(_matchesLocation);
    return index < 0 ? null : index;
  }

  int? get _utilitySelectedIndex {
    final index = _utilityDestinations.indexWhere(_matchesLocation);
    return index < 0 ? null : index;
  }

  bool _matchesLocation(_ShellDestination item) {
    if (item.path == '/home') return location == '/home';
    return location == item.path || location.startsWith('${item.path}/');
  }

  int get _compactSelectedIndex {
    if (location == '/plans' || location.startsWith('/plans/')) return 1;
    if (location == '/groups' || location.startsWith('/groups/')) return 3;
    if (location == '/profile') return 4;
    return 0;
  }

  void _navigate(BuildContext context, String target) {
    if (location != target) context.go(target);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windowClass = AppBreakpoints.windowClassOf(context);
    if (windowClass == AppWindowClass.compact) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _compactSelectedIndex,
          onDestinationSelected: (index) {
            if (index == 0) _navigate(context, '/home');
            if (index == 1) _navigate(context, '/plans');
            if (index == 2) _showCreateSheet(context, ref);
            if (index == 3) _navigate(context, '/groups');
            if (index == 4) _navigate(context, '/profile');
          },
          destinations: [
            NavigationDestination(
              icon: Icon(PhosphorIcons.house()),
              selectedIcon: Icon(PhosphorIcons.house(PhosphorIconsStyle.fill)),
              label: context.l10n.t('navigation.home'),
            ),
            NavigationDestination(
              icon: Icon(PhosphorIcons.suitcaseRolling()),
              selectedIcon: Icon(
                PhosphorIcons.suitcaseRolling(PhosphorIconsStyle.fill),
              ),
              label: context.l10n.t('navigation.trips'),
            ),
            NavigationDestination(
              icon: const _CreateNavigationIcon(),
              selectedIcon: const _CreateNavigationIcon(),
              label: context.l10n.t('common.create'),
            ),
            NavigationDestination(
              icon: Icon(PhosphorIcons.usersThree()),
              selectedIcon: Icon(
                PhosphorIcons.usersThree(PhosphorIconsStyle.fill),
              ),
              label: context.l10n.t('navigation.groups'),
            ),
            NavigationDestination(
              icon: Icon(PhosphorIcons.userCircle()),
              selectedIcon: Icon(
                PhosphorIcons.userCircle(PhosphorIconsStyle.fill),
              ),
              label: context.l10n.t('navigation.me'),
            ),
          ],
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          if (windowClass == AppWindowClass.medium)
            NavigationRail(
              selectedIndex: _primarySelectedIndex,
              onDestinationSelected: (index) =>
                  _navigate(context, _primaryDestinations[index].path),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.75,
              leading: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 12),
                child: PlanPalMark(
                  size: 36,
                  onTap: () => context.go(_landingPath),
                ),
              ),
              trailing: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Column(
                  children: [
                    IconButton(
                      tooltip: context.l10n.t('common.create'),
                      onPressed: () => _showCreateSheet(context, ref),
                      icon: Icon(PhosphorIcons.plusCircle()),
                    ),
                    for (final item in _utilityDestinations)
                      IconButton(
                        tooltip: context.l10n.t(item.labelKey),
                        onPressed: () => _navigate(context, item.path),
                        icon: Icon(
                          _matchesLocation(item)
                              ? item.selectedIcon
                              : item.icon,
                        ),
                      ),
                  ],
                ),
              ),
              destinations: _primaryDestinations
                  .map(
                    (item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: Text(context.l10n.t(item.labelKey)),
                    ),
                  )
                  .toList(),
            )
          else
            _ExpandedSidebar(
              primarySelectedIndex: _primarySelectedIndex,
              utilitySelectedIndex: _utilitySelectedIndex,
              primaryDestinations: _primaryDestinations,
              utilityDestinations: _utilityDestinations,
              landingPath: _landingPath,
              onNavigate: (target) => _navigate(context, target),
              onCreate: () => _showCreateSheet(context, ref),
            ),
          VerticalDivider(width: 1, color: colorScheme.outlineVariant),
          Expanded(child: child),
        ],
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<_CreateChoice>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                context.l10n.t('common.create'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: Icon(PhosphorIcons.airplaneTilt()),
              title: Text(context.l10n.t('home.create_plan')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(sheetContext).pop(_CreateChoice.trip),
            ),
            ListTile(
              leading: Icon(PhosphorIcons.usersThree()),
              title: Text(context.l10n.t('groups.create')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(sheetContext).pop(_CreateChoice.group),
            ),
            ListTile(
              leading: Icon(PhosphorIcons.password()),
              title: Text(context.l10n.t('home.join_group')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(sheetContext).pop(_CreateChoice.join),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == _CreateChoice.trip) {
      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => const PlanFormPage()),
      );
      if (result != null) ref.invalidate(plansNotifierProvider);
      if (context.mounted && result != null) context.go('/plans');
      return;
    }
    if (choice == _CreateChoice.group) {
      final result = await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const GroupFormPage()));
      if (result != null) ref.invalidate(groupsNotifierProvider);
      if (context.mounted && result != null) context.go('/groups');
      return;
    }

    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const GroupInviteCodeJoinPage()));
    if (result != null) ref.invalidate(groupsNotifierProvider);
    if (context.mounted && result != null) context.go('/groups');
  }
}

class _CreateNavigationIcon extends StatelessWidget {
  const _CreateNavigationIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      shape: BoxShape.circle,
    ),
    child: Icon(
      PhosphorIcons.plus(),
      color: Theme.of(context).colorScheme.onPrimary,
    ),
  );
}

class _ExpandedSidebar extends StatelessWidget {
  const _ExpandedSidebar({
    required this.primarySelectedIndex,
    required this.utilitySelectedIndex,
    required this.primaryDestinations,
    required this.utilityDestinations,
    required this.landingPath,
    required this.onNavigate,
    required this.onCreate,
  });

  final int? primarySelectedIndex;
  final int? utilitySelectedIndex;
  final List<_ShellDestination> primaryDestinations;
  final List<_ShellDestination> utilityDestinations;
  final String landingPath;
  final ValueChanged<String> onNavigate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      width: 248,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PlanPalLogo(
                    height: 42,
                    onTap: () => onNavigate(landingPath),
                  ),
                ),
              ),
              for (var index = 0; index < primaryDestinations.length; index++)
                _SidebarItem(
                  item: primaryDestinations[index],
                  selected: index == primarySelectedIndex,
                  onTap: () => onNavigate(primaryDestinations[index].path),
                ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: onCreate,
                icon: Icon(PhosphorIcons.plus()),
                label: Text(context.l10n.t('common.create')),
              ),
              const Spacer(),
              Divider(color: colorScheme.outlineVariant),
              const SizedBox(height: AppSpacing.xs),
              for (var index = 0; index < utilityDestinations.length; index++)
                _SidebarItem(
                  item: utilityDestinations[index],
                  selected: index == utilitySelectedIndex,
                  onTap: () => onNavigate(utilityDestinations[index].path),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _ShellDestination item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      leading: Icon(selected ? item.selectedIcon : item.icon),
      title: Text(context.l10n.t(item.labelKey)),
      onTap: onTap,
    ),
  );
}

enum _CreateChoice { trip, group, join }

class _ShellDestination {
  const _ShellDestination(
    this.path,
    this.icon,
    this.selectedIcon,
    this.labelKey,
  );

  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
}
