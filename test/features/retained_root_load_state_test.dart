import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/repositories/schedule_repository.dart';
import 'package:personal_butler/features/calendar/calendar_screen.dart';
import 'package:personal_butler/features/family/family_screen.dart';
import 'package:personal_butler/features/inbox/inbox_screen.dart';
import 'package:personal_butler/features/pending/pending_screen.dart';
import 'package:personal_butler/features/settings/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

const _failureMessage = '数据加载失败，请重试';
const _sensitiveError = 'TOP_SECRET_DATABASE_PATH';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets(
    'Inbox keeps a same-key snapshot but reports a sanitized refresh failure',
    (tester) async {
      final repository = _ScriptedItemRepository()
        ..inboxResults.addAll([
          Future.value([_item('old-inbox', inboxStatus: 'inbox')]),
          const _Failure(),
          Future.value([_item('new-inbox', inboxStatus: 'inbox')]),
        ])
        ..statsResults.addAll([
          Future.value({'inbox': 1, 'pending': 2, 'today': 3}),
          Future.value({'inbox': 4, 'pending': 5, 'today': 6}),
        ]);

      await tester.pumpWidget(
        MaterialApp(home: InboxScreen(itemRepository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('old-inbox'), findsOneWidget);

      repository.commitMutation();
      await tester.pumpAndSettle();

      expect(find.text('old-inbox'), findsOneWidget);
      expect(find.text(_failureMessage), findsOneWidget);
      expect(find.textContaining(_sensitiveError), findsNothing);
      expect(find.text('暂无待处理事项，可通过下方快捷入口添加'), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('new-inbox'), findsOneWidget);
      expect(find.text(_failureMessage), findsNothing);
    },
  );

  testWidgets('Inbox clears the previous repository snapshot on rebind', (
    tester,
  ) async {
    final oldRepository = _ScriptedItemRepository()
      ..inboxResults.add(
        Future.value([_item('old-repository-item', inboxStatus: 'inbox')]),
      )
      ..statsResults.add(Future.value(<String, int>{}));
    final newRepository = _ScriptedItemRepository()
      ..inboxResults.add(const _Failure());

    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(itemRepository: oldRepository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('old-repository-item'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(itemRepository: newRepository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('old-repository-item'), findsNothing);
    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.textContaining(_sensitiveError), findsNothing);
  });

  testWidgets('Calendar clears the previous day and exposes retry on failure', (
    tester,
  ) async {
    final nextLoad = Completer<List<ItemModel>>();
    final repository = _ScriptedItemRepository()
      ..calendarResults.addAll([
        Future.value([_item('old-day')]),
        nextLoad.future,
        Future.value([_item('new-day')]),
      ]);
    final appState = _TestAppState(repository);

    await tester.pumpWidget(_provided(appState, const CalendarScreen()));
    await tester.pumpAndSettle();
    expect(find.text('old-day'), findsOneWidget);

    final calendar = tester.widget<TableCalendar<dynamic>>(
      find.byType(TableCalendar),
    );
    final nextDay = DateTime.now().add(const Duration(days: 1));
    calendar.onDaySelected!(nextDay, nextDay);
    await tester.pump();

    expect(find.text('old-day'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    nextLoad.completeError(Exception(_sensitiveError));
    await tester.pumpAndSettle();
    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.text('今天暂无日程'), findsNothing);
    expect(find.textContaining(_sensitiveError), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('new-day'), findsOneWidget);
  });

  testWidgets('Calendar uses Chinese labels and retains a paged month', (
    tester,
  ) async {
    final repository = _ScriptedItemRepository()
      ..calendarResults.addAll([
        Future.value(<ItemModel>[]),
        Future.value(<ItemModel>[]),
      ]);
    final appState = _TestAppState(repository);

    await tester.pumpWidget(_provided(appState, const CalendarScreen()));
    await tester.pumpAndSettle();

    var calendar = tester.widget<TableCalendar<dynamic>>(
      find.byType(TableCalendar),
    );
    expect(calendar.locale, 'zh_CN');

    final initial = calendar.focusedDay;
    final nextMonth = DateTime(initial.year, initial.month + 1, 1);
    calendar.onPageChanged!(nextMonth);
    repository.commitMutation();
    await tester.pumpAndSettle();

    calendar = tester.widget<TableCalendar<dynamic>>(
      find.byType(TableCalendar),
    );
    expect(calendar.focusedDay.year, nextMonth.year);
    expect(calendar.focusedDay.month, nextMonth.month);
    expect(calendar.locale, 'zh_CN');
  });

  testWidgets('Pending clears the previous tab and exposes retry on failure', (
    tester,
  ) async {
    final nextLoad = Completer<List<ItemModel>>();
    final repository = _ScriptedItemRepository()
      ..pendingResults.addAll([
        Future.value([_item('old-tab', status: 'done')]),
        nextLoad.future,
        Future.value([_item('new-tab', status: 'done')]),
      ]);

    await tester.pumpWidget(
      MaterialApp(home: PendingScreen(itemRepository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('old-tab'), findsOneWidget);

    await tester.tap(find.text('已完成'));
    await tester.pump();
    expect(find.text('old-tab'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    nextLoad.completeError(Exception(_sensitiveError));
    await tester.pumpAndSettle();
    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.text('暂无悬而未决事项'), findsNothing);
    expect(find.textContaining(_sensitiveError), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('new-tab'), findsOneWidget);
  });

  testWidgets(
    'Family clears the previous filter and exposes retry on failure',
    (tester) async {
      final nextLoad = Completer<List<ItemModel>>();
      final repository = _ScriptedItemRepository()
        ..familyResults.addAll([
          Future.value([_item('old-family', owner: 'family')]),
          nextLoad.future,
          Future.value([_item('new-family', owner: 'beibei')]),
        ]);
      final appState = _TestAppState(repository);

      await tester.pumpWidget(_provided(appState, const FamilyScreen()));
      await tester.pumpAndSettle();
      expect(find.text('old-family'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, '贝贝'));
      await tester.pump();
      expect(find.text('old-family'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      nextLoad.completeError(Exception(_sensitiveError));
      await tester.pumpAndSettle();
      expect(find.text(_failureMessage), findsOneWidget);
      expect(find.textContaining('今日暂无家庭安排'), findsNothing);
      expect(find.textContaining(_sensitiveError), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('new-family'), findsOneWidget);
    },
  );

  testWidgets(
    'Settings initial failure never renders valid-looking zero stats',
    (tester) async {
      final repository = _ScriptedItemRepository()
        ..statsResults.addAll([
          const _Failure(),
          Future.value({'today': 1, 'pending': 2}),
        ]);
      final appState = _TestAppState(repository)
        ..ideaRepository.results.add(Future.value([_idea('idea')]))
        ..birthdayRepository.results.add(Future.value([_birthday('birthday')]))
        ..scheduleRepository.results.add(Future.value(_schedule()));

      await tester.pumpWidget(_provided(appState, const SettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text(_failureMessage), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.textContaining(_sensitiveError), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text(_failureMessage), findsNothing);
      expect(find.text('1'), findsNWidgets(3));
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets('Settings clears all summaries when the data revision changes', (
    tester,
  ) async {
    final replacementStats = Completer<Map<String, int>>();
    final repository = _ScriptedItemRepository()
      ..statsResults.addAll([
        Future.value({'today': 7, 'pending': 6}),
        replacementStats.future,
        Future.value({'today': 4, 'pending': 3}),
      ]);
    final appState = _TestAppState(repository)
      ..ideaRepository.results.addAll([
        Future.value(List.generate(8, (i) => _idea('old-idea-$i'))),
        Future.value([_idea('new-idea')]),
      ])
      ..birthdayRepository.results.addAll([
        Future.value(List.generate(9, (i) => _birthday('old-birthday-$i'))),
        Future.value([_birthday('new-birthday')]),
      ])
      ..scheduleRepository.results.addAll([
        Future.value(_schedule(startWeek: 1, endWeek: 20)),
        Future.value(_schedule(startWeek: 5, endWeek: 10)),
      ]);

    await tester.pumpWidget(_provided(appState, const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);

    appState.replaceAllData();
    await tester.pump();
    expect(find.text('7'), findsNothing);
    expect(find.text('8'), findsNothing);
    expect(find.text('9'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    replacementStats.completeError(Exception(_sensitiveError));
    await tester.pumpAndSettle();
    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.textContaining(_sensitiveError), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text(_failureMessage), findsNothing);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}

Widget _provided(AppState appState, Widget child) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(home: child),
  );
}

class _ScriptedItemRepository extends ItemRepository {
  final inboxResults = <Object>[];
  final calendarResults = <Object>[];
  final pendingResults = <Object>[];
  final familyResults = <Object>[];
  final statsResults = <Object>[];

  void commitMutation() => notifyListeners();

  @override
  Future<List<ItemModel>> getInboxItems() => _next(inboxResults);

  @override
  Future<List<ItemModel>> getCalendarItems(DateTime day) {
    return _next(calendarResults);
  }

  @override
  Future<List<ItemModel>> getPendingItems({bool includeDone = false}) {
    return _next(pendingResults);
  }

  @override
  Future<List<ItemModel>> getFamilyItems(DateTime day, List<String> owners) {
    return _next(familyResults);
  }

  @override
  Future<Map<String, int>> getTodayStats() => _next(statsResults);
}

class _Failure {
  const _Failure();
}

Future<T> _next<T>(List<Object> results) {
  final result = results.removeAt(0);
  if (result is _Failure) {
    return Future<T>.error(Exception(_sensitiveError));
  }
  return result as Future<T>;
}

class _TestAppState extends AppState {
  _TestAppState(this._items)
    : super(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        validateSession: () async => true,
        syncReminders: () async {},
      );

  final ItemRepository _items;
  final ideaRepository = _ScriptedIdeaRepository();
  final birthdayRepository = _ScriptedBirthdayRepository();
  final scheduleRepository = _ScriptedScheduleRepository();

  void replaceAllData() => refresh();

  @override
  ItemRepository get items => _items;

  @override
  IdeaRepository get ideas => ideaRepository;

  @override
  BirthdayRepository get birthdays => birthdayRepository;

  @override
  ScheduleRepository get schedules => scheduleRepository;
}

class _ScriptedIdeaRepository extends IdeaRepository {
  final results = <Future<List<IdeaModel>>>[];

  @override
  Future<List<IdeaModel>> getAll({String? tag}) => results.removeAt(0);
}

class _ScriptedBirthdayRepository extends BirthdayRepository {
  final results = <Future<List<BirthdayModel>>>[];

  @override
  Future<List<BirthdayModel>> getAll() => results.removeAt(0);
}

class _ScriptedScheduleRepository extends ScheduleRepository {
  final results = <Future<ScheduleSettingsModel>>[];

  @override
  Future<ScheduleSettingsModel> getSettings() => results.removeAt(0);
}

ItemModel _item(
  String title, {
  String owner = 'self',
  String status = 'active',
  String inboxStatus = 'confirmed',
}) {
  final now = DateTime(2026, 7, 16, 8);
  return ItemModel(
    id: title,
    type: 'meeting',
    title: title,
    owner: owner,
    status: status,
    inboxStatus: inboxStatus,
    startAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

IdeaModel _idea(String id) {
  return IdeaModel(
    id: id,
    title: id,
    content: '',
    createdAt: DateTime(2026, 7, 16),
  );
}

BirthdayModel _birthday(String id) {
  return BirthdayModel(
    id: id,
    name: id,
    isLunar: false,
    month: 1,
    day: 1,
    createdAt: DateTime(2026, 7, 16),
  );
}

ScheduleSettingsModel _schedule({int startWeek = 1, int endWeek = 20}) {
  return ScheduleSettingsModel(
    semesterStartWeek: startWeek,
    semesterEndWeek: endWeek,
    updatedAt: DateTime(2026, 7, 16),
  );
}
