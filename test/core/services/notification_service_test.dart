import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/services/notification_service.dart';
import 'package:personal_butler/core/services/notification_navigation_controller.dart';

const _notificationChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const _timezoneChannel = MethodChannel('flutter_timezone');

void main() {
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_notificationChannel, null);
    messenger.setMockMethodCallHandler(_timezoneChannel, null);
    NotificationNavigationController.instance.clear();
  });

  group('scheduleExactAlarmWithPermissionFallback', () {
    test('uses exact scheduling once when it succeeds', () async {
      final modes = <AndroidScheduleMode>[];

      await scheduleExactAlarmWithPermissionFallback((mode) async {
        modes.add(mode);
      });

      expect(modes, [AndroidScheduleMode.exactAllowWhileIdle]);
    });

    test('falls back once when exact alarms are not permitted', () async {
      final modes = <AndroidScheduleMode>[];

      await scheduleExactAlarmWithPermissionFallback((mode) async {
        modes.add(mode);
        if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
          throw PlatformException(code: 'exact_alarms_not_permitted');
        }
      });

      expect(modes, [
        AndroidScheduleMode.exactAllowWhileIdle,
        AndroidScheduleMode.inexactAllowWhileIdle,
      ]);
    });

    test('rethrows other platform errors without retrying', () async {
      final modes = <AndroidScheduleMode>[];
      final error = PlatformException(code: 'another_platform_error');

      await expectLater(
        scheduleExactAlarmWithPermissionFallback((mode) async {
          modes.add(mode);
          throw error;
        }),
        throwsA(same(error)),
      );

      expect(modes, [AndroidScheduleMode.exactAllowWhileIdle]);
    });

    test('rethrows non-platform errors without retrying', () async {
      final modes = <AndroidScheduleMode>[];
      final error = StateError('scheduling failed');

      await expectLater(
        scheduleExactAlarmWithPermissionFallback((mode) async {
          modes.add(mode);
          throw error;
        }),
        throwsA(same(error)),
      );

      expect(modes, [AndroidScheduleMode.exactAllowWhileIdle]);
    });

    test('rethrows fallback errors without a third attempt', () async {
      final modes = <AndroidScheduleMode>[];
      final fallbackError = StateError('fallback failed');

      await expectLater(
        scheduleExactAlarmWithPermissionFallback((mode) async {
          modes.add(mode);
          if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
            throw PlatformException(code: 'exact_alarms_not_permitted');
          }
          throw fallbackError;
        }),
        throwsA(same(fallbackError)),
      );

      expect(modes, [
        AndroidScheduleMode.exactAllowWhileIdle,
        AndroidScheduleMode.inexactAllowWhileIdle,
      ]);
    });
  });

  test(
    'coalesces concurrent initialization and retries after failure',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final initializeGate = Completer<void>();
      var initializeCalls = 0;
      messenger.setMockMethodCallHandler(_timezoneChannel, (_) async {
        return 'Asia/Shanghai';
      });
      messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
        if (call.method == 'initialize') {
          initializeCalls++;
          if (initializeCalls == 1) {
            await initializeGate.future;
            throw StateError('notification initialization failed');
          }
          return true;
        }
        return null;
      });

      final service = NotificationService.forTesting();
      final first = service.init();
      final second = service.init();

      expect(identical(first, second), isTrue);
      initializeGate.complete();
      await expectLater(first, throwsA(isA<PlatformException>()));
      await expectLater(second, throwsA(isA<PlatformException>()));

      await service.init();
      expect(initializeCalls, 2);
    },
  );

  test(
    'captures a cold-start notification destination during initialization',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_timezoneChannel, (_) async {
        return 'Asia/Shanghai';
      });
      messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'getNotificationAppLaunchDetails') {
          return <String, Object?>{
            'notificationLaunchedApp': true,
            'notificationResponse': <String, Object?>{
              'notificationId': 1,
              'actionId': null,
              'input': null,
              'payload': '/item/cold-start-item',
              'notificationResponseType': 0,
            },
          };
        }
        return null;
      });

      await NotificationService.forTesting().init();

      expect(
        NotificationNavigationController.instance.takePendingLocation(),
        '/item/cold-start-item',
      );
    },
  );

  test(
    'pendingNotificationIds initializes and maps pending requests',
    () async {
      final methods = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_timezoneChannel, (_) async {
        return 'Asia/Shanghai';
      });
      messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
        methods.add(call.method);
        if (call.method == 'initialize') return true;
        if (call.method == 'pendingNotificationRequests') {
          return <Map<String, Object?>>[
            {'id': 7, 'title': 'first'},
            {'id': 11, 'title': 'second'},
          ];
        }
        return null;
      });

      final ids = await NotificationService.instance.pendingNotificationIds();

      expect(ids, {7, 11});
      expect(methods, contains('initialize'));
      expect(methods, contains('pendingNotificationRequests'));
      expect(methods, isNot(contains('requestNotificationsPermission')));
      expect(methods, isNot(contains('requestExactAlarmsPermission')));
    },
  );

  test(
    'activeNotificationIds ignores active notifications without ids',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_timezoneChannel, (_) async {
        return 'Asia/Shanghai';
      });
      messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'getActiveNotifications') {
          return <Map<String, Object?>>[
            {'id': 13, 'title': 'with id'},
            {'id': null, 'title': 'without id'},
          ];
        }
        return null;
      });

      final ids = await NotificationService.instance.activeNotificationIds();

      expect(ids, {13});
    },
  );

  test(
    'requestExactAlarmsPermission delegates only when explicitly called',
    () async {
      final methods = <String>[];
      final exactAlarmResponses = <bool?>[true, false, null];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_timezoneChannel, (_) async {
        return 'Asia/Shanghai';
      });
      messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
        methods.add(call.method);
        if (call.method == 'initialize') return true;
        if (call.method == 'requestExactAlarmsPermission') {
          return exactAlarmResponses.removeAt(0);
        }
        return null;
      });

      await NotificationService.instance.init();

      expect(methods, isNot(contains('requestExactAlarmsPermission')));

      for (final expected in <bool?>[true, false, null]) {
        final methodCountBeforeRequest = methods.length;

        final result = await NotificationService.instance
            .requestExactAlarmsPermission();

        expect(result, expected);
        expect(methods.sublist(methodCountBeforeRequest), [
          'requestExactAlarmsPermission',
        ]);
      }
    },
  );
}
