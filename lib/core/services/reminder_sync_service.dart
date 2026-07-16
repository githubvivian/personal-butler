import 'dart:convert';

import '../models/models.dart';
import '../repositories/item_repository.dart';
import '../repositories/other_repositories.dart';
import '../utils/lunar_date_helper.dart';
import 'notification_service.dart';
import 'notification_permission_coordinator.dart';

typedef ReminderScheduleAction =
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      required DateTime when,
    });

typedef NotificationIdQuery = Future<Set<int>> Function();

/// 启动时重排所有本地提醒（会议、悬停关注、生日）
class ReminderSyncService {
  ReminderSyncService({
    Future<void> Function(int)? cancelNotification,
    NotificationIdQuery? pendingNotificationIds,
    NotificationIdQuery? activeNotificationIds,
    ReminderScheduleAction? scheduleItemReminder,
    ReminderScheduleAction? scheduleWeakReminder,
  }) : _cancelNotification =
           cancelNotification ?? NotificationService.instance.cancel,
       _pendingNotificationIds =
           pendingNotificationIds ??
           NotificationService.instance.pendingNotificationIds,
       _activeNotificationIds =
           activeNotificationIds ??
           NotificationService.instance.activeNotificationIds,
       _scheduleItemReminder =
           scheduleItemReminder ??
           NotificationService.instance.scheduleItemReminder,
       _scheduleWeakReminder =
           scheduleWeakReminder ??
           NotificationService.instance.scheduleWeakReminder;

  ReminderSyncService._() : this();
  static final ReminderSyncService instance = ReminderSyncService._();

  final Future<void> Function(int) _cancelNotification;
  final NotificationIdQuery _pendingNotificationIds;
  final NotificationIdQuery _activeNotificationIds;
  final ReminderScheduleAction _scheduleItemReminder;
  final ReminderScheduleAction _scheduleWeakReminder;

  static const int notificationIdVersion = 1;
  static const int _payloadMask = 0x07ffffff;

  static int itemId(String id) => _notificationId(id, 0);
  static int pendingId(String id) => _notificationId(id, 1);
  static int birthdayAdvanceId(String id) => _notificationId(id, 2);
  static int birthdayDayId(String id) => _notificationId(id, 3);

