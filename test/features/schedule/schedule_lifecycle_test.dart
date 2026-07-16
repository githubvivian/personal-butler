import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/schedule_repository.dart';
import 'package:personal_butler/features/schedule/my_schedule_screen.dart';
import 'package:personal_butler/features/settings/schedule_settings_screen.dart';

const _failureMessage = '数据加载失败，请重试';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets('MyScheduleScreen exposes retry after an initial load failure', (
    tester,
  ) async {
    final repository = _ScriptedScheduleRepository()
      ..entryResults.add(const _Failure())
      ..entryResults.add(Future.value([_entry('recovered-course')]))
      ..settingsResults.add(Future.value(_settings()));

    await tester.pumpWidget(
      MaterialApp(home: MyScheduleScreen(scheduleRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('recovered-course'), findsOneWidget);
    expect(find.text(_failureMessage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MyScheduleScreen ignores a late load from an old repository', (
    tester,
  ) async {
    final oldEntries = Completer<List<ScheduleEntryModel>>();
    final oldSettings = Completer<ScheduleSettingsModel>();
    final oldRepository = _ScriptedScheduleRepository()
      ..entryResults.add(oldEntries.future)
      ..settingsResults.add(oldSettings.future);
    final newRepository = _ScriptedScheduleRepository()
      ..entryResults.add(Future.value([_entry('new-course')]))
      ..settingsResults.add(Future.value(_settings()));

    await tester.pumpWidget(
      MaterialApp(home: MyScheduleScreen(scheduleRepository: oldRepository)),
    );
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(home: MyScheduleScreen(scheduleRepository: newRepository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('new-course'), findsOneWidget);

    oldEntries.complete([_entry('old-course')]);
    oldSettings.complete(_settings());
    await tester.pumpAndSettle();

    expect(find.text('new-course'), findsOneWidget);
    expect(find.text('old-course'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MyScheduleScreen ignores a delayed result after disposal', (
    tester,
  ) async {
    final entries = Completer<List<ScheduleEntryModel>>();
    final repository = _ScriptedScheduleRepository()
      ..entryResults.add(entries.future)
      ..settingsResults.add(Future.value(_settings()));

    await tester.pumpWidget(
      MaterialApp(home: MyScheduleScreen(scheduleRepository: repository)),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    entries.complete([_entry('disposed-course')]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ScheduleSettingsScreen exposes retry after an initial load failure',
    (tester) async {
      final repository = _ScriptedScheduleRepository()
        ..settingsResults.add(const _Failure())
        ..settingsResults.add(
          Future.value(_settings(startWeek: 2, endWeek: 12)),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleSettingsScreen(scheduleRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_failureMessage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('共 11 周'), findsOneWidget);
      expect(find.text(_failureMessage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ScheduleSettingsScreen ignores a late load from an old repository',
    (tester) async {
      final oldSettings = Completer<ScheduleSettingsModel>();
      final oldRepository = _ScriptedScheduleRepository()
        ..settingsResults.add(oldSettings.future);
      final newRepository = _ScriptedScheduleRepository()
        ..settingsResults.add(
          Future.value(_settings(startWeek: 4, endWeek: 8)),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleSettingsScreen(scheduleRepository: oldRepository),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleSettingsScreen(scheduleRepository: newRepository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('共 5 周'), findsOneWidget);

      oldSettings.complete(_settings(startWeek: 1, endWeek: 20));
      await tester.pumpAndSettle();

      expect(find.text('共 5 周'), findsOneWidget);
      expect(find.text('共 20 周'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ScheduleSettingsScreen ignores a delayed load after disposal', (
    tester,
  ) async {
    final settings = Completer<ScheduleSettingsModel>();
    final repository = _ScriptedScheduleRepository()
      ..settingsResults.add(settings.future);

    await tester.pumpWidget(
      MaterialApp(home: ScheduleSettingsScreen(scheduleRepository: repository)),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    settings.complete(_settings());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('ScheduleSettingsScreen restores save controls after failure', (
    tester,
  ) async {
    final repository = _ScriptedScheduleRepository()
      ..settingsResults.add(Future.value(_settings()))
      ..saveError = StateError('private schedule storage marker');

    await tester.pumpWidget(
      MaterialApp(home: ScheduleSettingsScreen(scheduleRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();

    expect(find.text('保存设置'), findsOneWidget);
    expect(find.text('保存中...'), findsNothing);
    expect(find.text('保存课表设置失败，请重试'), findsOneWidget);
    expect(
      find.textContaining('private schedule storage marker'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ScheduleSettingsScreen serializes rapid save taps', (
    tester,
  ) async {
    final save = Completer<void>();
    final repository = _ScriptedScheduleRepository()
      ..settingsResults.add(Future.value(_settings()))
      ..saveResult = save.future;

    await tester.pumpWidget(
      MaterialApp(home: ScheduleSettingsScreen(scheduleRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存设置'));
    await tester.tap(find.text('保存设置'));
    await tester.pump();

    expect(repository.saveCalls, 1);
    expect(find.text('保存中...'), findsOneWidget);

    save.complete();
    await tester.pumpAndSettle();

    expect(find.text('保存设置'), findsOneWidget);
    expect(repository.saveCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ScheduleSettingsScreen ignores an old save after repository rebind',
    (tester) async {
      final oldSave = Completer<void>();
      final oldRepository = _ScriptedScheduleRepository()
        ..settingsResults.add(Future.value(_settings()))
        ..saveResult = oldSave.future;
      final newRepository = _ScriptedScheduleRepository()
        ..settingsResults.add(
          Future.value(_settings(startWeek: 4, endWeek: 8)),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleSettingsScreen(scheduleRepository: oldRepository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置'));
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleSettingsScreen(scheduleRepository: newRepository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('共 5 周'), findsOneWidget);

      oldSave.complete();
      await tester.pumpAndSettle();

      expect(find.text('共 5 周'), findsOneWidget);
      expect(find.text('课表设置已保存'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ScheduleSettingsScreen ignores a date picker result after repository rebind',
    (tester) async {
      final oldRepository = _ScriptedScheduleRepository()
        ..settingsResults.add(
          Future.value(_settings(semesterStartDate: DateTime(2026, 1, 1))),
        );
      final newRepository = _ScriptedScheduleRepository()
        ..settingsResults.add(Future.value(_settings()));
      var repository = oldRepository;
      late void Function(void Function()) rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ScheduleSettingsScreen(scheduleRepository: repository);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);

      rebuild(() => repository = newRepository);
      await tester.pumpAndSettle();
      final pickerContext = tester.element(find.byType(CalendarDatePicker));
      Navigator.of(pickerContext).pop(DateTime(2026, 2, 2));
      await tester.pumpAndSettle();

      expect(find.text('未设置，课表页仍可手动切换周次'), findsOneWidget);
      expect(find.textContaining('2026年2月2日'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Failure {
  const _Failure();
}

class _ScriptedScheduleRepository extends ScheduleRepository {
  final entryResults = <Object>[];
  final settingsResults = <Object>[];
  Object? saveError;
  Future<void>? saveResult;
  int saveCalls = 0;

  @override
  Future<List<ScheduleEntryModel>> getByOwner(String owner) {
    return _next(entryResults);
  }

  @override
  Future<ScheduleSettingsModel> getSettings() {
    return _next(settingsResults);
  }

  @override
  Future<void> saveSettings(ScheduleSettingsModel settings) async {
    saveCalls++;
    final result = saveResult;
    if (result != null) await result;
    final error = saveError;
    if (error != null) throw error;
  }
}

Future<T> _next<T>(List<Object> values) {
  final value = values.removeAt(0);
  if (value is _Failure) {
    return Future<T>.error(StateError('private schedule storage marker'));
  }
  return value as Future<T>;
}

ScheduleSettingsModel _settings({
  int startWeek = 1,
  int endWeek = 20,
  DateTime? semesterStartDate,
}) {
  return ScheduleSettingsModel(
    semesterStartWeek: startWeek,
    semesterEndWeek: endWeek,
    semesterStartDate: semesterStartDate,
    updatedAt: DateTime(2026, 7, 16),
  );
}

ScheduleEntryModel _entry(String title) {
  return ScheduleEntryModel(
    id: title,
    owner: 'self',
    title: title,
    weekday: 1,
    startTime: '08:00',
    endTime: '09:40',
    createdAt: DateTime(2026, 7, 16),
  );
}
