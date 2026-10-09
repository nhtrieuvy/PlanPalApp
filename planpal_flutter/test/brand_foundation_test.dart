import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/theme/app_theme.dart';
import 'package:planpal_flutter/core/theme/semantic_colors.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_line.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/planpal_brand.dart';

void main() {
  test('light and dark themes expose semantic color tokens', () {
    final light = AppTheme.lightTheme.extension<PlanPalSemanticColors>();
    final dark = AppTheme.darkTheme.extension<PlanPalSemanticColors>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(
      _contrast(light!.textPrimary, light.backgroundPrimary),
      greaterThan(7),
    );
    expect(
      _contrast(dark!.textPrimary, dark.backgroundPrimary),
      greaterThan(7),
    );
    expect(light.brandAccent, isNot(light.brandPrimary));
  });

  testWidgets('route-P logo remains renderable at compact size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Center(child: PlanPalLogo(height: 24))),
      ),
    );

    expect(find.byType(PlanPalMark), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('journey progress supports a fully completed route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SizedBox(
            width: 240,
            child: JourneyProgress(completedStops: 4, totalStops: 4),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(JourneyStop), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}

double _contrast(Color first, Color second) {
  final light = first.computeLuminance();
  final dark = second.computeLuminance();
  final lighter = light > dark ? light : dark;
  final darker = light > dark ? dark : light;
  return (lighter + 0.05) / (darker + 0.05);
}