  static int _notificationId(String sourceId, int type) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(sourceId)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return (notificationIdVersion << 29) | (type << 27) | (hash & _payloadMask);
  }

  Future<void> syncAll({
    required ItemRepository items,
    required BirthdayRepository birthdays,
  }) async {
    final allItems = await items.getAllActiveConfirmed();
    final allBirthdays = await birthdays.getAll();
    await _runBestEffort([
      for (final item in allItems) () => syncItem(item),
      for (final birthday in allBirthdays) () => syncBirthday(birthday),
    ]);
  }

  Future<void> reconcileAll({
    required ItemRepository items,
    required BirthdayRepository birthdays,
  }) async {
    final plans = <_ReminderPlan>[];
    final allItems = await items.getAllActiveConfirmed();
    final allBirthdays = await birthdays.getAll();
    final now = DateTime.now();

    for (final item in allItems) {
      if (!itemHasActiveReminder(item)) continue;
      if (item.startAt != null) {
        final when = item.startAt!.subtract(
          Duration(minutes: item.reminderMinutes),
        );
        if (when.isAfter(now)) {
          plans.add(
            _ReminderPlan(
              id: itemId(item.id),
              title: item.title,
              body: item.location ?? '日程提醒',
              when: when,
              schedule: _scheduleItemReminder,
            ),
          );
        }
      }
      if (item.isPendingType &&
          item.status != 'done' &&
          item.nextFollowUpAt != null &&
          item.nextFollowUpAt!.isAfter(now)) {
        plans.add(
          _ReminderPlan(
            id: pendingId(item.id),
            title: '关注：${item.title}',
            body: '悬而未决事项到了关注时间，点击查看进展',
            when: item.nextFollowUpAt!,
            schedule: _scheduleWeakReminder,
          ),
        );
      }
    }

    for (final birthday in allBirthdays) {
      if (birthday.isDeleted) continue;
      final next = LunarDateHelper.nextSolarOccurrence(
        isLunar: birthday.isLunar,
        month: birthday.month,
        day: birthday.day,
        isLeapMonth: birthday.isLeapMonth,
      );
      if (next == null) continue;
      final remindAt = DateTime(next.year, next.month, next.day, 9);
      final advance = remindAt.subtract(
        Duration(days: birthday.remindDaysBefore),
      );
      if (advance.isAfter(now)) {
        plans.add(
          _ReminderPlan(
            id: birthdayAdvanceId(birthday.id),
            title: '生日临近',
            body: '${birthday.name} 的生日还有 ${birthday.remindDaysBefore} 天',
            when: advance,
            schedule: _scheduleWeakReminder,
          ),
        );
      }
      if (remindAt.isAfter(now)) {
        plans.add(
          _ReminderPlan(
            id: birthdayDayId(birthday.id),
            title: '生日快乐',
            body: '今天是 ${birthday.name} 的生日',
            when: remindAt,
            schedule: _scheduleItemReminder,
          ),
        );
      }
    }

    final desiredIds = plans.map((plan) => plan.id).toSet();
    Object? firstError;
    StackTrace? firstStackTrace;
    void rememberError(Object error, StackTrace stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    Set<int>? pendingIds;
    Set<int>? activeIds;
    try {
      pendingIds = await _pendingNotificationIds();
    } catch (error, stackTrace) {
      rememberError(error, stackTrace);
    }
    try {
      activeIds = await _activeNotificationIds();
    } catch (error, stackTrace) {
      rememberError(error, stackTrace);
    }
    if (pendingIds != null && activeIds != null) {
      for (final id
          in pendingIds.difference(desiredIds).difference(activeIds)) {
        try {
          await _cancelNotification(id);
        } catch (error, stackTrace) {
          rememberError(error, stackTrace);
        }
      }
    }
    for (final plan in plans) {
      try {
        await plan.schedule(
          id: plan.id,
          title: plan.title,
          body: plan.body,
          when: plan.when,
        );
      } catch (error, stackTrace) {
        rememberError(error, stackTrace);
      }
    }
    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  Future<void> syncItem(ItemModel item) async {
    final actions = <Future<void> Function()>[
      () => _cancelNotification(itemId(item.id)),
      () => _cancelNotification(pendingId(item.id)),
    ];
    if (!itemHasActiveReminder(item)) {
      await _runBestEffort(actions);
      return;
    }

    if (item.startAt != null) {
      final when = item.startAt!.subtract(
        Duration(minutes: item.reminderMinutes),
      );
      actions.add(
        () => _scheduleItemReminder(
          id: itemId(item.id),
          title: item.title,
          body: item.location ?? '日程提醒',
          when: when,
        ),
      );
    }

    if (item.isPendingType &&
        item.status != 'done' &&
        item.nextFollowUpAt != null) {
      actions.add(
        () => _scheduleWeakReminder(
          id: pendingId(item.id),
          title: '关注：${item.title}',
          body: '悬而未决事项到了关注时间，点击查看进展',
          when: item.nextFollowUpAt!,
        ),
      );
    }
    await _runBestEffort(actions);
  }

  Future<void> syncBirthday(BirthdayModel b) async {
    final actions = <Future<void> Function()>[
      () => _cancelNotification(birthdayAdvanceId(b.id)),
      () => _cancelNotification(birthdayDayId(b.id)),
    ];
    if (b.isDeleted) {
      await _runBestEffort(actions);
      return;
    }

    final next = LunarDateHelper.nextSolarOccurrence(
      isLunar: b.isLunar,
      month: b.month,
      day: b.day,
      isLeapMonth: b.isLeapMonth,
    );
    if (next == null) {
      await _runBestEffort(actions);
      return;
    }

    final remindAt = DateTime(next.year, next.month, next.day, 9);
    final advance = remindAt.subtract(Duration(days: b.remindDaysBefore));

    if (advance.isAfter(DateTime.now())) {
      actions.add(
        () => _scheduleWeakReminder(
          id: birthdayAdvanceId(b.id),
          title: '生日临近',
          body: '${b.name} 的生日还有 ${b.remindDaysBefore} 天',
          when: advance,
        ),
      );
    }
    if (remindAt.isAfter(DateTime.now())) {
      actions.add(
        () => _scheduleItemReminder(
          id: birthdayDayId(b.id),
          title: '生日快乐',
          body: '今天是 ${b.name} 的生日',
          when: remindAt,
        ),
      );
    }
    await _runBestEffort(actions);
  }
}

/// Runs independent notification operations to completion and rethrows the
/// first error with its original stack trace after every operation has run.
Future<void> _runBestEffort(Iterable<Future<void> Function()> actions) async {
  Object? firstError;
  StackTrace? firstStackTrace;
  for (final action in actions) {
    try {
      await action();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStackTrace!);
  }
}

class _ReminderPlan {
  const _ReminderPlan({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.schedule,
  });

  final int id;
  final String title;
  final String body;
  final DateTime when;
  final ReminderScheduleAction schedule;
}
