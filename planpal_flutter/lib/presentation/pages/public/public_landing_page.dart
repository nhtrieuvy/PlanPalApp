import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planpal_flutter/core/localization/app_locale.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/dtos/user_model.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/locale_notifier.dart';
import 'package:planpal_flutter/core/riverpod/theme_notifier.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/core/theme/semantic_colors.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_illustration.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_line.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/planpal_brand.dart';
import 'package:planpal_flutter/presentation/widgets/network_avatar.dart';

class PublicLandingPage extends ConsumerStatefulWidget {
  const PublicLandingPage({super.key});

  @override
  ConsumerState<PublicLandingPage> createState() => _PublicLandingPageState();
}

class _PublicLandingPageState extends ConsumerState<PublicLandingPage> {
  final _scrollController = ScrollController();
  final _featuresKey = GlobalKey();
  final _howItWorksKey = GlobalKey();
  final _useCasesKey = GlobalKey();
  final _faqKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: AppMotion.emphasized,
      curve: AppMotion.emphasizedCurve,
      alignment: .04,
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Scaffold(
      backgroundColor: semantic.backgroundPrimary,
      body: SelectionArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 72,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: semantic.backgroundPrimary.withValues(
                alpha: .96,
              ),
              surfaceTintColor: Colors.transparent,
              titleSpacing: 0,
              title: _PageWidth(
                child: _PublicNavigation(
                  onHome: () => _scrollController.animateTo(
                    0,
                    duration: AppMotion.emphasized,
                    curve: AppMotion.emphasizedCurve,
                  ),
                  onFeatures: () => _scrollTo(_featuresKey),
                  onHowItWorks: () => _scrollTo(_howItWorksKey),
                  onUseCases: () => _scrollTo(_useCasesKey),
                  onFaq: () => _scrollTo(_faqKey),
                  onToggleTheme: _toggleTheme,
                  onToggleLanguage: _toggleLanguage,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _HeroSection()),
            const SliverToBoxAdapter(child: _ProblemStorySection()),
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _howItWorksKey,
                child: const _HowItWorksSection(),
              ),
            ),
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _featuresKey,
                child: const _FeatureShowcaseSection(),
              ),
            ),
            const SliverToBoxAdapter(child: _CollaborationSection()),
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _useCasesKey,
                child: const _TravelExamplesSection(),
              ),
            ),
            const SliverToBoxAdapter(child: _ProductCarouselSection()),
            const SliverToBoxAdapter(child: _PlatformSection()),
            SliverToBoxAdapter(
              child: KeyedSubtree(key: _faqKey, child: const _FaqSection()),
            ),
            const SliverToBoxAdapter(child: _FinalCtaSection()),
            const SliverToBoxAdapter(child: _PublicFooter()),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleTheme() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await ref
        .read(themeNotifierProvider.notifier)
        .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> _toggleLanguage() async {
    final current = Localizations.localeOf(context).languageCode;
    await ref
        .read(localeNotifierProvider.notifier)
        .setLanguage(
          current == AppLanguage.vietnamese.code
              ? AppLanguage.english
              : AppLanguage.vietnamese,
        );
  }
}

class _PublicNavigation extends ConsumerWidget {
  const _PublicNavigation({
    required this.onHome,
    required this.onFeatures,
    required this.onHowItWorks,
    required this.onUseCases,
    required this.onFaq,
    required this.onToggleTheme,
    required this.onToggleLanguage,
  });

