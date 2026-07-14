import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/services/notification_service.dart';

void main() {
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
}
