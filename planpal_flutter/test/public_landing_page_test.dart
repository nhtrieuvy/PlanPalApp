import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/user_model.dart';
import 'package:planpal_flutter/core/localization/app_locale.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/theme/app_theme.dart';
import 'package:planpal_flutter/presentation/pages/public/public_landing_page.dart';

void main() {
  testWidgets('public landing renders the full desktop story', (tester) async {
    await _setViewport(tester, const Size(1280, 900));
    await tester.pumpWidget(_testApp(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Plan together.\nTravel better.'), findsOneWidget);
    expect(find.text('Start planning'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('A smoother start to the journey.'),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('What is PlanPal?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public landing keeps the compact navigation usable', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 780));
    await tester.pumpWidget(_testApp(const Locale('vi')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    expect(find.text('Cùng lên kế hoạch.\nCùng đi thật vui.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public landing shows the restored account menu', (tester) async {
    await _setViewport(tester, const Size(1280, 900));
    await tester.pumpWidget(
      _testApp(const Locale('en'), auth: _SignedInAuthProvider()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsNothing);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Test Traveler'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });
}

Widget _testApp(Locale locale, {AuthProvider? auth}) => ProviderScope(
  overrides: [
    authNotifierProvider.overrideWith((ref) => auth ?? AuthProvider()),
  ],
  child: MaterialApp(
    locale: locale,
    theme: AppTheme.lightTheme,
    supportedLocales: AppLocaleStore.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const PublicLandingPage(),
  ),
);

class _SignedInAuthProvider extends AuthProvider {
  final UserModel _signedInUser = UserModel(
    id: 'user-1',
    username: 'traveler',
    firstName: 'Test',
    lastName: 'Traveler',
    hasAvatar: false,
    isOnline: true,
    isRecentlyOnline: true,
    onlineStatus: 'online',
    plansCount: 0,
    personalPlansCount: 0,
    groupPlansCount: 0,
    groupsCount: 0,
    friendsCount: 0,
    unreadMessagesCount: 0,
    dateJoined: DateTime(2026, 1, 1),
    isActive: true,
    isStaff: false,
    fullName: 'Test Traveler',
    initials: 'TT',
  );

  @override
  UserModel? get user => _signedInUser;

  @override
  bool get isLoggedIn => true;
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
