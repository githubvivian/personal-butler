import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/services/reminder_sync_service.dart';

const _notificationChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const _timezoneChannel = MethodChannel('flutter_timezone');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_notificationChannel, null);
    messenger.setMockMethodCallHandler(_timezoneChannel, null);
  });

  group('notification IDs', () {
    test('matches the v1 ASCII known vectors', () {
      const sourceId = 'pending-reminder';

      expect(ReminderSyncService.itemId(sourceId), 546808337);
      expect(ReminderSyncService.pendingId(sourceId), 681026065);
      expect(ReminderSyncService.birthdayAdvanceId(sourceId), 815243793);
      expect(ReminderSyncService.birthdayDayId(sourceId), 949461521);
    });

    test('matches the v1 UTF-8 known vectors for a non-ASCII ID', () {
      const sourceId = '生日-张三';

      expect(ReminderSyncService.itemId(sourceId), 571105456);
      expect(ReminderSyncService.pendingId(sourceId), 705323184);
      expect(ReminderSyncService.birthdayAdvanceId(sourceId), 839540912);
      expect(ReminderSyncService.birthdayDayId(sourceId), 973758640);
    });

    test('keeps all four type namespaces isolated and Android-safe', () {
      for (final sourceId in ['', 'a', 'item-123', '生日-张三']) {
        final ids = [
          ReminderSyncService.itemId(sourceId),
          ReminderSyncService.pendingId(sourceId),
          ReminderSyncService.birthdayAdvanceId(sourceId),
          ReminderSyncService.birthdayDayId(sourceId),
        ];

        expect(ids.toSet(), hasLength(4));
        for (final id in ids) {
          expect(id, inInclusiveRange(0, 0x7fffffff));
        }
      }
    });
  });

  test('done item cancels both notification ids without scheduling', () async {
    final cancelled = <int>[];
    var itemSchedules = 0;
    var weakSchedules = 0;
    final service = ReminderSyncService(
      cancelNotification: (id) async => cancelled.add(id),
      scheduleItemReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {
            itemSchedules++;
          },
      scheduleWeakReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {
            weakSchedules++;
          },
    );
    final item = _pendingItem(
      status: 'done',
      pendingStatus: 'done',
      startAt: DateTime(2026, 7, 16, 10),
      nextFollowUpAt: DateTime(2026, 7, 22),
    );

    await service.syncItem(item);

    expect(cancelled, [
      ReminderSyncService.itemId(item.id),
      ReminderSyncService.pendingId(item.id),
    ]);
    expect(itemSchedules, 0);
    expect(weakSchedules, 0);
  });

  test('active timed item is still scheduled after cancellation', () async {
    final events = <String>[];
    final service = ReminderSyncService(
      cancelNotification: (id) async => events.add('cancel:$id'),
      scheduleItemReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {
            events.add('item:$id');
          },
      scheduleWeakReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {
            events.add('weak:$id');
          },
    );
    final item = _pendingItem(
      startAt: DateTime.now().add(const Duration(days: 1)),
      nextFollowUpAt: null,
    );

    await service.syncItem(item);

    expect(events, [
      'cancel:${ReminderSyncService.itemId(item.id)}',
      'cancel:${ReminderSyncService.pendingId(item.id)}',
      'item:${ReminderSyncService.itemId(item.id)}',
    ]);
  });

  test(
    'syncItem runs every independent action after an early failure',
    () async {
      final firstError = StateError('first cancel failed');
      final events = <String>[];
      final item = _pendingItem(
        id: 'best-effort-item',
        startAt: DateTime.now().add(const Duration(days: 1)),
        nextFollowUpAt: DateTime.now().add(const Duration(days: 2)),
      );
      final service = ReminderSyncService(
        cancelNotification: (id) async {
          events.add('cancel:$id');
          if (id == ReminderSyncService.itemId(item.id)) throw firstError;
        },
        scheduleItemReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {
              events.add('item:$id');
            },
        scheduleWeakReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {
              events.add('weak:$id');
            },
      );

      await expectLater(service.syncItem(item), throwsA(same(firstError)));

      expect(events, [
        'cancel:${ReminderSyncService.itemId(item.id)}',
        'cancel:${ReminderSyncService.pendingId(item.id)}',
        'item:${ReminderSyncService.itemId(item.id)}',
        'weak:${ReminderSyncService.pendingId(item.id)}',
      ]);
    },
  );

  test(
    'syncBirthday runs later cancellations and schedules after failure',
    () async {
      final firstError = StateError('birthday cancel failed');
      final events = <String>[];
      final birthdayDate = DateTime.now().add(const Duration(days: 10));
      final birthday = BirthdayModel(
        id: 'best-effort-birthday',
        name: 'Birthday',
        isLunar: false,
        month: birthdayDate.month,
        day: birthdayDate.day,
        remindDaysBefore: 1,
        createdAt: DateTime.now(),
      );
      final service = ReminderSyncService(
        cancelNotification: (id) async {
          events.add('cancel:$id');
          if (id == ReminderSyncService.birthdayAdvanceId(birthday.id)) {
            throw firstError;
          }
        },
        scheduleItemReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {
              events.add('item:$id');
            },
        scheduleWeakReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {
              events.add('weak:$id');
            },
      );

      await expectLater(
        service.syncBirthday(birthday),
        throwsA(same(firstError)),
      );

      expect(events, [
        'cancel:${ReminderSyncService.birthdayAdvanceId(birthday.id)}',
        'cancel:${ReminderSyncService.birthdayDayId(birthday.id)}',
        'weak:${ReminderSyncService.birthdayAdvanceId(birthday.id)}',
        'item:${ReminderSyncService.birthdayDayId(birthday.id)}',
      ]);
    },
  );

  test(
    'syncBirthday schedules today at 09:00 when it is still upcoming',
    () async {
      final now = DateTime(2026, 7, 18, 8, 59, 59);
      final birthday = BirthdayModel(
        id: 'same-day-before-nine',
        name: 'Birthday',
        isLunar: false,
        month: now.month,
        day: now.day,
        remindDaysBefore: 1,
        createdAt: now,
      );
      final strong = <int, DateTime>{};
      final service = ReminderSyncService(
        now: () => now,
        cancelNotification: (_) async {},
        scheduleItemReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async => strong[id] = when,
        scheduleWeakReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {},
      );

      await service.syncBirthday(birthday);

      expect(
        strong[ReminderSyncService.birthdayDayId(birthday.id)],
        DateTime(2026, 7, 18, 9),
      );
    },
  );

  test(
    'reconcileAll moves a same-day birthday past the 09:00 boundary',
    () async {
      final now = DateTime(2026, 7, 18, 9);
      final birthday = BirthdayModel(
        id: 'same-day-at-nine',
        name: 'Birthday',
        isLunar: false,
        month: now.month,
        day: now.day,
        remindDaysBefore: 1,
        createdAt: now,
      );
      final strong = <int, DateTime>{};
      final service = ReminderSyncService(
        now: () => now,
        cancelNotification: (_) async {},
        pendingNotificationIds: () async => <int>{},
        activeNotificationIds: () async => <int>{},
        scheduleItemReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async => strong[id] = when,
        scheduleWeakReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {},
      );

      await service.reconcileAll(
        items: _EmptyItemRepository(),
        birthdays: _BirthdayRepository([birthday]),
      );

      expect(
        strong[ReminderSyncService.birthdayDayId(birthday.id)],
        DateTime(2027, 7, 18, 9),
      );
    },
  );

  test(
    'syncAll continues with later items and birthdays after one failure',
    () async {
      final firstError = StateError('first item failed');
      final events = <String>[];
      final firstItem = _pendingItem(
        id: 'first-sync-all',
        startAt: DateTime.now().add(const Duration(days: 1)),
      );
      final secondItem = _pendingItem(
        id: 'second-sync-all',
        startAt: DateTime.now().add(const Duration(days: 2)),
      );
      final birthdayDate = DateTime.now().add(const Duration(days: 10));
      final birthday = BirthdayModel(
        id: 'sync-all-birthday',
        name: 'Birthday',
        isLunar: false,
        month: birthdayDate.month,
        day: birthdayDate.day,
        remindDaysBefore: 1,
        createdAt: DateTime.now(),
      );
      final service = ReminderSyncService(
        cancelNotification: (id) async {
          events.add('cancel:$id');
          if (id == ReminderSyncService.itemId(firstItem.id)) throw firstError;
        },
        scheduleItemReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {
              events.add('item:$id');
            },
        scheduleWeakReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {
              events.add('weak:$id');
            },
      );

      await expectLater(
        service.syncAll(
          items: _ItemRepository([firstItem, secondItem]),
          birthdays: _BirthdayRepository([birthday]),
        ),
        throwsA(same(firstError)),
      );

      expect(
        events,
        contains('cancel:${ReminderSyncService.itemId(secondItem.id)}'),
      );
      expect(
        events,
        contains('item:${ReminderSyncService.itemId(secondItem.id)}'),
      );
      expect(
        events,
        contains(
          'cancel:${ReminderSyncService.birthdayAdvanceId(birthday.id)}',
        ),
      );
      expect(
        events,
        contains('item:${ReminderSyncService.birthdayDayId(birthday.id)}'),
      );
    },
  );

  test(
    'syncItem preserves the first error without exposing later errors',
    () async {
      final firstError = StateError('first error');
      final laterError = StateError('later error details');
      final item = _pendingItem(
        id: 'first-error-item',
        startAt: DateTime.now().add(const Duration(days: 1)),
      );
      final service = ReminderSyncService(
        cancelNotification: (id) async {
          if (id == ReminderSyncService.itemId(item.id)) throw firstError;
          throw laterError;
        },
        scheduleItemReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {},
        scheduleWeakReminder:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
            }) async {},
      );

      await expectLater(service.syncItem(item), throwsA(same(firstError)));
    },
  );

  test('syncAll silently reschedules without requesting permission', () async {
    final notificationMethods = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_timezoneChannel, (_) async {
      return 'Asia/Shanghai';
    });
    messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
      notificationMethods.add(call.method);
      return true;
    });
    final service = ReminderSyncService(
      cancelNotification: (_) async {},
      scheduleItemReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {},
      scheduleWeakReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {},
    );

    await service.syncAll(
      items: _EmptyItemRepository(),
      birthdays: _EmptyBirthdayRepository(),
    );

    expect(
      notificationMethods,
      isNot(contains('requestNotificationsPermission')),
    );
  });

  test('reconcileAll cancels legacy pending but schedules desired', () async {
    final cancelled = <int>[];
    final scheduled = <int>[];
    final item = _pendingItem(
      startAt: DateTime.now().add(const Duration(days: 1)),
      nextFollowUpAt: null,
    );
    final desiredId = ReminderSyncService.itemId(item.id);
    final service = ReminderSyncService(
      cancelNotification: (id) async => cancelled.add(id),
      pendingNotificationIds: () async => {42, desiredId},
      activeNotificationIds: () async => <int>{},
      scheduleItemReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async => scheduled.add(id),
      scheduleWeakReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {},
    );

    await service.reconcileAll(
      items: _ItemRepository([item]),
      birthdays: _EmptyBirthdayRepository(),
    );

    expect(cancelled, [42]);
    expect(scheduled, [desiredId]);
  });

  test('reconcileAll preserves an active notification', () async {
    final cancelled = <int>[];
    final service = ReminderSyncService(
      cancelNotification: (id) async => cancelled.add(id),
      pendingNotificationIds: () async => {42},
      activeNotificationIds: () async => {42},
      scheduleItemReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {},
      scheduleWeakReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {},
    );

    await service.reconcileAll(
      items: _EmptyItemRepository(),
      birthdays: _EmptyBirthdayRepository(),
    );

    expect(cancelled, isEmpty);
  });

  test('reconcileAll skips cleanup but schedules when a query fails', () async {
    final error = StateError('pending query failed');
    final cancelled = <int>[];
    final scheduled = <int>[];
    var activeQueries = 0;
    final item = _pendingItem(
      startAt: DateTime.now().add(const Duration(days: 1)),
      nextFollowUpAt: null,
    );
    final service = ReminderSyncService(
      cancelNotification: (id) async => cancelled.add(id),
      pendingNotificationIds: () async => throw error,
      activeNotificationIds: () async {
        activeQueries++;
        return <int>{};
      },
      scheduleItemReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async => scheduled.add(id),
      scheduleWeakReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {},
    );

    await expectLater(
      service.reconcileAll(
        items: _ItemRepository([item]),
        birthdays: _EmptyBirthdayRepository(),
      ),
      throwsA(same(error)),
    );

    expect(activeQueries, 1);
    expect(cancelled, isEmpty);
    expect(scheduled, [ReminderSyncService.itemId(item.id)]);
  });

  test('reconcileAll continues after cancel and schedule failures', () async {
    final cancelError = StateError('cancel failed');
    final scheduleError = StateError('schedule failed');
    final cancelled = <int>[];
    final scheduled = <int>[];
    final firstItem = _pendingItem(
      id: 'first',
      startAt: DateTime.now().add(const Duration(days: 1)),
      nextFollowUpAt: null,
    );
    final secondItem = _pendingItem(
      id: 'second',
      startAt: DateTime.now().add(const Duration(days: 2)),
      nextFollowUpAt: null,
    );
    final firstDesiredId = ReminderSyncService.itemId(firstItem.id);
    final secondDesiredId = ReminderSyncService.itemId(secondItem.id);
    final service = ReminderSyncService(
      cancelNotification: (id) async {
        cancelled.add(id);
        if (id == 41) throw cancelError;
      },
      pendingNotificationIds: () async => {41, 42},
      activeNotificationIds: () async => <int>{},
      scheduleItemReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {
            scheduled.add(id);
            if (id == firstDesiredId) throw scheduleError;
          },
      scheduleWeakReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async {},
    );

    await expectLater(
      service.reconcileAll(
        items: _ItemRepository([firstItem, secondItem]),
        birthdays: _EmptyBirthdayRepository(),
      ),
      throwsA(same(cancelError)),
    );

    expect(cancelled, [41, 42]);
    expect(scheduled, [firstDesiredId, secondDesiredId]);
  });

  test('reconcileAll schedules every future strong and weak plan', () async {
    final now = DateTime.now();
    final timedItem = _pendingItem(
      id: 'timed',
      startAt: now.add(const Duration(days: 2)),
      nextFollowUpAt: null,
    );
    final followUpItem = _pendingItem(
      id: 'follow-up',
      startAt: null,
      nextFollowUpAt: now.add(const Duration(days: 1)),
    );
    final birthdayDate = now.add(const Duration(days: 1));
    final birthday = BirthdayModel(
      id: 'birthday',
      name: 'Birthday',
      isLunar: false,
      month: birthdayDate.month,
      day: birthdayDate.day,
      remindDaysBefore: 0,
      createdAt: now,
    );
    final strong = <int, DateTime>{};
    final weak = <int, DateTime>{};
    final service = ReminderSyncService(
      cancelNotification: (_) async {},
      pendingNotificationIds: () async => <int>{},
      activeNotificationIds: () async => <int>{},
      scheduleItemReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async => strong[id] = when,
      scheduleWeakReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async => weak[id] = when,
    );

    await service.reconcileAll(
      items: _ItemRepository([timedItem, followUpItem]),
      birthdays: _BirthdayRepository([birthday]),
    );

    expect(strong.keys, {
      ReminderSyncService.itemId(timedItem.id),
      ReminderSyncService.birthdayDayId(birthday.id),
    });
    expect(weak.keys, {
      ReminderSyncService.pendingId(followUpItem.id),
      ReminderSyncService.birthdayAdvanceId(birthday.id),
    });
    expect(strong.values.every((when) => when.isAfter(now)), isTrue);
    expect(weak.values.every((when) => when.isAfter(now)), isTrue);
  });

  test(
    'reconcileAll supplies safe destinations for notification taps',
    () async {
      final now = DateTime(2026, 7, 15, 8);
      final item = _pendingItem(
        id: 'tap-item',
        startAt: now.add(const Duration(days: 1)),
        nextFollowUpAt: now.add(const Duration(hours: 2)),
      );
      final birthday = BirthdayModel(
        id: 'tap-birthday',
        name: 'Birthday',
        isLunar: false,
        month: 7,
        day: 20,
        remindDaysBefore: 1,
        createdAt: now,
      );
      final payloads = <int, String?>{};
      final service = ReminderSyncService(
        now: () => now,
        cancelNotification: (_) async {},
        pendingNotificationIds: () async => <int>{},
        activeNotificationIds: () async => <int>{},
        scheduleItemReminderWithPayload:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
              required String? payload,
            }) async {
              payloads[id] = payload;
            },
        scheduleWeakReminderWithPayload:
            ({
              required int id,
              required String title,
              required String body,
              required DateTime when,
              required String? payload,
            }) async {
              payloads[id] = payload;
            },
      );

      await service.reconcileAll(
        items: _ItemRepository([item]),
        birthdays: _BirthdayRepository([birthday]),
      );

      expect(payloads[ReminderSyncService.itemId(item.id)], '/item/tap-item');
      expect(
        payloads[ReminderSyncService.pendingId(item.id)],
        '/item/tap-item',
      );
      expect(
        payloads[ReminderSyncService.birthdayAdvanceId(birthday.id)],
        '/birthdays',
      );
      expect(
        payloads[ReminderSyncService.birthdayDayId(birthday.id)],
        '/birthdays',
      );
    },
  );

  test('reconcileAll handles empty repositories without permission', () async {
    final notificationMethods = <String>[];
    final cancelled = <int>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
      notificationMethods.add(call.method);
      return null;
    });
    final service = ReminderSyncService(
      cancelNotification: (id) async => cancelled.add(id),
      pendingNotificationIds: () async => {42},
      activeNotificationIds: () async => <int>{},
      scheduleItemReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async => fail('empty repositories must not schedule'),
      scheduleWeakReminder:
          ({
            required int id,
            required String title,
            required String body,
            required DateTime when,
          }) async => fail('empty repositories must not schedule'),
    );

    await service.reconcileAll(
      items: _EmptyItemRepository(),
      birthdays: _EmptyBirthdayRepository(),
    );

    expect(cancelled, [42]);
    expect(
      notificationMethods,
      isNot(contains('requestNotificationsPermission')),
    );
  });
}

