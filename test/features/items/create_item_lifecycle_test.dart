import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/features/items/item_screens.dart';

void main() {
  testWidgets('time picker result after screen disposal is ignored', (
    tester,
  ) async {
    final showScreen = ValueNotifier<bool>(true);
    addTearDown(showScreen.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: showScreen,
          builder: (_, visible, _) =>
              visible ? const CreateItemScreen() : const SizedBox.shrink(),
        ),
      ),
    );

    await tester.tap(find.text('时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);

    showScreen.value = false;
    await tester.pump();
    expect(find.byType(CreateItemScreen), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
