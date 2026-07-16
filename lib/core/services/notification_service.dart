import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

Future<void> scheduleExactAlarmWithPermissionFallback(
  Future<void> Function(AndroidScheduleMode mode) schedule,
) async {
  try {
    await schedule(AndroidScheduleMode.exactAllowWhileIdle);
  } on PlatformException catch (error) {
    if (error.code != 'exact_alarms_not_permitted') {
      rethrow;
    }
    await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
  }
}

class NotificationService {
  NotificationService._();

  @visibleForTesting
  NotificationService.forTesting() : this._();

  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _initFuture;

  Future<void> init() {
    if (_ready) return Future<void>.value();
    final inFlight = _initFuture;
    if (inFlight != null) return inFlight;

    final future = _initialize();
    _initFuture = future;
    future.then<void>(
      (_) => _clearInitFuture(future),
      onError: (Object error, StackTrace stackTrace) {
        _clearInitFuture(future);
      },
    );
    return future;
  }

  void _clearInitFuture(Future<void> future) {
    if (identical(_initFuture, future)) {
      _initFuture = null;
    }
  }

  Future<void> _initialize() async {
    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    const channelStrong = AndroidNotificationChannel(
      'personal_butler_reminders',
      '日程提醒',
      description: '会议、生日当天等强提醒',
      importance: Importance.high,
    );
    const channelWeak = AndroidNotificationChannel(
      'personal_butler_followups',
      '关注提醒',
      description: '悬而未决、生日临近等弱提醒',
      importance: Importance.defaultImportance,
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(channelStrong);
    await androidPlugin?.createNotificationChannel(channelWeak);

    _ready = true;
  }

  Future<bool?> requestAndroidPermission() async {
    if (!_ready) await init();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return androidPlugin?.requestNotificationsPermission();
  }

  Future<bool?> requestExactAlarmsPermission() async {
    if (!_ready) await init();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return androidPlugin?.requestExactAlarmsPermission();
  }

  Future<void> scheduleItemReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_ready) await init();
    if (!when.isAfter(DateTime.now())) return;

    await scheduleExactAlarmWithPermissionFallback(
      (androidScheduleMode) => _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'personal_butler_reminders',
            '日程提醒',
            channelDescription: '会议、生日当天等强提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: androidScheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      ),
    );
  }

  Future<void> scheduleWeakReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_ready) await init();
    if (!when.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'personal_butler_followups',
          '关注提醒',
          channelDescription: '悬而未决、生日临近等弱提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<Set<int>> pendingNotificationIds() async {
    if (!_ready) await init();
    final requests = await _plugin.pendingNotificationRequests();
    return requests.map((request) => request.id).toSet();
  }

  Future<Set<int>> activeNotificationIds() async {
    if (!_ready) await init();
    final notifications = await _plugin.getActiveNotifications();
    return {
      for (final notification in notifications)
        if (notification.id != null) notification.id!,
    };
  }

  Future<void> cancel(int id) => _plugin.cancel(id);
}
