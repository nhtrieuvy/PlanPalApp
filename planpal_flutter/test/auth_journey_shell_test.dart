import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/localization/app_locale.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/routing/app_router.dart';
import 'package:planpal_flutter/core/theme/app_theme.dart';

void main() {
  testWidgets('desktop auth panels slide both ways and retain return URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthProvider();
    final router = createAppRouter(auth);
    addTearDown(router.dispose);
    router.go('/register?from=%2Fplans%2Ftrip-1');

    await tester.pumpWidget(_testApp(router, auth));
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsOneWidget);
    final registerFormX = tester.getTopLeft(find.text('Create account')).dx;
    final registerBannerX = tester
        .getTopLeft(find.text('Start somewhere worth remembering.'))
        .dx;
    expect(registerFormX, lessThan(registerBannerX));

    await tester.tap(find.textContaining('Already have an account?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 170));
    final midLoginFormX = tester.getTopLeft(find.text('Sign in to PlanPal')).dx;
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['from'],
      '/plans/trip-1',
    );
    expect(find.text('Sign in to PlanPal'), findsOneWidget);
    final loginFormX = tester.getTopLeft(find.text('Sign in to PlanPal')).dx;
    expect(midLoginFormX, greaterThan(registerFormX));
    expect(midLoginFormX, lessThan(loginFormX));
    final loginBannerX = tester
        .getTopLeft(find.text('Pick up where your journey left off.'))
        .dx;
    expect(loginFormX, greaterThan(loginBannerX));

    await tester.tap(find.textContaining('No account yet?'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/register');
    expect(find.text('Create account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact auth keeps both forms usable without a desktop banner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthProvider();
    final router = createAppRouter(auth);
    addTearDown(router.dispose);
    router.go('/login');

    await tester.pumpWidget(_testApp(router, auth));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to PlanPal'), findsOneWidget);

    await tester.tap(find.textContaining('No account yet?'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Tell us about you'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in [const Size(960, 600), const Size(320, 640)]) {
    testWidgets('registration stays scrollable at ${viewport.width}px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = AuthProvider();
      final router = createAppRouter(auth);
      addTearDown(router.dispose);
      router.go('/register');

      await tester.pumpWidget(_testApp(router, auth));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _testApp(GoRouter router, AuthProvider auth) => ProviderScope(
  overrides: [authNotifierProvider.overrideWith((ref) => auth)],
  child: MaterialApp.router(
    routerConfig: router,
    locale: const Locale('en'),
    theme: AppTheme.lightTheme,
    supportedLocales: AppLocaleStore.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  ),
);
