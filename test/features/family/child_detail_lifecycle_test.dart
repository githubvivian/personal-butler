import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/repositories/schedule_repository.dart';
import 'package:personal_butler/features/family/child_detail_screen.dart';

const _failureMessage = '数据加载失败，请重试';

void main() {
  testWidgets('ChildDetailScreen exposes retry after an initial load failure', (
    tester,
  ) async {
    _useWideView(tester);
    final schedules = _ScriptedScheduleRepository()
      ..entryResults.add(const _Failure())
      ..entryResults.add(Future.value([_course('recovered-course')]))
      ..settingsResults.add(Future.value(_settings()));
    final items = _ScriptedItemRepository()
      ..familyResults.add(Future.value([_event('recovered-event')]));

    await tester.pumpWidget(
      MaterialApp(
        home: ChildDetailScreen(
          ownerId: 'beibei',
          scheduleRepository: schedules,
          itemRepository: items,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('private family storage marker'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('recovered-course'), findsOneWidget);
    await tester.tap(find.text('活动'));
    await tester.pumpAndSettle();
    expect(find.text('recovered-event'), findsOneWidget);
    expect(find.text(_failureMessage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ChildDetailScreen ignores a late load after repository-only rebind',
    (tester) async {
      _useWideView(tester);
      final oldEntries = Completer<List<ScheduleEntryModel>>();
      final oldSettings = Completer<ScheduleSettingsModel>();
      final oldEvents = Completer<List<ItemModel>>();
      final oldSchedules = _ScriptedScheduleRepository()
        ..entryResults.add(oldEntries.future)
        ..settingsResults.add(oldSettings.future);
      final oldItems = _ScriptedItemRepository()
        ..familyResults.add(oldEvents.future);
      final newSchedules = _ScriptedScheduleRepository()
        ..entryResults.add(Future.value([_course('rebound-course')]))
        ..settingsResults.add(Future.value(_settings()));
      final newItems = _ScriptedItemRepository()
        ..familyResults.add(Future.value([_event('rebound-event')]));

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDetailScreen(
            ownerId: 'beibei',
            scheduleRepository: oldSchedules,
            itemRepository: oldItems,
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          home: ChildDetailScreen(
            ownerId: 'beibei',
            scheduleRepository: newSchedules,
            itemRepository: newItems,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('rebound-course'), findsOneWidget);

      oldEntries.complete([_course('stale-repository-course')]);
      oldSettings.complete(_settings());
      oldEvents.complete([_event('stale-repository-event')]);
      await tester.pumpAndSettle();

      expect(find.text('rebound-course'), findsOneWidget);
      expect(find.text('stale-repository-course'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ChildDetailScreen ignores a late load for an old owner', (
    tester,
  ) async {
    _useWideView(tester);
    final oldEntries = Completer<List<ScheduleEntryModel>>();
    final oldSettings = Completer<ScheduleSettingsModel>();
    final oldEvents = Completer<List<ItemModel>>();
    final oldSchedules = _ScriptedScheduleRepository()
      ..entryResults.add(oldEntries.future)
      ..settingsResults.add(oldSettings.future);
    final oldItems = _ScriptedItemRepository()
      ..familyResults.add(oldEvents.future);
    final newSchedules = _ScriptedScheduleRepository()
      ..entryResults.add(Future.value([_course('new-owner-course')]))
      ..settingsResults.add(Future.value(_settings()));
    final newItems = _ScriptedItemRepository()
      ..familyResults.add(Future.value([_event('new-owner-event')]));

    await tester.pumpWidget(
      MaterialApp(
        home: ChildDetailScreen(
          ownerId: 'beibei',
          scheduleRepository: oldSchedules,
          itemRepository: oldItems,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ChildDetailScreen(
          ownerId: 'hetao',
          scheduleRepository: newSchedules,
          itemRepository: newItems,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('核桃'), findsOneWidget);
    expect(find.text('new-owner-course'), findsOneWidget);

    oldEntries.complete([_course('old-owner-course')]);
    oldSettings.complete(_settings());
    oldEvents.complete([_event('old-owner-event')]);
    await tester.pumpAndSettle();

    expect(find.text('new-owner-course'), findsOneWidget);
    expect(find.text('old-owner-course'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ChildDetailScreen ignores delayed results after disposal', (
    tester,
  ) async {
    final entries = Completer<List<ScheduleEntryModel>>();
    final schedules = _ScriptedScheduleRepository()
      ..entryResults.add(entries.future)
      ..settingsResults.add(Future.value(_settings()));
    final items = _ScriptedItemRepository()
      ..familyResults.add(Future.value(<ItemModel>[]));

    await tester.pumpWidget(
      MaterialApp(
        home: ChildDetailScreen(
          ownerId: 'beibei',
          scheduleRepository: schedules,
          itemRepository: items,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    entries.complete([_course('disposed-course')]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('ChildDetailScreen cancels an old delete after owner changes', (
    tester,
  ) async {
    _useWideView(tester);
    final oldSchedules = _ScriptedScheduleRepository()
      ..entryResults.add(Future.value([_course('old-course')]))
      ..settingsResults.add(Future.value(_settings()));
    final oldItems = _ScriptedItemRepository()
      ..familyResults.add(Future.value(<ItemModel>[]));
    final newSchedules = _ScriptedScheduleRepository()
      ..entryResults.add(Future.value([_course('new-course')]))
      ..settingsResults.add(Future.value(_settings()));
    final newItems = _ScriptedItemRepository()
      ..familyResults.add(Future.value(<ItemModel>[]));
    var ownerId = 'beibei';
    var schedules = oldSchedules;
    var items = oldItems;
    late void Function(void Function()) rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ChildDetailScreen(
              ownerId: ownerId,
              scheduleRepository: schedules,
              itemRepository: items,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('删除课程'), findsOneWidget);

    rebuild(() {
      ownerId = 'hetao';
      schedules = newSchedules;
      items = newItems;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('移入已删除'));
    await tester.pumpAndSettle();

    expect(oldSchedules.deletedIds, isEmpty);
    expect(newSchedules.deletedIds, isEmpty);
    expect(find.text('new-course'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ChildDetailScreen serializes rapid delete operations', (
    tester,
  ) async {
    _useWideView(tester);
    final schedules = _ScriptedScheduleRepository()
      ..entryResults.add(Future.value([_course('single-flight-course')]))
      ..settingsResults.add(Future.value(_settings()));
    final items = _ScriptedItemRepository()
      ..familyResults.add(Future.value(<ItemModel>[]));

    await tester.pumpWidget(
      MaterialApp(
        home: ChildDetailScreen(
          ownerId: 'beibei',
          scheduleRepository: schedules,
          itemRepository: items,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final deleteButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    deleteButton.onPressed!();
    deleteButton.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('删除课程'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(schedules.deletedIds, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

void _useWideView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Failure {
  const _Failure();
}

class _ScriptedScheduleRepository extends ScheduleRepository {
  final entryResults = <Object>[];
  final settingsResults = <Object>[];
  final deletedIds = <String>[];

  @override
  Future<List<ScheduleEntryModel>> getByOwner(String owner) {
    return _next(entryResults);
  }

  @override
  Future<ScheduleSettingsModel> getSettings() {
    return _next(settingsResults);
  }

  @override
  Future<void> softDelete(String id) async {
    deletedIds.add(id);
  }
}

class _ScriptedItemRepository extends ItemRepository {
  final familyResults = <Object>[];

  @override
  Future<List<ItemModel>> getFamilyItems(DateTime day, List<String> owners) {
    return _next(familyResults);
  }
}

Future<T> _next<T>(List<Object> values) {
  final value = values.removeAt(0);
  if (value is _Failure) {
    return Future<T>.error(StateError('private family storage marker'));
  }
  return value as Future<T>;
}

ScheduleSettingsModel _settings() {
  return ScheduleSettingsModel(updatedAt: DateTime(2026, 7, 16));
}

ScheduleEntryModel _course(String title) {
  return ScheduleEntryModel(
    id: title,
    owner: 'beibei',
    title: title,
    weekday: 1,
    startTime: '08:00',
    endTime: '09:40',
    createdAt: DateTime(2026, 7, 16),
  );
}

ItemModel _event(String title) {
  final now = DateTime(2026, 7, 16, 8);
  return ItemModel(
    id: title,
    type: 'meeting',
    title: title,
    owner: 'beibei',
    startAt: now,
    createdAt: now,
    updatedAt: now,
  );
}
