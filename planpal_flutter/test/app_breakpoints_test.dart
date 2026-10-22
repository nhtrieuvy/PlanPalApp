import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/responsive/app_breakpoints.dart';

void main() {
  Future<AppWindowClass> windowClassFor(
    WidgetTester tester,
    double width,
  ) async {
    AppWindowClass? result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(
          builder: (context) {
            result = AppBreakpoints.windowClassOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return result!;
  }

  testWidgets('classifies compact, medium, and expanded widths', (
    tester,
  ) async {
    expect(await windowClassFor(tester, 599), AppWindowClass.compact);
    expect(await windowClassFor(tester, 600), AppWindowClass.medium);
    expect(await windowClassFor(tester, 1024), AppWindowClass.medium);
    expect(await windowClassFor(tester, 1025), AppWindowClass.expanded);
  });
}