  final VoidCallback onHome;
  final VoidCallback onFeatures;
  final VoidCallback onHowItWorks;
  final VoidCallback onUseCases;
  final VoidCallback onFaq;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleLanguage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < 860;
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final locale = Localizations.localeOf(context).languageCode;
    final auth = ref.watch(authNotifierProvider);
    final user = auth.user;
    final isSignedIn = auth.isLoggedIn && user != null;
    return SizedBox(
      height: 72,
      child: Row(
        children: [
          PlanPalLogo(height: 38, onTap: onHome),
          const Spacer(),
          if (!compact) ...[
            _NavLink(label: l10n.t('public.nav.features'), onTap: onFeatures),
            _NavLink(
              label: l10n.t('public.nav.how_it_works'),
              onTap: onHowItWorks,
            ),
            _NavLink(label: l10n.t('public.nav.use_cases'), onTap: onUseCases),
            _NavLink(label: l10n.t('public.nav.faq'), onTap: onFaq),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (!compact) ...[
            IconButton(
              tooltip: l10n.t('public.nav.change_theme'),
              onPressed: onToggleTheme,
              icon: Icon(
                brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
            TextButton(
              onPressed: onToggleLanguage,
              child: Text(locale == 'vi' ? 'EN' : 'VI'),
            ),
            if (!isSignedIn) ...[
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(l10n.t('public.nav.login')),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ],
          if (isSignedIn)
            _PublicAccountMenu(user: user)
          else
            FilledButton(
              onPressed: () => context.go('/register'),
              child: Text(
                compact
                    ? l10n.t('public.nav.start_short')
                    : l10n.t('public.nav.start'),
              ),
            ),
          if (compact)
            PopupMenuButton<VoidCallback>(
              tooltip: l10n.t('public.nav.menu'),
              icon: const Icon(Icons.menu_rounded),
              onSelected: (callback) => callback(),
              itemBuilder: (_) => [
                _menuItem(l10n.t('public.nav.features'), onFeatures),
                _menuItem(l10n.t('public.nav.how_it_works'), onHowItWorks),
                _menuItem(l10n.t('public.nav.use_cases'), onUseCases),
                _menuItem(l10n.t('public.nav.faq'), onFaq),
                _menuItem(l10n.t('public.nav.change_theme'), onToggleTheme),
                _menuItem(
                  '${l10n.t('common.language')}: ${locale == 'vi' ? 'English' : 'Tiếng Việt'}',
                  onToggleLanguage,
                ),
                if (!isSignedIn)
                  _menuItem(
                    l10n.t('public.nav.login'),
                    () => context.go('/login'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  PopupMenuItem<VoidCallback> _menuItem(String label, VoidCallback callback) {
    return PopupMenuItem(value: callback, child: Text(label));
  }
}

enum _PublicAccountAction { home, profile, logout }

class _PublicAccountMenu extends ConsumerWidget {
  const _PublicAccountMenu({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final displayName = user.fullName.trim().isNotEmpty
        ? user.fullName
        : (user.username.trim().isNotEmpty ? user.username : 'PlanPal');
    final initials = user.initials.trim().isNotEmpty
        ? user.initials
        : displayName.substring(0, 1).toUpperCase();

    return Tooltip(
      message: displayName,
      child: PopupMenuButton<_PublicAccountAction>(
        tooltip: l10n.t('home.profile'),
        position: PopupMenuPosition.under,
        offset: const Offset(0, 10),
        constraints: const BoxConstraints(minWidth: 236, maxWidth: 280),
        menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        color: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: context.semanticColors.borderDefault),
        ),
        onSelected: (action) async {
          switch (action) {
            case _PublicAccountAction.home:
              context.go('/home');
              break;
            case _PublicAccountAction.profile:
              context.go('/profile');
              break;
            case _PublicAccountAction.logout:
              await ref.read(authNotifierProvider).logout();
              if (context.mounted) context.go('/');
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<_PublicAccountAction>(
            enabled: false,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.semanticColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@${user.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _PublicAccountAction.home,
            child: _AccountMenuItem(
              icon: Icons.home_outlined,
              label: l10n.t('navigation.home'),
            ),
          ),
          PopupMenuItem(
            value: _PublicAccountAction.profile,
            child: _AccountMenuItem(
              icon: Icons.person_outline_rounded,
              label: l10n.t('home.profile'),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _PublicAccountAction.logout,
            child: _AccountMenuItem(
              icon: Icons.logout_rounded,
              label: l10n.t('profile.logout'),
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: NetworkAvatar(
            imageUrl: user.avatarUrl,
            initials: initials,
            size: 40,
            showBorder: true,
            borderColor: Theme.of(context).colorScheme.outlineVariant,
            borderWidth: 1,
          ),
        ),
      ),
    );
  }
}

class _AccountMenuItem extends StatelessWidget {
  const _AccountMenuItem({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        icon,
        size: AppSize.icon,
        color: color ?? context.semanticColors.textSecondary,
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color ?? context.semanticColors.textPrimary,
          ),
        ),
      ),
    ],
  );
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: context.semanticColors.textSecondary,
    ),
    child: Text(label),
  );
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final l10n = context.l10n;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Eyebrow(label: l10n.t('public.hero.eyebrow')),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            l10n.t('public.hero.title'),
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontSize: compact ? 44 : 64,
              height: 1.03,
              letterSpacing: -2,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 590),
          child: Text(
            l10n.t('public.hero.subtitle'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: context.semanticColors.textSecondary,
              fontWeight: FontWeight.w400,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: () => context.go('/register'),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(l10n.t('public.hero.primary_cta')),
            ),
            OutlinedButton.icon(
              onPressed: () {
                final target = context
                    .findAncestorStateOfType<_PublicLandingPageState>();
                target?._scrollTo(target._howItWorksKey);
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.t('public.hero.secondary_cta')),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        _TrustLine(text: l10n.t('public.hero.trust')),
      ],
    );

    return _SectionSurface(
      child: _PageWidth(
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? AppSpacing.huge : 88,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    content,
                    const SizedBox(height: AppSpacing.huge),
                    const _HeroProductVisual(),
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 10, child: content),
                    const SizedBox(width: 56),
                    const Expanded(flex: 9, child: _HeroProductVisual()),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HeroProductVisual extends StatelessWidget {
  const _HeroProductVisual();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return AspectRatio(
      aspectRatio: 1.08,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.deepOcean,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: semantic.brandPrimary.withValues(alpha: .3),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: Image.asset(
                    'assets/brand/planpal-journey-hero.webp',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x18081A19), Color(0xA6081A19)],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 24,
                left: 24,
                right: 24,
                child: _TripHeaderCard(
                  title: context.l10n.t('public.mock.trip_title'),
                  subtitle: context.l10n.t('public.mock.trip_dates'),
                ),
              ),
              Positioned(
                left: 20,
                right: 104,
                bottom: 22,
                child: _ItineraryCard(
                  title: context.l10n.t('public.mock.next_stop'),
                  place: context.l10n.t('public.mock.place'),
                  time: context.l10n.t('public.mock.time'),
                ),
              ),
              Positioned(
                right: 18,
                top: 128,
                child: _PollBadge(label: context.l10n.t('public.mock.poll')),
              ),
              Positioned(
                left: 22,
                top: 142,
                child: _AvatarStack(
                  label: context.l10n.t('public.mock.people'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripHeaderCard extends StatelessWidget {
  const _TripHeaderCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.warmWhite,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.oceanTeal,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.flight_takeoff_rounded, color: Colors.white),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.neutral600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.more_horiz_rounded, color: AppColors.neutral600),
        ],
      ),
    ),
  );
}

class _ItineraryCard extends StatelessWidget {
  const _ItineraryCard({
    required this.title,
    required this.place,
    required this.time,
  });

  final String title;
  final String place;
  final String time;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.warmWhite,
      borderRadius: BorderRadius.circular(AppRadius.card),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const Column(
            children: [
              CircleAvatar(radius: 5, backgroundColor: AppColors.oceanTeal),
              SizedBox(height: 24, child: VerticalDivider(width: 2)),
              CircleAvatar(radius: 6, backgroundColor: AppColors.sunsetCoral),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.neutral600,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  place,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  time,
                  style: const TextStyle(
                    color: AppColors.oceanTeal,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PollBadge extends StatelessWidget {
  const _PollBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: .04,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.sunsetCoral,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.how_to_vote_outlined,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < 4; index++)
          Transform.translate(
            offset: Offset(index * -8.0, 0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: const [
                AppColors.journeyMint,
                AppColors.secondaryLight,
                AppColors.accentLight,
                AppColors.warmSand,
              ][index],
              child: Text(
                ['V', 'A', 'M', '+3'][index],
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _ProblemStorySection extends StatelessWidget {
  const _ProblemStorySection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SectionSurface(
      secondary: true,
      child: _PageWidth(
        child: _SectionPadding(
          child: Column(
            children: [
              _SectionHeading(
                eyebrow: l10n.t('public.story.eyebrow'),
                title: l10n.t('public.story.title'),
                body: l10n.t('public.story.body'),
                centered: true,
              ),
              const SizedBox(height: AppSpacing.huge),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final item in [
                    ('public.story.chat', Icons.chat_bubble_outline_rounded),
                    ('public.story.notes', Icons.note_alt_outlined),
                    ('public.story.maps', Icons.map_outlined),
                    ('public.story.sheets', Icons.table_chart_outlined),
                    ('public.story.polls', Icons.how_to_vote_outlined),
                  ])
                    _ScatteredTool(label: l10n.t(item.$1), icon: item.$2),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              const Icon(Icons.keyboard_double_arrow_down_rounded, size: 30),
              const SizedBox(height: AppSpacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.semanticColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: context.semanticColors.borderDefault,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.lg,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PlanPalMark(size: 36),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          l10n.t('public.story.answer'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScatteredTool extends StatelessWidget {
  const _ScatteredTool({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.semanticColors.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: Border.all(color: context.semanticColors.borderDefault),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: context.semanticColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    ),
  );
}

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final steps = [
      (
        l10n.t('public.how.create_title'),
        l10n.t('public.how.create_body'),
        Icons.add_location_alt_outlined,
      ),
      (
        l10n.t('public.how.invite_title'),
        l10n.t('public.how.invite_body'),
        Icons.group_add_outlined,
      ),
      (
        l10n.t('public.how.travel_title'),
        l10n.t('public.how.travel_body'),
        Icons.luggage_outlined,
      ),
    ];
    return _PageWidth(
      child: _SectionPadding(
        child: Column(
          children: [
            _SectionHeading(
              eyebrow: l10n.t('public.how.eyebrow'),
              title: l10n.t('public.how.title'),
              body: l10n.t('public.how.body'),
              centered: true,
            ),
            const SizedBox(height: AppSpacing.huge),
            if (!compact)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 100),
                child: JourneyLine(stopCount: 3, currentStop: 2),
              ),
            if (!compact) const SizedBox(height: AppSpacing.xl),
            if (compact)
              Column(
                children: [
                  for (var index = 0; index < steps.length; index++) ...[
                    _JourneyStep(
                      number: index + 1,
                      title: steps[index].$1,
                      body: steps[index].$2,
                      icon: steps[index].$3,
                      showLine: index < steps.length - 1,
                      destination: index == steps.length - 1,
                    ),
                    if (index < steps.length - 1)
                      const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < steps.length; index++)
                    Expanded(
                      child: _JourneyStep(
                        number: index + 1,
                        title: steps[index].$1,
                        body: steps[index].$2,
                        icon: steps[index].$3,
                        showLine: false,
                        destination: index == steps.length - 1,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _JourneyStep extends StatelessWidget {
  const _JourneyStep({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
    required this.showLine,
    required this.destination,
  });

  final int number;
  final String title;
  final String body;
  final IconData icon;
  final bool showLine;
  final bool destination;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (showLine)
        SizedBox(
          height: 116,
          child: Column(
            children: [
              JourneyStop(
                state: JourneyStopState.completed,
                isDestination: destination,
                icon: icon,
              ),
              const Expanded(child: VerticalDivider(width: 2)),
            ],
          ),
        )
      else
        JourneyStop(
          state: JourneyStopState.completed,
          isDestination: destination,
          icon: icon,
        ),
      const SizedBox(width: AppSpacing.md),
      Flexible(
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$number',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.semanticColors.brandPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.semanticColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _FeatureShowcaseSection extends StatelessWidget {
  const _FeatureShowcaseSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SectionSurface(
      secondary: true,
      child: _PageWidth(
        child: _SectionPadding(
          child: Column(
            children: [
              _SectionHeading(
                eyebrow: l10n.t('public.features.eyebrow'),
                title: l10n.t('public.features.title'),
                body: l10n.t('public.features.body'),
                centered: true,
              ),
              const SizedBox(height: 64),
              _FeatureRow(
                title: l10n.t('public.features.itinerary_title'),
                body: l10n.t('public.features.itinerary_body'),
                points: [
                  l10n.t('public.features.itinerary_point_1'),
                  l10n.t('public.features.itinerary_point_2'),
                  l10n.t('public.features.itinerary_point_3'),
                ],
                visual: const _TimelinePreview(),
              ),
              const SizedBox(height: 88),
              _FeatureRow(
                reversed: true,
                title: l10n.t('public.features.decisions_title'),
                body: l10n.t('public.features.decisions_body'),
                points: [
                  l10n.t('public.features.decisions_point_1'),
                  l10n.t('public.features.decisions_point_2'),
                  l10n.t('public.features.decisions_point_3'),
                ],
                visual: const _DecisionPreview(),
              ),
              const SizedBox(height: 88),
              _FeatureRow(
                title: l10n.t('public.features.progress_title'),
                body: l10n.t('public.features.progress_body'),
                points: [
                  l10n.t('public.features.progress_point_1'),
                  l10n.t('public.features.progress_point_2'),
                  l10n.t('public.features.progress_point_3'),
                ],
                visual: const _PlanningPreview(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.title,
    required this.body,
    required this.points,
    required this.visual,
    this.reversed = false,
  });

  final String title;
  final String body;
  final List<String> points;
  final Widget visual;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 820;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.md),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: context.semanticColors.textSecondary,
            height: 1.55,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: context.semanticColors.brandPrimary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(point)),
              ],
            ),
          ),
      ],
    );
    final ordered = reversed && !compact
        ? [
            Expanded(child: visual),
            const SizedBox(width: 64),
            Expanded(child: copy),
          ]
        : [
            Expanded(child: copy),
            const SizedBox(width: 64),
            Expanded(child: visual),
          ];
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          copy,
          const SizedBox(height: AppSpacing.xxl),
          visual,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: ordered,
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.child, this.dark = false});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: dark ? AppColors.deepOcean : context.semanticColors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: context.semanticColors.borderDefault),
    ),
    child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: child),
  );
}

class _TimelinePreview extends StatelessWidget {
  const _TimelinePreview();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      ('09:00', l10n.t('public.preview.breakfast'), Icons.local_cafe_outlined),
      (
        '11:30',
        l10n.t('public.preview.landmark'),
        Icons.temple_buddhist_outlined,
      ),
      ('15:00', l10n.t('public.preview.checkin'), Icons.hotel_outlined),
    ];
    return _PreviewFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('public.preview.day_two'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var index = 0; index < items.length; index++)
            _TimelineItem(
              time: items[index].$1,
              title: items[index].$2,
              icon: items[index].$3,
              last: index == items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.time,
    required this.title,
    required this.icon,
    required this.last,
  });

  final String time;
  final String title;
  final IconData icon;
  final bool last;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 72,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 54,
          child: Text(
            time,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.semanticColors.textSecondary,
            ),
          ),
        ),
        Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: last
                  ? context.semanticColors.brandAccent
                  : context.semanticColors.brandPrimary,
              child: Icon(icon, color: Colors.white, size: 17),
            ),
            if (!last)
              Expanded(
                child: VerticalDivider(
                  color: context.semanticColors.borderStrong,
                  width: 2,
                ),
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
      ],
    ),
  );
}

class _DecisionPreview extends StatelessWidget {
  const _DecisionPreview();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _PreviewFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.how_to_vote_outlined,
                color: context.semanticColors.brandPrimary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.t('public.decision.question'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _PollOption(label: 'Shinjuku', votes: 4, ratio: 1),
          _PollOption(label: 'Shibuya', votes: 3, ratio: .75),
          _PollOption(label: 'Ginza', votes: 1, ratio: .25),
          const SizedBox(height: AppSpacing.sm),
          const _AvatarStack(label: '8 votes'),
        ],
      ),
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.label,
    required this.votes,
    required this.ratio,
  });

  final String label;
  final int votes;
  final double ratio;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            Text(
              context.l10n.t(
                'public.decision.votes',
                params: {'count': '$votes'},
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(value: ratio, minHeight: 8),
        ),
      ],
    ),
  );
}

class _PlanningPreview extends StatelessWidget {
  const _PlanningPreview();

  @override
  Widget build(BuildContext context) => _PreviewFrame(
    dark: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t('public.preview.ready_title'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: AppColors.warmWhite),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.t('public.preview.ready_body'),
          style: const TextStyle(color: AppColors.darkOnSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const JourneyProgress(completedStops: 3, totalStops: 4),
        const SizedBox(height: AppSpacing.xl),
        _ProgressStat(
          label: context.l10n.t('public.preview.activities'),
          value: '8/10',
        ),
        _ProgressStat(
          label: context.l10n.t('public.preview.checklist'),
          value: '14/18',
        ),
      ],
    ),
  );
}

class _ProgressStat extends StatelessWidget {
  const _ProgressStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle_outline_rounded,
          color: AppColors.journeyMint,
          size: 18,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.warmWhite),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.journeyMint,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _CollaborationSection extends StatelessWidget {
  const _CollaborationSection();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 820;
    final l10n = context.l10n;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow(label: l10n.t('public.collab.eyebrow')),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.t('public.collab.title'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.t('public.collab.body'),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: context.semanticColors.textSecondary,
            height: 1.55,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _FeatureTag(
              label: l10n.t('public.collab.chat'),
              icon: Icons.chat_bubble_outline_rounded,
            ),
            _FeatureTag(
              label: l10n.t('public.collab.polls'),
              icon: Icons.how_to_vote_outlined,
            ),
            _FeatureTag(
              label: l10n.t('public.collab.live'),
              icon: Icons.sync_rounded,
            ),
          ],
        ),
      ],
    );
    const visual = _CollaborationVisual();
    return _PageWidth(
      child: _SectionPadding(
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  copy,
                  const SizedBox(height: AppSpacing.xxl),
                  visual,
                ],
              )
            : Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 64),
                  const Expanded(child: visual),
                ],
              ),
      ),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  const _FeatureTag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Chip(avatar: Icon(icon, size: 18), label: Text(label));
}

class _CollaborationVisual extends StatelessWidget {
  const _CollaborationVisual();

