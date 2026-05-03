import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'test_app.dart';

void main() {
  testWidgets('AppLocalizations switches between Vietnamese and English', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        Builder(
          builder: (context) => Text(context.l10n.t('notifications.title')),
        ),
      ),
    );

    expect(find.text('Notifications'), findsOneWidget);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        Builder(
          builder: (context) => Text(context.l10n.t('notifications.title')),
        ),
        locale: const Locale('vi'),
      ),
    );

    expect(find.text('Thông báo'), findsOneWidget);
  });
}
