import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/planpal_brand.dart';

String authSwitchLocation(BuildContext context, String path) {
  final from = GoRouterState.of(context).uri.queryParameters['from'];
  return Uri(
    path: path,
    queryParameters: from == null || from.isEmpty ? null : {'from': from},
  ).toString();
}

class AuthJourneyShell extends StatelessWidget {
  const AuthJourneyShell({
    super.key,
    required this.isRegister,
    required this.child,
  });

  final bool isRegister;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 340);

    return Scaffold(
      backgroundColor: colors.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 960) return child;

          final formWidth = constraints.maxWidth * 0.52;
          final bannerWidth = constraints.maxWidth - formWidth;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeInOutCubic,
                left: isRegister ? 0 : bannerWidth,
                top: 0,
                bottom: 0,
                width: formWidth,
                child: child,
              ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeInOutCubic,
                left: isRegister ? formWidth : 0,
                top: 0,
                bottom: 0,
                width: bannerWidth,
                child: _JourneyBanner(isRegister: isRegister),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AuthFormViewport extends StatelessWidget {
  const AuthFormViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 960;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (compact) ...[
                    const _CompactBrand(),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          const PlanPalMark(size: 48),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t('common.app_name'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  context.l10n.t('auth.brand_tagline_short'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyBanner extends StatelessWidget {
  const _JourneyBanner({required this.isRegister});

  final bool isRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return ColoredBox(
      color: AppColors.primaryDark,
      child: JourneyPathBackdrop(
        color: Colors.white,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const PlanPalLogo(height: 58, onDark: true),
                        const SizedBox(height: AppSpacing.huge),
                        Text(
                          l10n.t('auth.journey_eyebrow').toUpperCase(),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.journeyMint,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : AppMotion.standard,
                          child: Text(
                            isRegister
                                ? l10n.t('auth.register_journey_title')
                                : l10n.t('auth.login_journey_title'),
                            key: ValueKey(isRegister),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          l10n.t('auth.brand_tagline'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white.withValues(alpha: .78),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxxl),
                        _JourneyPreview(isRegister: isRegister),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JourneyPreview extends StatelessWidget {
  const _JourneyPreview({required this.isRegister});

  final bool isRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final steps = [
      l10n.t('auth.journey_step_1'),
      l10n.t('auth.journey_step_2'),
      l10n.t('auth.journey_step_3'),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_outlined,
                color: AppColors.journeyMint,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.t('auth.journey_preview_title'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${isRegister ? '01' : '02'} / 03',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.journeyMint,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var index = 0; index < steps.length; index++)
            _JourneyPreviewStep(
              index: index,
              label: steps[index],
              isLast: index == steps.length - 1,
              isActive: index == (isRegister ? 0 : 1),
            ),
        ],
      ),
    );
  }
}

class _JourneyPreviewStep extends StatelessWidget {
  const _JourneyPreviewStep({
    required this.index,
    required this.label,
    required this.isLast,
    required this.isActive,
  });

  final int index;
  final String label;
  final bool isLast;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: isLast ? 34 : 58,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: reduceMotion ? Duration.zero : AppMotion.standard,
                  width: isActive ? 16 : 12,
                  height: isActive ? 16 : 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AppColors.sunsetCoral
                        : AppColors.journeyMint,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.journeyMint.withValues(alpha: .55),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            '${index + 1}'.padLeft(2, '0'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.journeyMint,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
