import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/presentation/pages/analytics/analytics_dashboard_page.dart'
    deferred as analytics_page;
import 'package:planpal_flutter/presentation/pages/auth/login_page.dart';
import 'package:planpal_flutter/presentation/pages/auth/register_page.dart';
import 'package:planpal_flutter/presentation/pages/auth/auth_journey_shell.dart';
import 'package:planpal_flutter/presentation/pages/chat/conversation_list_page.dart'
    deferred as conversations_page;
import 'package:planpal_flutter/presentation/pages/chat/conversation_route_page.dart'
    deferred as conversation_page;
import 'package:planpal_flutter/presentation/pages/experience/global_search_page.dart'
    deferred as explore_page;
import 'package:planpal_flutter/presentation/pages/home/home_page.dart'
    deferred as home_page;
import 'package:planpal_flutter/presentation/pages/friends/friends_page.dart'
    deferred as friends_page;
import 'package:planpal_flutter/presentation/pages/friends/publication_preview_page.dart'
    deferred as publication_page;
import 'package:planpal_flutter/presentation/pages/notifications/notification_list_page.dart'
    deferred as notifications_page;
import 'package:planpal_flutter/presentation/pages/plans/plans_list_page.dart'
    deferred as plans_page;
import 'package:planpal_flutter/presentation/pages/public/public_landing_page.dart';
import 'package:planpal_flutter/presentation/pages/users/group_details_page.dart'
    deferred as group_details_page;
import 'package:planpal_flutter/presentation/pages/users/group_page.dart'
    deferred as groups_page;
import 'package:planpal_flutter/presentation/pages/users/plan_details_page.dart'
    deferred as plan_details_page;
import 'package:planpal_flutter/presentation/pages/users/profile_page.dart'
    deferred as profile_page;
import 'package:planpal_flutter/presentation/widgets/layout/app_navigation_shell.dart';

GoRouter createAppRouter(AuthProvider auth) {
  return GoRouter(
    refreshListenable: auth,
    redirect: (context, state) {
      final isRootLandingRoute = state.matchedLocation == '/';
      final isLandingRoute =
          isRootLandingRoute || state.matchedLocation == '/welcome';
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      final isPublicRoute = isLandingRoute || isAuthRoute;

      // Native apps retain the established app-first entry flow. The browser
      // owns the public marketing homepage at `/`.
      if (!kIsWeb && isRootLandingRoute) {
        return auth.isLoggedIn ? '/home' : '/login';
      }

      if (!auth.isLoggedIn && !isPublicRoute) {
        final intended = Uri.encodeComponent(state.uri.toString());
        return '/login?from=$intended';
      }

      if (auth.isLoggedIn && state.matchedLocation == '/login') {
        final intended = state.uri.queryParameters['from'];
        return intended == null || intended.isEmpty ? '/home' : intended;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PublicLandingPage()),
      GoRoute(path: '/welcome', builder: (_, _) => const PublicLandingPage()),
      ShellRoute(
        builder: (context, state, child) => AuthJourneyShell(
          isRegister: state.uri.path == '/register',
          child: child,
        ),
        routes: [
          GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
          GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppNavigationShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => _DeferredRoutePage(
              loadLibrary: home_page.loadLibrary,
              builder: () => home_page.HomePage(),
            ),
          ),
          GoRoute(path: '/group', redirect: (_, _) => '/groups'),
          GoRoute(
            path: '/groups',
            builder: (_, _) => _DeferredRoutePage(
              loadLibrary: groups_page.loadLibrary,
              builder: () => groups_page.GroupPage(),
            ),
          ),
          GoRoute(
            path: '/friends',
            builder: (_, _) => _DeferredRoutePage(
              loadLibrary: friends_page.loadLibrary,
              builder: () => friends_page.FriendsPage(),
            ),
          ),
          GoRoute(
            path: '/journeys/:id',
            builder: (_, state) => _DeferredRoutePage(
              loadLibrary: publication_page.loadLibrary,
              builder: () => publication_page.PublicationPreviewPage(
                id: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/groups/:id',
            builder: (_, state) => _DeferredRoutePage(
              loadLibrary: group_details_page.loadLibrary,
              builder: () => group_details_page.GroupDetailsPage(
                id: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(path: '/plan', redirect: (_, _) => '/plans'),
          GoRoute(
            path: '/plans',
            builder: (_, _) => _DeferredRoutePage(
              loadLibrary: plans_page.loadLibrary,
              builder: () => plans_page.PlansListPage(),
            ),
          ),
          GoRoute(
            path: '/explore',
            builder: (_, _) => _DeferredRoutePage(
              loadLibrary: explore_page.loadLibrary,
              builder: () => explore_page.GlobalSearchPage(),
            ),
          ),
          GoRoute(
            path: '/plans/:id',
            builder: (_, state) => _DeferredRoutePage(
              loadLibrary: plan_details_page.loadLibrary,
              builder: () => plan_details_page.PlanDetailsPage(
                id: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/conversations',
            builder: (_, _) => _DeferredRoutePage(
              loadLibrary: conversations_page.loadLibrary,
              builder: () => conversations_page.ConversationListPage(),
            ),
          ),
          GoRoute(
            path: '/conversations/:id',
            builder: (_, state) => _DeferredRoutePage(
              loadLibrary: conversation_page.loadLibrary,
              builder: () => conversation_page.ConversationRoutePage(
                conversationId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/analytics',
            builder: (_, _) => _DeferredRoutePage(
              loadLibrary: analytics_page.loadLibrary,
              builder: () => analytics_page.AnalyticsDashboardPage(),
            ),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, _) => _DeferredRoutePage(
              loadLibrary: notifications_page.loadLibrary,
              builder: () => notifications_page.NotificationListPage(),
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => _DeferredRoutePage(
              loadLibrary: profile_page.loadLibrary,
              builder: () => profile_page.ProfilePage(),
            ),
          ),
        ],
      ),
    ],
  );
}

class _DeferredRoutePage extends StatefulWidget {
  const _DeferredRoutePage({required this.loadLibrary, required this.builder});

  final Future<void> Function() loadLibrary;
  final Widget Function() builder;

  @override
  State<_DeferredRoutePage> createState() => _DeferredRoutePageState();
}

class _DeferredRoutePageState extends State<_DeferredRoutePage> {
  late Future<void> _loading = widget.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.builder();
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: FilledButton.icon(
                onPressed: () => setState(() {
                  _loading = widget.loadLibrary();
                }),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.t('common.retry')),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
