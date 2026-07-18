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

typedef ReminderScheduleActionWithPayload =
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      required DateTime when,
      required String? payload,
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
    ReminderScheduleActionWithPayload? scheduleItemReminderWithPayload,
    ReminderScheduleActionWithPayload? scheduleWeakReminderWithPayload,
    DateTime Function()? now,
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
           NotificationService.instance.scheduleWeakReminder,
       _scheduleItemReminderWithPayload = scheduleItemReminder == null
           ? (scheduleItemReminderWithPayload ??
                 NotificationService.instance.scheduleItemReminderWithPayload)
           : scheduleItemReminderWithPayload,
       _scheduleWeakReminderWithPayload = scheduleWeakReminder == null
           ? (scheduleWeakReminderWithPayload ??
                 NotificationService.instance.scheduleWeakReminderWithPayload)
           : scheduleWeakReminderWithPayload,
       _now = now ?? DateTime.now;

  ReminderSyncService._() : this();
  static final ReminderSyncService instance = ReminderSyncService._();

  final Future<void> Function(int) _cancelNotification;
  final NotificationIdQuery _pendingNotificationIds;
  final NotificationIdQuery _activeNotificationIds;
  final ReminderScheduleAction _scheduleItemReminder;
  final ReminderScheduleAction _scheduleWeakReminder;
  final ReminderScheduleActionWithPayload? _scheduleItemReminderWithPayload;
  final ReminderScheduleActionWithPayload? _scheduleWeakReminderWithPayload;
  final DateTime Function() _now;

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
    final now = _now();

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
              scheduleWithPayload: _scheduleItemReminderWithPayload,
              payload: '/item/${Uri.encodeComponent(item.id)}',
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
            scheduleWithPayload: _scheduleWeakReminderWithPayload,
            payload: '/item/${Uri.encodeComponent(item.id)}',
          ),
        );
      }
    }

    for (final birthday in allBirthdays) {
      if (birthday.isDeleted) continue;
      final remindAt = _nextBirthdayReminderAt(birthday, now);
      if (remindAt == null) continue;
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
            scheduleWithPayload: _scheduleWeakReminderWithPayload,
            payload: '/birthdays',
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
            scheduleWithPayload: _scheduleItemReminderWithPayload,
            payload: '/birthdays',
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
        final scheduleWithPayload = plan.scheduleWithPayload;
        if (scheduleWithPayload != null) {
          await scheduleWithPayload(
            id: plan.id,
            title: plan.title,
            body: plan.body,
            when: plan.when,
            payload: plan.payload,
          );
        } else {
          await plan.schedule(
            id: plan.id,
            title: plan.title,
            body: plan.body,
            when: plan.when,
          );
        }
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
        () => _scheduleItem(
          id: itemId(item.id),
          title: item.title,
          body: item.location ?? '日程提醒',
          when: when,
          payload: '/item/${Uri.encodeComponent(item.id)}',
        ),
      );
    }

    if (item.isPendingType &&
        item.status != 'done' &&
        item.nextFollowUpAt != null) {
      actions.add(
        () => _scheduleWeak(
          id: pendingId(item.id),
          title: '关注：${item.title}',
          body: '悬而未决事项到了关注时间，点击查看进展',
          when: item.nextFollowUpAt!,
          payload: '/item/${Uri.encodeComponent(item.id)}',
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

    final now = _now();
    final remindAt = _nextBirthdayReminderAt(b, now);
    if (remindAt == null) {
      await _runBestEffort(actions);
      return;
    }

    final advance = remindAt.subtract(Duration(days: b.remindDaysBefore));

    if (advance.isAfter(now)) {
      actions.add(
        () => _scheduleWeak(
          id: birthdayAdvanceId(b.id),
          title: '生日临近',
          body: '${b.name} 的生日还有 ${b.remindDaysBefore} 天',
          when: advance,
          payload: '/birthdays',
        ),
      );
    }
    if (remindAt.isAfter(now)) {
      actions.add(
        () => _scheduleItem(
          id: birthdayDayId(b.id),
          title: '生日快乐',
          body: '今天是 ${b.name} 的生日',
          when: remindAt,
          payload: '/birthdays',
        ),
      );
    }
    await _runBestEffort(actions);
  }

  DateTime? _nextBirthdayReminderAt(BirthdayModel birthday, DateTime now) {
    final todayReminderAt = DateTime(now.year, now.month, now.day, 9);
    final occurrenceAfter = now.isBefore(todayReminderAt)
        ? DateTime(now.year, now.month, now.day - 1)
        : DateTime(now.year, now.month, now.day);
    final occurrence = LunarDateHelper.nextSolarOccurrence(
      isLunar: birthday.isLunar,
      month: birthday.month,
      day: birthday.day,
      isLeapMonth: birthday.isLeapMonth,
      after: occurrenceAfter,
    );
    if (occurrence == null) return null;
    return DateTime(occurrence.year, occurrence.month, occurrence.day, 9);
  }

  Future<void> _scheduleItem({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
  }) {
    final withPayload = _scheduleItemReminderWithPayload;
    if (withPayload != null) {
      return withPayload(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
      );
    }
    return _scheduleItemReminder(id: id, title: title, body: body, when: when);
  }

  Future<void> _scheduleWeak({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
  }) {
    final withPayload = _scheduleWeakReminderWithPayload;
    if (withPayload != null) {
      return withPayload(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
      );
    }
    return _scheduleWeakReminder(id: id, title: title, body: body, when: when);
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
    this.scheduleWithPayload,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime when;
  final ReminderScheduleAction schedule;
  final ReminderScheduleActionWithPayload? scheduleWithPayload;
  final String payload;
}
