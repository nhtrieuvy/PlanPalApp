import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/localization/app_locale.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/presentation/pages/plans/plans_list_page.dart';
import 'package:planpal_flutter/presentation/pages/analytics/analytics_dashboard_page.dart';
import 'package:planpal_flutter/presentation/pages/notifications/notification_list_page.dart';
import 'package:planpal_flutter/presentation/pages/users/profile_page.dart';
import 'package:planpal_flutter/presentation/pages/users/group_page.dart';
import 'package:planpal_flutter/core/theme/app_theme.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/riverpod/providers.dart';
import 'package:planpal_flutter/core/services/firebase_service.dart';
import 'package:planpal_flutter/presentation/pages/home/home_page.dart';
import 'package:planpal_flutter/presentation/pages/auth/login_page.dart';
import 'package:planpal_flutter/presentation/pages/auth/register_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  // Pre-initialize SharedPreferences for synchronous access
  final prefs = await SharedPreferences.getInstance();

  // Initialize providers before runApp
  final authProvider = AuthProvider();

  runApp(
    // Riverpod ProviderScope wraps everything — overrides inject pre-init instances
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authNotifierProvider.overrideWithValue(authProvider),
      ],
      child: const PlanPalApp(),
    ),
  );
}

class PlanPalApp extends ConsumerStatefulWidget {
  const PlanPalApp({super.key});

  @override
  ConsumerState<PlanPalApp> createState() => _PlanPalAppState();
}

class _PlanPalAppState extends ConsumerState<PlanPalApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapFuture = _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final authProvider = ref.read(authNotifierProvider);
    if (authProvider.isLoggedIn) {
      unawaited(authProvider.markOnline());
    }
  }

  Future<void> _bootstrap() async {
    final authProvider = ref.read(authNotifierProvider);
    await authProvider.init();

    if (authProvider.isLoggedIn && authProvider.token != null) {
      unawaited(_initializeFirebaseOnStartup(authProvider.token!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeNotifierProvider);
    final locale = ref.watch(localeNotifierProvider);

    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        final authProvider = ref.read(authNotifierProvider);
        final isBootstrapping =
            snapshot.connectionState != ConnectionState.done;

        return MaterialApp(
          navigatorKey: _navigatorKey,
          onGenerateTitle: (context) => context.l10n.t('common.app_name'),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          locale: locale,
          supportedLocales: AppLocaleStore.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: isBootstrapping
              ? const _StartupPage()
              : (authProvider.isLoggedIn
                    ? const HomePage()
                    : const LoginPage()),
          routes: {
            '/login': (context) => const LoginPage(),
            '/register': (context) => const RegisterPage(),
            '/home': (context) => const HomePage(),
            '/group': (context) => const GroupPage(),
            '/plan': (context) => const PlansListPage(),
            '/analytics': (context) => const AnalyticsDashboardPage(),
            '/notifications': (context) => const NotificationListPage(),
            '/profile': (context) => ProfilePage(),
          },
        );
      },
    );
  }
}

class _StartupPage extends StatelessWidget {
  const _StartupPage();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.t('common.app_name'),
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.t('common.loading_session'),
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Initialize Firebase on app startup if user is logged in
Future<void> _initializeFirebaseOnStartup(String authToken) async {
  try {
    final registered = await FirebaseService.instance.registerToken(authToken);
    if (!registered) {
      final error = FirebaseService.instance.lastInitializationError;
      if (error != null && error.isNotEmpty) {
        debugPrint('Main: Firebase unavailable: $error');
      }
    }
  } catch (e) {
    debugPrint('Main: Firebase startup initialization error: $e');
  }
}
