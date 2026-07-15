import '../models/models.dart';
import '../repositories/item_repository.dart';
import '../repositories/other_repositories.dart';
import '../utils/lunar_date_helper.dart';
import 'notification_service.dart';
import 'notification_permission_coordinator.dart';

typedef ReminderScheduleAction = Future<void> Function({
  required int id,
  required String title,
  required String body,
  required DateTime when,
});

/// 启动时重排所有本地提醒（会议、悬停关注、生日）
class ReminderSyncService {
  ReminderSyncService({
    Future<void> Function(int)? cancelNotification,
    ReminderScheduleAction? scheduleItemReminder,
    ReminderScheduleAction? scheduleWeakReminder,
  }) : _cancelNotification =
           cancelNotification ?? NotificationService.instance.cancel,
       _scheduleItemReminder =
           scheduleItemReminder ??
           NotificationService.instance.scheduleItemReminder,
       _scheduleWeakReminder =
           scheduleWeakReminder ?? NotificationService.instance.scheduleWeakReminder;

  ReminderSyncService._() : this();
  static final ReminderSyncService instance = ReminderSyncService._();

  final Future<void> Function(int) _cancelNotification;
  final ReminderScheduleAction _scheduleItemReminder;
  final ReminderScheduleAction _scheduleWeakReminder;

  static int pendingId(String itemId) => itemId.hashCode ^ 0x100000;
  static int birthdayAdvanceId(String id) => id.hashCode ^ 0x200000;
  static int birthdayDayId(String id) => id.hashCode ^ 0x300000;

  Future<void> syncAll({
    required ItemRepository items,
    required BirthdayRepository birthdays,
  }) async {
    final allItems = await items.getAllActiveConfirmed();
    for (final item in allItems) {
      await syncItem(item);
    }

    final allBirthdays = await birthdays.getAll();
    for (final b in allBirthdays) {
      await syncBirthday(b);
    }
  }

  Future<void> syncItem(ItemModel item) async {
    await _cancelNotification(item.id.hashCode);
    await _cancelNotification(pendingId(item.id));

    if (!itemHasActiveReminder(item)) return;

    if (item.startAt != null) {
      final when = item.startAt!.subtract(Duration(minutes: item.reminderMinutes));
      await _scheduleItemReminder(
        id: item.id.hashCode,
        title: item.title,
        body: item.location ?? '日程提醒',
        when: when,
      );
    }

    if (item.isPendingType &&
        item.status != 'done' &&
        item.nextFollowUpAt != null) {
      await _scheduleWeakReminder(
        id: pendingId(item.id),
        title: '关注：${item.title}',
        body: '悬而未决事项到了关注时间，点击查看进展',
        when: item.nextFollowUpAt!,
      );
    }
  }

  Future<void> syncBirthday(BirthdayModel b) async {
    await _cancelNotification(birthdayAdvanceId(b.id));
    await _cancelNotification(birthdayDayId(b.id));
    if (b.isDeleted) return;

    final next = LunarDateHelper.nextSolarOccurrence(
      isLunar: b.isLunar,
      month: b.month,
      day: b.day,
      isLeapMonth: b.isLeapMonth,
    );
    if (next == null) return;

    final remindAt = DateTime(next.year, next.month, next.day, 9);
    final advance = remindAt.subtract(Duration(days: b.remindDaysBefore));

    if (advance.isAfter(DateTime.now())) {
      await _scheduleWeakReminder(
        id: birthdayAdvanceId(b.id),
        title: '生日临近',
        body: '${b.name} 的生日还有 ${b.remindDaysBefore} 天',
        when: advance,
      );
    }
    if (remindAt.isAfter(DateTime.now())) {
      await _scheduleItemReminder(
        id: birthdayDayId(b.id),
        title: '生日快乐',
        body: '今天是 ${b.name} 的生日',
        when: remindAt,
      );
    }
  }
}
