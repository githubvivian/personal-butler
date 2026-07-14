import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/providers/app_state.dart';

void main() {
  group('AppState.bootstrap', () {
    test('runs the secure bootstrap steps in order', () async {
      final events = <String>[];
      final state = AppState(
        initializeNotifications: () async {
          events.add('notifications');
        },
        readInitialized: () async {
          events.add('initialized');
          return true;
        },
        validateSession: () async {
          events.add('session');
          return true;
        },
        syncReminders: () async {
          events.add('sync');
        },
      );

      await state.bootstrap();

      expect(events, ['notifications', 'initialized', 'session', 'sync']);
      expect(state.loading, isFalse);
      expect(state.initialized, isTrue);
      expect(state.unlocked, isTrue);
      expect(state.bootstrapError, isNull);
    });

    test('coalesces concurrent bootstraps and allows a later run', () async {
      final firstNotificationGate = Completer<void>();
      final secondNotificationGate = Completer<void>();
      var notificationAttempts = 0;
      var initializedReads = 0;
      var sessionValidations = 0;
      var reminderSyncs = 0;
      final state = AppState(
        initializeNotifications: () {
          notificationAttempts++;
          if (notificationAttempts == 1) {
            return firstNotificationGate.future;
          }
          if (notificationAttempts == 2) {
            return secondNotificationGate.future;
          }
          return Future<void>.value();
        },
        readInitialized: () async {
          initializedReads++;
          return true;
        },
        validateSession: () async {
          sessionValidations++;
          return true;
        },
        syncReminders: () async {
          reminderSyncs++;
        },
      );

      final firstRun = state.bootstrap();
      final secondRun = state.bootstrap();
      var secondRunCompleted = false;
      final observeSecondRun = secondRun.then((_) {
        secondRunCompleted = true;
      });
      final sameInFlightFuture = identical(firstRun, secondRun);
      final notificationAttemptsAfterStart = notificationAttempts;

      secondNotificationGate.complete();
      await Future<void>.delayed(Duration.zero);
      final secondRunCompletedWhileFirstPending = secondRunCompleted;
      final loadingWhileFirstPending = state.loading;
      final unlockedWhileFirstPending = state.unlocked;

      firstNotificationGate.complete();
      await Future.wait([firstRun, secondRun, observeSecondRun]);
      final attemptsAfterConcurrentRuns = (
        notifications: notificationAttempts,
        initialized: initializedReads,
        session: sessionValidations,
        sync: reminderSyncs,
      );

      final thirdRun = state.bootstrap();
      final thirdRunUsesNewFuture = !identical(thirdRun, firstRun);
      await thirdRun;

      expect(
        {
          'sameInFlightFuture': sameInFlightFuture,
          'notificationAttemptsAfterStart': notificationAttemptsAfterStart,
          'secondRunCompletedWhileFirstPending':
              secondRunCompletedWhileFirstPending,
          'loadingWhileFirstPending': loadingWhileFirstPending,
          'unlockedWhileFirstPending': unlockedWhileFirstPending,
          'attemptsAfterConcurrentRuns': attemptsAfterConcurrentRuns,
          'thirdRunUsesNewFuture': thirdRunUsesNewFuture,
          'attemptsAfterThirdRun': (
            notifications: notificationAttempts,
            initialized: initializedReads,
            session: sessionValidations,
            sync: reminderSyncs,
          ),
        },
        {
          'sameInFlightFuture': true,
          'notificationAttemptsAfterStart': 1,
          'secondRunCompletedWhileFirstPending': false,
          'loadingWhileFirstPending': true,
          'unlockedWhileFirstPending': false,
          'attemptsAfterConcurrentRuns': (
            notifications: 1,
            initialized: 1,
            session: 1,
            sync: 1,
          ),
          'thirdRunUsesNewFuture': true,
          'attemptsAfterThirdRun': (
            notifications: 2,
            initialized: 2,
            session: 2,
            sync: 2,
          ),
        },
      );
    });

    test(
      'coalesces bootstrap reentered synchronously from a listener',
      () async {
        final firstNotificationGate = Completer<void>();
        final secondNotificationGate = Completer<void>();
        var notificationAttempts = 0;
        final state = AppState(
          initializeNotifications: () {
            notificationAttempts++;
            return notificationAttempts == 1
                ? firstNotificationGate.future
                : secondNotificationGate.future;
          },
          readInitialized: () async => false,
          validateSession: () async => false,
          syncReminders: () async {},
        );

        Future<void>? reentrantRun;
        late void Function() listener;
        listener = () {
          state.removeListener(listener);
          reentrantRun = state.bootstrap();
        };
        state.addListener(listener);

        final outerRun = state.bootstrap();
        final capturedReentrantRun = reentrantRun;
        final sameInFlightFuture =
            capturedReentrantRun != null &&
            identical(outerRun, capturedReentrantRun);
        final notificationAttemptsAfterStart = notificationAttempts;

        firstNotificationGate.complete();
        secondNotificationGate.complete();
        await Future.wait([outerRun, ?capturedReentrantRun]);

        expect(
          {
            'capturedReentrantRun': capturedReentrantRun != null,
            'sameInFlightFuture': sameInFlightFuture,
            'notificationAttemptsAfterStart': notificationAttemptsAfterStart,
          },
          {
            'capturedReentrantRun': true,
            'sameInFlightFuture': true,
            'notificationAttemptsAfterStart': 1,
          },
        );
      },
    );

    test('bootstrap exception completes loading and fails closed', () async {
      final failure = StateError('secure storage unavailable');
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => throw failure,
        validateSession: () async => true,
        syncReminders: () async {},
      );

      await expectLater(state.bootstrap(), completes);

      expect(state.loading, isFalse);
      expect(state.unlocked, isFalse);
      expect(state.bootstrapError, same(failure));
    });

    test('retry clears the old error while loading and can succeed', () async {
      var notificationAttempts = 0;
      final retryGate = Completer<void>();
      final state = AppState(
        initializeNotifications: () async {
          notificationAttempts++;
          if (notificationAttempts == 1) {
            throw StateError('first failure');
          }
          await retryGate.future;
        },
        readInitialized: () async => true,
        validateSession: () async => true,
        syncReminders: () async {},
      );

      await state.bootstrap();
      expect(state.bootstrapError, isNotNull);

      final retry = state.bootstrap();
      expect(state.loading, isTrue);
      expect(state.bootstrapError, isNull);
      expect(state.unlocked, isFalse);

      retryGate.complete();
      await retry;

      expect(state.loading, isFalse);
      expect(state.bootstrapError, isNull);
      expect(state.initialized, isTrue);
      expect(state.unlocked, isTrue);
    });

    test('reminder sync exception also fails closed', () async {
      final events = <String>[];
      final failure = StateError('sync failed');
      final state = AppState(
        initializeNotifications: () async {
          events.add('notifications');
        },
        readInitialized: () async {
          events.add('initialized');
          return true;
        },
        validateSession: () async {
          events.add('session');
          return true;
        },
        syncReminders: () async {
          events.add('sync');
          throw failure;
        },
      );

      await expectLater(state.bootstrap(), completes);

      expect(events, ['notifications', 'initialized', 'session', 'sync']);
      expect(state.loading, isFalse);
      expect(state.unlocked, isFalse);
      expect(state.bootstrapError, same(failure));
    });
  });
}