  @override
  Widget build(BuildContext context) => _PreviewFrame(
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            _MessageRow(
              initials: 'V',
              text: context.l10n.t('public.collab.message_one'),
              color: AppColors.journeyMint,
            ),
            const SizedBox(height: AppSpacing.sm),
            _MessageRow(
              initials: 'A',
              text: context.l10n.t('public.collab.message_two'),
              color: AppColors.secondaryLight,
            ),
            const SizedBox(height: AppSpacing.sm),
            _MessageRow(
              initials: 'M',
              text: context.l10n.t('public.collab.message_three'),
              color: AppColors.accentLight,
            ),
          ],
        ),
        Positioned(
          right: -12,
          bottom: -18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.sunsetCoral,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                context.l10n.t('public.collab.updated'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.initials,
    required this.text,
    required this.color,
  });

  final String initials;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: color,
        child: Text(
          initials,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.semanticColors.surfaceInteractive,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(AppRadius.card),
              bottomLeft: Radius.circular(AppRadius.card),
              bottomRight: Radius.circular(AppRadius.card),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(text),
          ),
        ),
      ),
    ],
  );
}

class _TravelExamplesSection extends StatelessWidget {
  const _TravelExamplesSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final examples = [
      (
        l10n.t('public.examples.phu_quoc'),
        l10n.t('public.examples.phu_quoc_meta'),
        Icons.beach_access_outlined,
        AppColors.horizonBlue,
      ),
      (
        l10n.t('public.examples.japan'),
        l10n.t('public.examples.japan_meta'),
        Icons.temple_buddhist_outlined,
        AppColors.sunsetCoral,
      ),
      (
        l10n.t('public.examples.da_lat'),
        l10n.t('public.examples.da_lat_meta'),
        Icons.forest_outlined,
        AppColors.oceanTeal,
      ),
      (
        l10n.t('public.examples.bangkok'),
        l10n.t('public.examples.bangkok_meta'),
        Icons.nightlife_outlined,
        AppColors.warning,
      ),
    ];
    return _SectionSurface(
      secondary: true,
      child: _PageWidth(
        child: _SectionPadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeading(
                eyebrow: l10n.t('public.examples.eyebrow'),
                title: l10n.t('public.examples.title'),
                body: l10n.t('public.examples.body'),
              ),
              const SizedBox(height: AppSpacing.xxl),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final example in examples)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.md),
                        child: _DestinationCard(
                          title: example.$1,
                          meta: example.$2,
                          icon: example.$3,
                          color: example.$4,
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
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.title,
    required this.meta,
    required this.icon,
    required this.color,
  });

  final String title;
  final String meta;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 280,
    height: 220,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.semanticColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.semanticColors.borderDefault),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _DestinationPainter(color: color)),
          ),
          Positioned(
            top: 22,
            right: 22,
            child: Icon(icon, color: color, size: 36),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  meta,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DestinationPainter extends CustomPainter {
  const _DestinationPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(-10, size.height * .42)
      ..cubicTo(
        size.width * .22,
        size.height * .68,
        size.width * .52,
        size.height * .18,
        size.width + 12,
        size.height * .42,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(size.width * .7, size.height * .31),
      7,
      Paint()..color = AppColors.sunsetCoral,
    );
  }

  @override
  bool shouldRepaint(covariant _DestinationPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ProductCarouselSection extends StatefulWidget {
  const _ProductCarouselSection();

  @override
  State<_ProductCarouselSection> createState() =>
      _ProductCarouselSectionState();
}

class _ProductCarouselSectionState extends State<_ProductCarouselSection> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final target = (_index + delta).clamp(0, 4);
    if (target == _index) return;
    _controller.animateToPage(
      target,
      duration: AppMotion.standard,
      curve: AppMotion.enter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final slides = [
      (l10n.t('public.carousel.home'), Icons.home_outlined),
      (l10n.t('public.carousel.itinerary'), Icons.route_outlined),
      (l10n.t('public.carousel.decisions'), Icons.how_to_vote_outlined),
      (l10n.t('public.carousel.chat'), Icons.chat_bubble_outline_rounded),
      (l10n.t('public.carousel.polls'), Icons.poll_outlined),
    ];
    return _PageWidth(
      child: _SectionPadding(
        child: Column(
          children: [
            _SectionHeading(
              eyebrow: l10n.t('public.carousel.eyebrow'),
              title: l10n.t('public.carousel.title'),
              body: l10n.t('public.carousel.body'),
              centered: true,
            ),
            const SizedBox(height: AppSpacing.xxl),
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                    _move(-1),
                const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                    _move(1),
              },
              child: Focus(
                child: Semantics(
                  label: l10n.t('public.carousel.a11y'),
                  value: '${_index + 1}/${slides.length}',
                  child: SizedBox(
                    height: 340,
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: slides.length,
                      onPageChanged: (value) => setState(() => _index = value),
                      itemBuilder: (_, index) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: _ProductSlide(
                          title: slides[index].$1,
                          icon: slides[index].$2,
                          index: index,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: l10n.t('public.carousel.previous'),
                  onPressed: _index == 0 ? null : () => _move(-1),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: AppSpacing.sm),
                for (var index = 0; index < slides.length; index++)
                  AnimatedContainer(
                    duration: AppMotion.quick,
                    width: index == _index ? 24 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: index == _index
                          ? context.semanticColors.brandPrimary
                          : context.semanticColors.borderStrong,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: l10n.t('public.carousel.next'),
                  onPressed: _index == slides.length - 1
                      ? null
                      : () => _move(1),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSlide extends StatelessWidget {
  const _ProductSlide({
    required this.title,
    required this.icon,
    required this.index,
  });

  final String title;
  final IconData icon;
  final int index;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.deepOcean,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.journeyMint, size: 36),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.warmWhite,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.l10n.t('public.carousel.slide_${index + 1}'),
                  style: const TextStyle(
                    color: AppColors.darkOnSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xl),
          if (MediaQuery.sizeOf(context).width > 620)
            Expanded(
              child: JourneyIllustration(
                type: index == 2 || index == 4
                    ? JourneyIllustrationType.emptyPolls
                    : index == 3
                    ? JourneyIllustrationType.emptyMessages
                    : JourneyIllustrationType.destination,
                height: 250,
              ),
            ),
        ],
      ),
    ),
  );
}

class _PlatformSection extends StatelessWidget {
  const _PlatformSection();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final l10n = context.l10n;
    final cards = [
      _PlatformCard(
        icon: Icons.desktop_windows_outlined,
        title: l10n.t('public.platform.web_title'),
        body: l10n.t('public.platform.web_body'),
        accent: context.semanticColors.brandSecondary,
      ),
      _PlatformCard(
        icon: Icons.phone_android_outlined,
        title: l10n.t('public.platform.mobile_title'),
        body: l10n.t('public.platform.mobile_body'),
        accent: context.semanticColors.brandAccent,
      ),
    ];
    return _SectionSurface(
      secondary: true,
      child: _PageWidth(
        child: _SectionPadding(
          child: Column(
            children: [
              _SectionHeading(
                eyebrow: l10n.t('public.platform.eyebrow'),
                title: l10n.t('public.platform.title'),
                body: l10n.t('public.platform.body'),
                centered: true,
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (compact)
                Column(
                  children: [
                    cards[0],
                    const SizedBox(height: AppSpacing.md),
                    cards[1],
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: cards[1]),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.semanticColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: context.semanticColors.borderDefault),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FaqSection extends StatelessWidget {
  const _FaqSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final compact = MediaQuery.sizeOf(context).width < 880;
    final questions = List.generate(
      7,
      (index) => (
        l10n.t('public.faq.q${index + 1}'),
        l10n.t('public.faq.a${index + 1}'),
      ),
    );
    final accordion = Column(
      children: [
        for (final item in questions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.semanticColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: context.semanticColors.borderDefault),
              ),
              child: ExpansionTile(
                title: Text(
                  item.$1,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$2,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.semanticColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    final help = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.deepOcean,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const JourneyIllustration(
              type: JourneyIllustrationType.onboarding,
              height: 180,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.t('public.faq.help_title'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: AppColors.warmWhite),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.t('public.faq.help_body'),
              style: const TextStyle(
                color: AppColors.darkOnSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.tonalIcon(
              onPressed: () => context.go('/register'),
              icon: const Icon(Icons.explore_outlined),
              label: Text(l10n.t('public.faq.help_cta')),
            ),
          ],
        ),
      ),
    );
    return _PageWidth(
      child: _SectionPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeading(
              eyebrow: l10n.t('public.faq.eyebrow'),
              title: l10n.t('public.faq.title'),
              body: l10n.t('public.faq.body'),
            ),
            const SizedBox(height: AppSpacing.xxl),
            if (compact)
              Column(
                children: [
                  accordion,
                  const SizedBox(height: AppSpacing.xl),
                  help,
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: accordion),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 4, child: help),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FinalCtaSection extends StatelessWidget {
  const _FinalCtaSection();

  @override
  Widget build(BuildContext context) => _PageWidth(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 96),
      child: JourneyPath(
        color: AppColors.journeyMint,
        strokeWidth: 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.deepOcean,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
            child: Column(
              children: [
                const JourneyStop(
                  state: JourneyStopState.completed,
                  isDestination: true,
                  icon: Icons.flag_outlined,
                  size: 40,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  context.l10n.t('public.cta.title'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.warmWhite,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.l10n.t('public.cta.body'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.darkOnSurfaceVariant,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                FilledButton.icon(
                  onPressed: () => context.go('/register'),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(context.l10n.t('public.cta.action')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PublicFooter extends StatelessWidget {
  const _PublicFooter();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final columns = [
      _FooterColumn(
        title: l10n.t('public.footer.product'),
        links: [
          l10n.t('public.nav.features'),
          l10n.t('public.nav.how_it_works'),
          l10n.t('public.nav.use_cases'),
        ],
      ),
      _FooterColumn(
        title: l10n.t('public.footer.resources'),
        links: [
          l10n.t('public.nav.faq'),
          l10n.t('public.footer.help'),
          l10n.t('public.footer.contact'),
        ],
      ),
      _FooterColumn(
        title: l10n.t('public.footer.project'),
        links: [
          l10n.t('public.footer.about'),
          l10n.t('public.footer.privacy'),
          l10n.t('public.footer.terms'),
        ],
      ),
    ];
    return ColoredBox(
      color: AppColors.deepOcean,
      child: _PageWidth(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FooterBrand(tagline: l10n.t('public.footer.tagline')),
                    const SizedBox(height: AppSpacing.xxl),
                    Wrap(spacing: 40, runSpacing: 32, children: columns),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _FooterBrand(
                        tagline: l10n.t('public.footer.tagline'),
                      ),
                    ),
                    for (final column in columns) Expanded(child: column),
                  ],
                ),
              const SizedBox(height: 40),
              const Divider(color: AppColors.darkOutline),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.t('public.footer.copyright'),
                      style: const TextStyle(
                        color: AppColors.darkOnSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/register'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.journeyMint,
                    ),
                    child: Text(l10n.t('public.nav.start')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterBrand extends StatelessWidget {
  const _FooterBrand({required this.tagline});

  final String tagline;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PlanPalLogo(height: 42, onDark: true),
      const SizedBox(height: AppSpacing.md),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Text(
          tagline,
          style: const TextStyle(
            color: AppColors.darkOnSurfaceVariant,
            height: 1.5,
          ),
        ),
      ),
    ],
  );
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.links});

  final String title;
  final List<String> links;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.warmWhite,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final link in links)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              link,
              style: const TextStyle(color: AppColors.darkOnSurfaceVariant),
            ),
          ),
      ],
    ),
  );
}

class _PageWidth extends StatelessWidget {
  const _PageWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1240),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
        ),
        child: child,
      ),
    ),
  );
}

class _SectionPadding extends StatelessWidget {
  const _SectionPadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      vertical: MediaQuery.sizeOf(context).width < 600 ? 64 : 96,
    ),
    child: child,
  );
}

class _SectionSurface extends StatelessWidget {
  const _SectionSurface({required this.child, this.secondary = false});

  final Widget child;
  final bool secondary;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: secondary
        ? context.semanticColors.backgroundSecondary
        : context.semanticColors.backgroundPrimary,
    child: child,
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.body,
    this.centered = false,
  });

  final String eyebrow;
  final String title;
  final String body;
  final bool centered;

  @override
  Widget build(BuildContext context) => Align(
    alignment: centered ? Alignment.center : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          _Eyebrow(label: eyebrow),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: context.semanticColors.textSecondary,
              height: 1.55,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: context.semanticColors.brandPrimary,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
    ),
  );
}

class _TrustLine extends StatelessWidget {
  const _TrustLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.check_circle_outline_rounded,
        size: 18,
        color: context.semanticColors.success,
      ),
      const SizedBox(width: AppSpacing.xs),
      Flexible(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.semanticColors.textSecondary,
          ),
        ),
      ),
    ],
  );
}
