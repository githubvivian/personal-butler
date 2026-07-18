import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/features/auth/startup_screen.dart';

void main() {
  testWidgets('startup states do not overflow in a short large-text viewport', (
    tester,
  ) async {
    await tester.pumpWidget(_narrowLargeTextHost(const StartupLoadingScreen()));
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _narrowLargeTextHost(StartupErrorScreen(onRetry: () async {})),
    );
    await tester.pump();

    expect(find.byKey(const Key('startup-retry-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _narrowLargeTextHost(Widget child) {
  return MaterialApp(
    home: SizedBox(
      width: 320,
      height: 320,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 320),
          textScaler: TextScaler.linear(2),
        ),
        child: child,
      ),
    ),
  );
}
