import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/localization/app_locale.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/theme/app_theme.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/routing/app_router.dart';
import 'package:planpal_flutter/core/riverpod/providers.dart';
import 'package:planpal_flutter/core/services/firebase_service.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:planpal_flutter/core/storage/offline_storage_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Brand fonts are bundled so typography remains stable offline and in PWA.
  GoogleFonts.config.allowRuntimeFetching = false;
  // Must be configured before the first native map platform view is created.
  // Android emulators can render the default Virtual Display as a black map.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    maplibre.MapLibreMap.useHybridComposition = true;
  }

  // Pre-initialize SharedPreferences for synchronous access
  final prefs = await SharedPreferences.getInstance();
  final offlineStorage = await createOfflineStorage(prefs);

  // Initialize providers before runApp
  final authProvider = AuthProvider(offlineStorage: offlineStorage);

  runApp(
    // Riverpod ProviderScope wraps everything — overrides inject pre-init instances
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineStorageProvider.overrideWithValue(offlineStorage),
        authNotifierProvider.overrideWith((ref) => authProvider),
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
  late final Future<void> _bootstrapFuture;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapFuture = _bootstrap();
    ref.read(offlineSyncProvider).start();
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
      unawaited(ref.read(offlineSyncProvider).onAppResumed());
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

        if (isBootstrapping) {
          return MaterialApp(
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
            home: const _StartupPage(),
          );
        }

        _router ??= createAppRouter(authProvider);
        return MaterialApp.router(
          routerConfig: _router,
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
    final registered = kIsWeb
        ? await FirebaseService.instance.initialize()
        : await FirebaseService.instance.registerToken(authToken);
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
