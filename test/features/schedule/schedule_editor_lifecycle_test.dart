import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/features/schedule/schedule_support.dart';

void main() {
  testWidgets(
    'schedule editor keeps controllers alive through route dismissal',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);

      ScheduleEntryDraft? result;
      final settings = ScheduleSettingsModel(
        semesterStartWeek: 1,
        semesterEndWeek: 20,
        updatedAt: DateTime(2026, 7, 16),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showScheduleEntryEditor(
                    context,
                    dialogTitle: '添加上课',
                    settings: settings,
                  );
                },
                child: const Text('打开编辑器'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开编辑器'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Algorithms');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      expect(result?.title, 'Algorithms');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('schedule editor preset dropdown fits a narrow phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = ScheduleSettingsModel(
      semesterStartWeek: 1,
      semesterEndWeek: 20,
      updatedAt: DateTime(2026, 7, 16),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showScheduleEntryEditor(
                  context,
                  dialogTitle: '添加上课',
                  settings: settings,
                );
              },
              child: const Text('打开编辑器'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();

    expect(find.text('节次模板'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