ItemModel _pendingItem({
  String id = 'pending-reminder',
  String status = 'active',
  String pendingStatus = 'submitted',
  DateTime? startAt,
  DateTime? nextFollowUpAt,
}) {
  final now = DateTime(2026, 7, 15);
  return ItemModel(
    id: id,
    type: 'review',
    title: '待跟进事项',
    status: status,
    inboxStatus: 'confirmed',
    pendingStatus: pendingStatus,
    startAt: startAt,
    nextFollowUpAt: nextFollowUpAt,
    createdAt: now,
    updatedAt: now,
  );
}

class _EmptyItemRepository extends ItemRepository {
  @override
  Future<List<ItemModel>> getAllActiveConfirmed() async => [];
}

class _ItemRepository extends ItemRepository {
  _ItemRepository(this.items);

  final List<ItemModel> items;

  @override
  Future<List<ItemModel>> getAllActiveConfirmed() async => items;
}

class _EmptyBirthdayRepository extends BirthdayRepository {
  @override
  Future<List<BirthdayModel>> getAll() async => [];
}

class _BirthdayRepository extends BirthdayRepository {
  _BirthdayRepository(this.birthdays);

  final List<BirthdayModel> birthdays;

  @override
  Future<List<BirthdayModel>> getAll() async => birthdays;
}
