import 'package:flutter/material.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_page.dart';
import 'package:planpal_flutter/presentation/pages/users/profile_page.dart';
import 'package:planpal_flutter/presentation/pages/users/group_page.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/theme/app_theme.dart';
import 'package:planpal_flutter/core/providers/theme_provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/providers/conversation_provider.dart';
import 'package:planpal_flutter/core/services/firebase_service.dart';
import 'package:planpal_flutter/presentation/pages/home/home_page.dart';
import 'package:planpal_flutter/presentation/pages/auth/login_page.dart';
import 'package:planpal_flutter/presentation/pages/auth/register_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  // Initialize providers before runApp
  final themeProvider = ThemeProvider();
  await themeProvider.init();
  final authProvider = AuthProvider();
  await authProvider.init();

  // Initialize Firebase if user is already logged in
  if (authProvider.isLoggedIn) {
    await _initializeFirebaseOnStartup(authProvider.token!);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProxyProvider<AuthProvider, ConversationProvider>(
          create: (context) => ConversationProvider(null),
          update: (context, auth, previous) => ConversationProvider(auth.token),
        ),
      ],
      child: const PlanPalApp(),
    ),
  );
}

class PlanPalApp extends StatelessWidget {
  const PlanPalApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Consume the providers that were initialized in main()
    return Consumer2<ThemeProvider, AuthProvider>(
      builder: (context, themeProvider, authProvider, child) {
        return MaterialApp(
          title: 'PlanPal',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          initialRoute: authProvider.isLoggedIn ? '/home' : '/login',
          routes: {
            '/login': (context) => const LoginPage(),
            '/register': (context) => const RegisterPage(),
            '/home': (context) => const HomePage(),
            '/group': (context) => const GroupPage(),
            '/plan': (context) => const PlanPage(),
            '/profile': (context) => ProfilePage(),
          },
        );
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
