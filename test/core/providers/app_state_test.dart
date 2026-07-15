import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/security/session_service.dart';

const _localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, null);
  });

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
      expect(state.initialized, isFalse);
      expect(state.unlocked, isFalse);
      expect(state.bootstrapError, same(failure));
    });

    test(
      'notification init failure still runs secure checks and unlocks',
      () async {
        final events = <String>[];
        final state = AppState(
          initializeNotifications: () async {
            events.add('notifications');
            throw StateError('notification init failed');
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

        await expectLater(state.bootstrap(), completes);

        expect(events, ['notifications', 'initialized', 'session', 'sync']);
        expect(state.loading, isFalse);
        expect(state.initialized, isTrue);
        expect(state.unlocked, isTrue);
        expect(state.bootstrapError, isNull);
      },
    );

    test('retry clears the old error while loading and can succeed', () async {
      var initializedReads = 0;
      final retryGate = Completer<void>();
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async {
          initializedReads++;
          if (initializedReads == 1) {
            throw StateError('first failure');
          }
          await retryGate.future;
          return true;
        },
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

    test('reminder sync exception does not relock a valid session', () async {
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
          throw StateError('sync failed');
        },
      );

      await expectLater(state.bootstrap(), completes);

      expect(events, ['notifications', 'initialized', 'session', 'sync']);
      expect(state.loading, isFalse);
      expect(state.initialized, isTrue);
      expect(state.unlocked, isTrue);
      expect(state.bootstrapError, isNull);
    });
  });

  group('AppState.unlock', () {
    test(
      'successful authentication unlocks and notifies when sync throws',
      () async {
        _setAuthenticationResult(true);
        var syncAttempts = 0;
        var notifications = 0;
        final state =
            AppState(
              syncReminders: () async {
                syncAttempts++;
                throw StateError('sync failed');
              },
            )..addListener(() {
              notifications++;
            });

        final result = await state.unlock();

        expect(result, isTrue);
        expect(state.unlocked, isTrue);
        expect(syncAttempts, 1);
        expect(notifications, 1);
      },
    );

    test('failed authentication does not sync reminders', () async {
      _setAuthenticationResult(false);
      var syncAttempts = 0;
      var notifications = 0;
      final state =
          AppState(
            syncReminders: () async {
              syncAttempts++;
            },
          )..addListener(() {
            notifications++;
          });

      final result = await state.unlock();

      expect(result, isFalse);
      expect(state.unlocked, isFalse);
      expect(syncAttempts, 0);
      expect(notifications, 1);
    });
  });

  group('AppState.lock', () {
    test(
      'fails closed immediately and waits for persisted session deletion',
      () async {
        final deletionGate = Completer<void>();
        final events = <String>[];
        var callbackSawLockedState = false;
        late final AppState state;
        state = AppState(
          initializeNotifications: () async {},
          readInitialized: () async => true,
          validateSession: () async => true,
          syncReminders: () async {},
          lockSession: () {
            events.add('delete-start');
            callbackSawLockedState =
                !state.unlocked && !SessionService.instance.isVaultSessionValid;
            return deletionGate.future;
          },
        );
        await state.bootstrap();
        SessionService.instance.unlockVault();
        var notifications = 0;
        state.addListener(() {
          notifications++;
          events.add('notify');
        });

        final lockFuture = state.lock();
        var completed = false;
        lockFuture.whenComplete(() {
          completed = true;
        });
        await Future<void>.delayed(Duration.zero);

        expect(state.unlocked, isFalse);
        expect(SessionService.instance.isVaultSessionValid, isFalse);
        expect(callbackSawLockedState, isTrue);
        expect(notifications, 1);
        expect(events, ['notify', 'delete-start']);
        expect(completed, isFalse);

        deletionGate.complete();
        await lockFuture;

        expect(completed, isTrue);
      },
    );

    test('remains locked and reports persisted deletion failure', () async {
      final failure = StateError('secure deletion failed');
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        validateSession: () async => true,
        syncReminders: () async {},
        lockSession: () async => throw failure,
      );
      await state.bootstrap();
      SessionService.instance.unlockVault();

      await expectLater(state.lock(), throwsA(same(failure)));

      expect(state.unlocked, isFalse);
      expect(SessionService.instance.isVaultSessionValid, isFalse);
    });
  });
}

void _setAuthenticationResult(bool result) {
  FlutterSecureStorage.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_localAuthChannel, (call) async {
        if (call.method == 'authenticate') return result;
        return null;
      });
}
