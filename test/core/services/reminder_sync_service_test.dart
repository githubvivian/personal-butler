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
}

ItemModel _pendingItem({
  String status = 'active',
  String pendingStatus = 'submitted',
  DateTime? startAt,
  DateTime? nextFollowUpAt,
}) {
  final now = DateTime(2026, 7, 15);
  return ItemModel(
    id: 'pending-reminder',
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

class _EmptyBirthdayRepository extends BirthdayRepository {
  @override
  Future<List<BirthdayModel>> getAll() async => [];
}
