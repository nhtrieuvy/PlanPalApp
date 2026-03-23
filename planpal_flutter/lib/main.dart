import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/presentation/pages/plans/plans_list_page.dart';
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
  await authProvider.init();

  // Initialize Firebase if user is already logged in
  if (authProvider.isLoggedIn) {
    await _initializeFirebaseOnStartup(authProvider.token!);
  }

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

class PlanPalApp extends ConsumerWidget {
  const PlanPalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeNotifierProvider);
    final authProvider = ref.watch(authNotifierProvider);
    return MaterialApp(
      title: 'PlanPal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      initialRoute: authProvider.isLoggedIn ? '/home' : '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/home': (context) => const HomePage(),
        '/group': (context) => const GroupPage(),
        '/plan': (context) => const PlansListPage(),
        '/profile': (context) => ProfilePage(),
      },
    );
  }
}

/// Initialize Firebase on app startup if user is logged in
Future<void> _initializeFirebaseOnStartup(String authToken) async {
  try {
    debugPrint('Main: Initializing Firebase on app startup...');

    final initialized = await FirebaseService.instance.initialize();
    if (initialized) {
      // Register token in background - don't block app startup
      FirebaseService.instance
          .registerToken(authToken)
          .then((registered) {
            debugPrint(
              'Main: FCM token registration ${registered ? 'succeeded' : 'failed'}',
            );
          })
          .catchError((e) {
            debugPrint('Main: FCM token registration error: $e');
          });
    }
  } catch (e) {
    debugPrint('Main: Firebase startup initialization error: $e');
  }
}
