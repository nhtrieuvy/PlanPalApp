import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/localization/app_locale.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/theme/app_theme.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/planpal_brand.dart';
import 'package:planpal_flutter/presentation/widgets/layout/app_navigation_shell.dart';

void main() {
  testWidgets('compact shell keeps the five mobile journey destinations', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 820));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Explore'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded shell exposes desktop discovery and messaging', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1280, 900));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.byType(PlanPalLogo), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp() => ProviderScope(
  child: MaterialApp(
    locale: const Locale('en'),
    theme: AppTheme.lightTheme,
    supportedLocales: AppLocaleStore.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const AppNavigationShell(
      location: '/home',
      child: ColoredBox(color: Colors.transparent),
    ),
  ),
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
