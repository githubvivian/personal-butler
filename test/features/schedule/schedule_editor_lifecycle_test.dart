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

  testWidgets(
    'conflict confirmation scrolls and closes after caller disposal',
    (tester) async {
      tester.view.physicalSize = const Size(360, 480);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final showCaller = ValueNotifier<bool>(true);
      addTearDown(showCaller.dispose);
      bool? result;
      final conflicts = List.generate(
        30,
        (index) => ScheduleEntryModel(
          id: 'conflict-$index',
          owner: 'self',
          title: '课程$index',
          weekday: 1,
          startTime: '08:00',
          endTime: '09:40',
          createdAt: DateTime(2026, 7, 19),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ValueListenableBuilder<bool>(
              valueListenable: showCaller,
              builder: (_, visible, _) => visible
                  ? Builder(
                      key: const ValueKey('conflict-launcher'),
                      builder: (launcherContext) => ElevatedButton(
                        onPressed: () async {
                          result = await showScheduleConflictConfirmation(
                            launcherContext,
                            description: '以下课程存在时间冲突：',
                            conflicts: conflicts,
                          );
                        },
                        child: const Text('打开冲突确认'),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开冲突确认'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.scrollable, isTrue);
      expect(find.textContaining('课程29'), findsOneWidget);
      expect(tester.takeException(), isNull);

      showCaller.value = false;
      await tester.pump();
      expect(find.byKey(const ValueKey('conflict-launcher')), findsNothing);
      expect(find.text('打开冲突确认'), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('schedule editor rejects invalid and reversed time ranges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
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
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '非法时间测试');
    await tester.enterText(fields.at(2), '25:99');
    await tester.enterText(fields.at(3), '01:00');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('时间格式应为 HH:mm（例如 08:00）'), findsOneWidget);
    expect(find.text('添加上课'), findsOneWidget);

    await tester.enterText(fields.at(2), '10:00');
    await tester.enterText(fields.at(3), '09:00');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('结束时间必须晚于开始时间'), findsOneWidget);
    expect(find.text('添加上课'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
