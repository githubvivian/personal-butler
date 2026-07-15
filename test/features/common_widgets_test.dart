import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/features/widgets/common_widgets.dart';

void main() {
  testWidgets('accent AppCard lays out in a vertical ListView', (tester) async {
    await tester.pumpWidget(
      _listHost(
        child: const AppCard(
          key: Key('accent-card'),
          accentColor: Colors.orange,
          child: Text('accent card'),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('accent card'), findsOneWidget);

    final stripe = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).color == Colors.orange,
    );
    expect(stripe, findsOneWidget);
    expect(tester.getSize(stripe).width, 4);
    expect(
      tester.getSize(stripe).height,
      tester.getSize(find.byKey(const Key('accent-card'))).height,
    );
  });

  testWidgets('accent AppCard grows to its child natural height', (
    tester,
  ) async {
    Future<double> pumpCard(double childHeight) async {
      await tester.pumpWidget(
        _listHost(
          child: AppCard(
            key: const Key('sized-card'),
            accentColor: Colors.blue,
            child: SizedBox(height: childHeight),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      return tester.getSize(find.byKey(const Key('sized-card'))).height;
    }

    final shortHeight = await pumpCard(24);
    final tallHeight = await pumpCard(120);

    expect(tallHeight, greaterThan(shortHeight));
    expect(tallHeight - shortHeight, closeTo(96, 0.001));
  });

  testWidgets('accent AppCard invokes onTap once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _listHost(
        child: AppCard(
          accentColor: Colors.green,
          onTap: () => taps++,
          child: const Text('tap target'),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('tap target'));
    await tester.pump();

    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppCard without an accent still lays out normally', (
    tester,
  ) async {
    await tester.pumpWidget(
      _listHost(child: const AppCard(child: Text('plain card'))),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('plain card'), findsOneWidget);
  });
}

Widget _listHost({required Widget child}) {
  return MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  );
}
