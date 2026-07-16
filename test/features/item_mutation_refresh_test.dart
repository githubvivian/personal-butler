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

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets('Inbox ignores an older query that completes after a mutation', (
    tester,
  ) async {
    final repository = _DeferredInboxRepository();

    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(itemRepository: repository)),
    );
    await tester.pump();
    expect(repository.inboxLoads, 1);

    repository.commitMutation();
    await tester.pump();
    expect(repository.inboxLoads, 2);

    repository.second.complete([_inboxItem('new-result')]);
    await tester.pumpAndSettle();
    expect(find.text('new-result'), findsOneWidget);

    repository.first.complete([_inboxItem('stale-result')]);
    await tester.pumpAndSettle();
    expect(find.text('new-result'), findsOneWidget);
    expect(find.text('stale-result'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inbox rebinds to a replacement repository', (tester) async {
    final first = _RefreshItemRepository();
    final second = _RefreshItemRepository();

    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(itemRepository: first)),
    );
    await tester.pumpAndSettle();
    expect(first.inboxLoads, 1);

    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(itemRepository: second)),
    );
    await tester.pumpAndSettle();
    expect(second.inboxLoads, 1);

    first.commitMutation();
    await tester.pumpAndSettle();
    expect(first.inboxLoads, 1);
    expect(second.inboxLoads, 1);

    second.commitMutation();
    await tester.pumpAndSettle();
    expect(second.inboxLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pending rebinds to a replacement repository', (tester) async {
    final first = _RefreshItemRepository();
    final second = _RefreshItemRepository();

    await tester.pumpWidget(
      MaterialApp(home: PendingScreen(itemRepository: first)),
    );
    await tester.pumpAndSettle();
    expect(first.pendingLoads, 1);

    await tester.pumpWidget(
      MaterialApp(home: PendingScreen(itemRepository: second)),
    );
    await tester.pumpAndSettle();
    expect(second.pendingLoads, 1);

    first.commitMutation();
    await tester.pumpAndSettle();
    expect(first.pendingLoads, 1);
    expect(second.pendingLoads, 1);

    second.commitMutation();
    await tester.pumpAndSettle();
    expect(second.pendingLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained root screens reload after a committed item mutation and unsubscribe on dispose',
    (tester) async {
      final repository = _RefreshItemRepository();
      final appState = _RefreshAppState(repository);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: IndexedStack(
              index: 0,
              children: [
                InboxScreen(),
                CalendarScreen(),
                PendingScreen(),
                FamilyScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.inboxLoads, 1);
      expect(repository.calendarLoads, 1);
      expect(repository.pendingLoads, 1);
      expect(repository.familyLoads, 1);
      expect(repository.statsLoads, 2);
      expect(appState.ideaRepository.loads, 1);
      expect(appState.birthdayRepository.loads, 1);
      expect(appState.scheduleRepository.loads, 1);

      repository.commitMutation();
      await tester.pumpAndSettle();

      expect(repository.inboxLoads, 2);
      expect(repository.calendarLoads, 2);
      expect(repository.pendingLoads, 2);
      expect(repository.familyLoads, 2);
      expect(repository.statsLoads, 4);
      expect(appState.ideaRepository.loads, 1);
      expect(appState.birthdayRepository.loads, 1);
      expect(appState.scheduleRepository.loads, 1);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      repository.commitMutation();
      await tester.pump();

      expect(repository.inboxLoads, 2);
      expect(repository.calendarLoads, 2);
      expect(repository.pendingLoads, 2);
      expect(repository.familyLoads, 2);
      expect(repository.statsLoads, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('full data revision reloads every Settings summary', (
    tester,
  ) async {
    final repository = _RefreshItemRepository();
    final appState = _RefreshAppState(repository);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(appState.ideaRepository.loads, 1);
    expect(appState.birthdayRepository.loads, 1);
    expect(appState.scheduleRepository.loads, 1);

    appState.replaceAllData();
    await tester.pumpAndSettle();

    expect(appState.ideaRepository.loads, 2);
    expect(appState.birthdayRepository.loads, 2);
    expect(appState.scheduleRepository.loads, 2);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('课表设置'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('第5-10周 · 已设开学日期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DeferredInboxRepository extends ItemRepository {
  final first = Completer<List<ItemModel>>();
  final second = Completer<List<ItemModel>>();
  int inboxLoads = 0;

  void commitMutation() => notifyListeners();

  @override
  Future<List<ItemModel>> getInboxItems() {
    inboxLoads += 1;
    return inboxLoads == 1 ? first.future : second.future;
  }

  @override
  Future<Map<String, int>> getTodayStats() async => {};
}

class _RefreshItemRepository extends ItemRepository {
  int revision = 0;
  int inboxLoads = 0;
  int calendarLoads = 0;
  int pendingLoads = 0;
  int familyLoads = 0;
  int statsLoads = 0;

  void commitMutation() {
    revision += 1;
    notifyListeners();
  }

  @override
  Future<List<ItemModel>> getInboxItems() async {
    inboxLoads += 1;
    return [_item('inbox', inboxStatus: 'inbox')];
  }

  @override
  Future<List<ItemModel>> getCalendarItems(DateTime day) async {
    calendarLoads += 1;
    return [
      _item('calendar', startAt: DateTime(day.year, day.month, day.day, 9)),
    ];
  }

  @override
  Future<List<ItemModel>> getPendingItems({bool includeDone = false}) async {
    pendingLoads += 1;
    return [_item('pending', type: 'review', pendingStatus: 'submitted')];
  }

  @override
  Future<List<ItemModel>> getFamilyItems(
    DateTime day,
    List<String> owners,
  ) async {
    familyLoads += 1;
    return [
      _item(
        'family',
        owner: owners.first,
        startAt: DateTime(day.year, day.month, day.day, 10),
      ),
    ];
  }

  @override
  Future<Map<String, int>> getTodayStats() async {
    statsLoads += 1;
    return {'inbox': revision, 'pending': revision, 'today': revision};
  }

  ItemModel _item(
    String source, {
    String type = 'meeting',
    String owner = 'self',
    String inboxStatus = 'confirmed',
    String? pendingStatus,
    DateTime? startAt,
  }) {
    final now = DateTime(2026, 7, 16, 8);
    return ItemModel(
      id: '$source-$revision',
      type: type,
      title: '$source-$revision',
      owner: owner,
      inboxStatus: inboxStatus,
      pendingStatus: pendingStatus,
      startAt: startAt,
      createdAt: now,
      updatedAt: now,
    );
  }
}

class _RefreshAppState extends AppState {
  _RefreshAppState(this._itemRepository)
    : super(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        validateSession: () async => true,
        syncReminders: () async {},
      );

  final ItemRepository _itemRepository;
  final ideaRepository = _MutableIdeaRepository();
  final birthdayRepository = _MutableBirthdayRepository();
  final scheduleRepository = _MutableScheduleRepository();

  void replaceAllData() {
    ideaRepository.count = 2;
    birthdayRepository.count = 3;
    scheduleRepository.settings = ScheduleSettingsModel(
      semesterStartWeek: 5,
      semesterEndWeek: 10,
      semesterStartDate: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 7, 16),
    );
    refresh();
  }

  @override
  ItemRepository get items => _itemRepository;

  @override
  IdeaRepository get ideas => ideaRepository;

  @override
  BirthdayRepository get birthdays => birthdayRepository;

  @override
  ScheduleRepository get schedules => scheduleRepository;
}

class _MutableIdeaRepository extends IdeaRepository {
  int count = 0;
  int loads = 0;

  @override
  Future<List<IdeaModel>> getAll({String? tag}) async {
    loads += 1;
    return List.generate(
      count,
      (index) => IdeaModel(
        id: 'idea-$index',
        title: 'Idea $index',
        content: '',
        createdAt: DateTime(2026, 7, 16),
      ),
    );
  }
}

class _MutableBirthdayRepository extends BirthdayRepository {
  int count = 0;
  int loads = 0;

  @override
  Future<List<BirthdayModel>> getAll() async {
    loads += 1;
    return List.generate(
      count,
      (index) => BirthdayModel(
        id: 'birthday-$index',
        name: 'Birthday $index',
        isLunar: false,
        month: 1,
        day: 1,
        createdAt: DateTime(2026, 7, 16),
      ),
    );
  }
}

class _MutableScheduleRepository extends ScheduleRepository {
  int loads = 0;
  ScheduleSettingsModel settings = ScheduleSettingsModel(
    updatedAt: DateTime(2026, 7, 16),
  );

  @override
  Future<ScheduleSettingsModel> getSettings() async {
    loads += 1;
    return settings;
  }
}

ItemModel _inboxItem(String title) {
  final now = DateTime(2026, 7, 16, 8);
  return ItemModel(
    id: title,
    type: 'meeting',
    title: title,
    owner: 'self',
    inboxStatus: 'inbox',
    createdAt: now,
    updatedAt: now,
  );
}
