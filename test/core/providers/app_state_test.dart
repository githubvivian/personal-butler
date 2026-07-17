import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/security/session_service.dart';

const _localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SessionService.instance.clearSessionRevocationFailure();
  });

  tearDown(() {
    SessionService.instance.clearSessionRevocationFailure();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, null);
  });

  group('AppState.bootstrap', () {
    testWidgets('locks when the persisted session remaining time expires', (
      tester,
    ) async {
      var persistedLocks = 0;
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        readSessionRemainingLifetime: () async => const Duration(minutes: 15),
        syncReminders: () async {},
        lockSession: () async {
          persistedLocks++;
        },
      );

      await state.bootstrap();
      await _authenticateVault();
      var notifications = 0;
      state.addListener(() {
        notifications++;
      });

      await tester.pump(const Duration(minutes: 14, seconds: 59));
      expect(state.unlocked, isTrue);
      expect(persistedLocks, 0);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(state.unlocked, isFalse);
      expect(SessionService.instance.isVaultSessionValid, isFalse);
      expect(persistedLocks, 1);
      expect(notifications, 1);
      state.dispose();
    });

    testWidgets('bootstrap retry replaces the previous expiry timer', (
      tester,
    ) async {
      var lifetimeReads = 0;
      var persistedLocks = 0;
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        readSessionRemainingLifetime: () async {
          lifetimeReads++;
          return lifetimeReads == 1
              ? const Duration(minutes: 10)
              : const Duration(minutes: 20);
        },
        syncReminders: () async {},
        lockSession: () async {
          persistedLocks++;
        },
      );

      await state.bootstrap();
      await tester.pump(const Duration(minutes: 5));
      await state.bootstrap();

      await tester.pump(const Duration(minutes: 5));
      expect(state.unlocked, isTrue);
      expect(persistedLocks, 0);

      await tester.pump(const Duration(minutes: 15));
      await tester.pump();
      expect(state.unlocked, isFalse);
      expect(persistedLocks, 1);
      state.dispose();
    });

    testWidgets(
      'reminder synchronization cannot extend the persisted session lifetime',
      (tester) async {
        final syncStarted = Completer<void>();
        final syncGate = Completer<void>();
        var persistedLocks = 0;
        final state = AppState(
          initializeNotifications: () async {},
          readInitialized: () async => true,
          readSessionRemainingLifetime: () async => const Duration(minutes: 1),
          syncReminders: () {
            syncStarted.complete();
            return syncGate.future;
          },
          lockSession: () async {
            persistedLocks++;
          },
        );

        final bootstrap = state.bootstrap();
        await syncStarted.future;
        await tester.pump(const Duration(minutes: 1));
        await tester.pump();
        final locksBeforeSyncCompleted = persistedLocks;

        syncGate.complete();
        await bootstrap;

        expect(locksBeforeSyncCompleted, 1);
        expect(state.initialized, isTrue);
        expect(state.unlocked, isFalse);
        expect(state.loading, isFalse);
        state.dispose();
      },
    );

    testWidgets(
      'stale remaining-lifetime reads cannot replace a newer session timer',
      (tester) async {
        _setAuthenticationResult(true);
        final lifetimeReadStarted = Completer<void>();
        final lifetimeGate = Completer<Duration?>();
        var persistedLocks = 0;
        final state = AppState(
          initializeNotifications: () async {},
          readInitialized: () async => true,
          readSessionRemainingLifetime: () {
            lifetimeReadStarted.complete();
            return lifetimeGate.future;
          },
          syncReminders: () async {},
          lockSession: () async {
            persistedLocks++;
          },
        );

        final bootstrap = state.bootstrap();
        await lifetimeReadStarted.future;
        expect(await state.unlock(), isTrue);

        lifetimeGate.complete(const Duration(minutes: 1));
        await bootstrap;
        await tester.pump(const Duration(minutes: 1));
        await tester.pump();

        expect(state.unlocked, isTrue);
        expect(persistedLocks, 0);
        state.dispose();
      },
    );

    testWidgets('waits for in-flight deletion before restoring a session', (
      tester,
    ) async {
      _setAuthenticationResult(true);
      final deletionGate = Completer<void>();
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        syncReminders: () async {},
        lockSession: () async {
          await deletionGate.future;
          await SessionService.instance.lock();
        },
      );
      expect(await state.unlock(), isTrue);

      final lock = state.lock();
      final bootstrap = state.bootstrap();
      await tester.pump();
      deletionGate.complete();
      await Future.wait([lock, bootstrap]);

      expect(state.unlocked, isFalse);
      expect(await state.session.isSessionValid(), isFalse);
      state.dispose();
    });

    testWidgets(
      'bootstrap waits for stale authentication cleanup before reading the session',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final authenticationStarted = Completer<void>();
        final authenticationGate = Completer<bool>();
        final deletionStarted = Completer<void>();
        final deletionGate = Completer<void>();
        var initializedReads = 0;
        var lifetimeReads = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_localAuthChannel, (call) async {
              if (call.method == 'authenticate') {
                authenticationStarted.complete();
                return authenticationGate.future;
              }
              return null;
            });
        final state = AppState(
          initializeNotifications: () async {},
          readInitialized: () async {
            initializedReads++;
            return true;
          },
          readSessionRemainingLifetime: () async {
            lifetimeReads++;
            return SessionService.instance.getRemainingSessionLifetime();
          },
          syncReminders: () async {},
          lockSession: () async {
            await SessionService.instance.lock();
            deletionStarted.complete();
            await deletionGate.future;
          },
        );

        final unlock = state.unlock();
        await tester.pump();
        await authenticationStarted.future;

        final bootstrap = state.bootstrap();
        await tester.pump();
        await tester.pump();
        final readsBeforeAuthenticationCompleted = initializedReads;

        authenticationGate.complete(true);
        await deletionStarted.future;
        await tester.pump();
        final readsBeforeCleanupCompleted = initializedReads;

        deletionGate.complete();
        expect(await unlock, isFalse);
        await bootstrap;
        final finalUnlocked = state.unlocked;
        final persistedSessionValid = await state.session.isSessionValid();
        state.dispose();

        expect(readsBeforeAuthenticationCompleted, 0);
        expect(readsBeforeCleanupCompleted, 0);
        expect(initializedReads, 1);
        expect(lifetimeReads, 1);
        expect(finalUnlocked, isFalse);
        expect(persistedSessionValid, isFalse);
      },
    );

    testWidgets(
      'bootstrap stays locked when stale authentication cleanup deletion fails',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final authenticationStarted = Completer<void>();
        final authenticationGate = Completer<bool>();
        final deletionFailure = StateError('stale session deletion failed');
        var lifetimeReads = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_localAuthChannel, (call) async {
              if (call.method == 'authenticate') {
                authenticationStarted.complete();
                return authenticationGate.future;
              }
              return null;
            });
        final state = AppState(
          initializeNotifications: () async {},
          readInitialized: () async => true,
          readSessionRemainingLifetime: () async {
            lifetimeReads++;
            return SessionService.instance.getRemainingSessionLifetime();
          },
          syncReminders: () async {},
          lockSession: () async => throw deletionFailure,
        );

        final unlock = state.unlock();
        await tester.pump();
        await authenticationStarted.future;
        final bootstrap = state.bootstrap();

        authenticationGate.complete(true);
        expect(await unlock, isFalse);
        await bootstrap;
        final finalUnlocked = state.unlocked;
        final bootstrapError = state.bootstrapError;
        state.dispose();

        expect(finalUnlocked, isFalse);
        expect(bootstrapError, same(deletionFailure));
        expect(lifetimeReads, 0);
      },
    );

    testWidgets(
      'bootstrap retry clears a transient revocation failure after deletion succeeds',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        await SessionService.instance.markUnlocked();
        final deletionFailure = StateError('transient session deletion failed');
        var deletionCalls = 0;
        final state = AppState(
          initializeNotifications: () async {},
          readInitialized: () async => true,
          readSessionRemainingLifetime:
              SessionService.instance.getRemainingSessionLifetime,
          syncReminders: () async {},
          lockSession: () async {
            deletionCalls++;
            if (deletionCalls == 1) throw deletionFailure;
            await SessionService.instance.lock();
          },
        );

        await expectLater(state.lock(), throwsA(same(deletionFailure)));
        await state.bootstrap();
        final finalUnlocked = state.unlocked;
        final bootstrapError = state.bootstrapError;
        final persistedSessionValid = await state.session.isSessionValid();
        state.dispose();

        expect(deletionCalls, 2);
        expect(bootstrapError, isNull);
        expect(finalUnlocked, isFalse);
        expect(persistedSessionValid, isFalse);
      },
    );

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

  group('AppState.setupFirstRun', () {
    testWidgets('manual lock invalidates authentication still in progress', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      final authenticationGate = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            if (call.method == 'authenticate') {
              return authenticationGate.future;
            }
            return null;
          });
      final state = AppState(
        markSessionInitialized: () async {},
        syncReminders: () async {},
      );

      final setup = state.setupFirstRun();
      await tester.pump();
      await state.lock();
      authenticationGate.complete(true);
      await tester.pump();

      expect(await setup, isFalse);
      expect(state.initialized, isFalse);
      expect(state.unlocked, isFalse);
      expect(await state.session.isSessionValid(), isFalse);
      state.dispose();
    });

    testWidgets(
      'initialization work cannot extend a newly authenticated session',
      (tester) async {
        _setAuthenticationResult(true);
        final initializationStarted = Completer<void>();
        final initializationGate = Completer<void>();
        var persistedLocks = 0;
        final state = AppState(
          markSessionInitialized: () {
            initializationStarted.complete();
            return initializationGate.future;
          },
          syncReminders: () async {},
          lockSession: () async {
            persistedLocks++;
          },
        );

        final setup = state.setupFirstRun();
        await initializationStarted.future;
        await tester.pump(AppState.sessionLifetime);
        await tester.pump();
        final locksBeforeInitializationCompleted = persistedLocks;

        initializationGate.complete();
        final result = await setup;

        expect(locksBeforeInitializationCompleted, 1);
        expect(result, isFalse);
        expect(state.initialized, isFalse);
        expect(state.unlocked, isFalse);
        state.dispose();
      },
    );

    testWidgets(
      'disposed setup cleans persisted authentication after initialization fails',
      (tester) async {
        _setAuthenticationResult(true);
        final initializationStarted = Completer<void>();
        final initializationGate = Completer<void>();
        final failure = StateError('initialization failed');
        var persistedLocks = 0;
        final state = AppState(
          markSessionInitialized: () {
            initializationStarted.complete();
            return initializationGate.future;
          },
          syncReminders: () async {},
          lockSession: () async {
            persistedLocks++;
          },
        );

        final setup = state.setupFirstRun();
        await initializationStarted.future;
        state.dispose();
        initializationGate.completeError(failure);

        await expectLater(setup, throwsA(same(failure)));
        expect(persistedLocks, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('successful setup schedules a full new session lifetime', (
      tester,
    ) async {
      _setAuthenticationResult(true);
      var persistedLocks = 0;
      final state = AppState(
        syncReminders: () async {},
        lockSession: () async {
          persistedLocks++;
        },
      );

      expect(await state.setupFirstRun(), isTrue);

      await tester.pump(AppState.sessionLifetime - const Duration(seconds: 1));
      expect(state.unlocked, isTrue);
      expect(persistedLocks, 0);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(state.unlocked, isFalse);
      expect(persistedLocks, 1);
      state.dispose();
    });
  });

  group('AppState.unlock', () {
    testWidgets('a queued unlock is invalidated by an immediate manual lock', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      var authenticationCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            if (call.method == 'authenticate') {
              authenticationCalls++;
              return true;
            }
            return null;
          });
      final state = AppState(syncReminders: () async {});

      final unlock = state.unlock();
      await state.lock();
      await tester.pump();

      expect(await unlock, isFalse);
      expect(authenticationCalls, 0);
      expect(state.unlocked, isFalse);
      state.dispose();
    });

    testWidgets('serializes concurrent authentication attempts', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      final firstAuthentication = Completer<bool>();
      final secondAuthentication = Completer<bool>();
      var authenticationCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            if (call.method != 'authenticate') return null;
            authenticationCalls++;
            return authenticationCalls == 1
                ? firstAuthentication.future
                : secondAuthentication.future;
          });
      final state = AppState(syncReminders: () async {});

      final first = state.unlock();
      await tester.pump();
      final second = state.unlock();
      await tester.pump();
      final callsWhileFirstWasPending = authenticationCalls;

      firstAuthentication.complete(false);
      await tester.pump();
      expect(await first, isFalse);
      await tester.pump();
      final callsAfterFirstCompleted = authenticationCalls;

      secondAuthentication.complete(false);
      await tester.pump();
      expect(await second, isFalse);

      expect(callsWhileFirstWasPending, 1);
      expect(callsAfterFirstCompleted, 2);
      state.dispose();
    });

    testWidgets('stale authentication waits for session cleanup', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      final authenticationGate = Completer<bool>();
      final deletionGate = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            if (call.method == 'authenticate') {
              return authenticationGate.future;
            }
            return null;
          });
      final state = AppState(
        syncReminders: () async {},
        lockSession: () => deletionGate.future,
      );
      var unlockCompleted = false;

      final unlock = state.unlock();
      unlock.whenComplete(() => unlockCompleted = true);
      await tester.pump();
      final lock = state.lock();
      await tester.pump();

      authenticationGate.complete(true);
      await tester.pump();
      await tester.pump();

      expect(unlockCompleted, isFalse);

      deletionGate.complete();
      await lock;
      expect(await unlock, isFalse);
      state.dispose();
    });

    testWidgets(
      'stale authentication deletes a timestamp written after an older deletion',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final authenticationGate = Completer<bool>();
        final firstDeletionCompleted = Completer<void>();
        final deletionRelease = Completer<void>();
        var deletionCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_localAuthChannel, (call) async {
              if (call.method == 'authenticate') {
                return authenticationGate.future;
              }
              return null;
            });
        final state = AppState(
          syncReminders: () async {},
          lockSession: () async {
            deletionCalls++;
            await SessionService.instance.lock();
            if (!firstDeletionCompleted.isCompleted) {
              firstDeletionCompleted.complete();
            }
            await deletionRelease.future;
          },
        );

        final unlock = state.unlock();
        await tester.pump();
        final lock = state.lock();
        await firstDeletionCompleted.future;
        authenticationGate.complete(true);
        await tester.pump();
        await tester.pump();

        deletionRelease.complete();
        await lock;
        expect(await unlock, isFalse);

        expect(deletionCalls, 2);
        expect(await state.session.isSessionValid(), isFalse);
        state.dispose();
      },
    );

    testWidgets(
      'reminder synchronization cannot extend a newly authenticated session',
      (tester) async {
        _setAuthenticationResult(true);
        final syncStarted = Completer<void>();
        final syncGate = Completer<void>();
        var persistedLocks = 0;
        final state = AppState(
          syncReminders: () {
            syncStarted.complete();
            return syncGate.future;
          },
          lockSession: () async {
            persistedLocks++;
          },
        );

        final unlock = state.unlock();
        await syncStarted.future;
        await tester.pump(AppState.sessionLifetime);
        await tester.pump();
        final locksBeforeSyncCompleted = persistedLocks;

        syncGate.complete();
        final result = await unlock;

        expect(locksBeforeSyncCompleted, 1);
        expect(result, isFalse);
        expect(state.unlocked, isFalse);
        state.dispose();
      },
    );

    testWidgets(
      'waits for an in-flight expiry deletion before authenticating again',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final deletionGate = Completer<void>();
        var authenticationCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_localAuthChannel, (call) async {
              if (call.method == 'authenticate') {
                authenticationCalls++;
                return true;
              }
              return null;
            });
        final state = AppState(
          initializeNotifications: () async {},
          readInitialized: () async => true,
          readSessionRemainingLifetime: () async => const Duration(minutes: 1),
          syncReminders: () async {},
          lockSession: () => deletionGate.future,
        );
        await state.bootstrap();
        Future<bool>? unlock;
        state.addListener(() {
          if (!state.unlocked && unlock == null) {
            unlock = state.unlock();
          }
        });

        await tester.pump(const Duration(minutes: 1));
        await tester.pump();

        expect(state.unlocked, isFalse);
        expect(unlock, isNotNull);
        expect(authenticationCalls, 0);

        deletionGate.complete();
        await tester.pump();
        expect(await unlock!, isTrue);

        expect(authenticationCalls, 1);
        expect(state.unlocked, isTrue);
        expect(await state.session.isSessionValid(), isTrue);
        state.dispose();
      },
    );

    testWidgets('successful re-unlock replaces the previous expiry timer', (
      tester,
    ) async {
      _setAuthenticationResult(true);
      var persistedLocks = 0;
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        readSessionRemainingLifetime: () async => const Duration(minutes: 10),
        syncReminders: () async {},
        lockSession: () async {
          persistedLocks++;
        },
      );
      await state.bootstrap();
      await tester.pump(const Duration(minutes: 5));

      expect(await state.unlock(), isTrue);

      await tester.pump(const Duration(minutes: 5));
      expect(state.unlocked, isTrue);
      expect(persistedLocks, 0);

      await tester.pump(AppState.sessionLifetime - const Duration(minutes: 5));
      await tester.pump();
      expect(state.unlocked, isFalse);
      expect(persistedLocks, 1);
      state.dispose();
    });

    testWidgets(
      'successful unlock expires at the authenticated session remaining lifetime',
      (tester) async {
        _setAuthenticationResult(true);
        var persistedLocks = 0;
        final state = AppState(
          readAuthenticatedSessionRemainingLifetime: () async =>
              const Duration(hours: 1, minutes: 59),
          syncReminders: () async {},
          lockSession: () async {
            persistedLocks++;
          },
        );

        expect(await state.unlock(), isTrue);

        await tester.pump(const Duration(hours: 1, minutes: 58, seconds: 59));
        expect(state.unlocked, isTrue);
        expect(persistedLocks, 0);

        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        final unlockedAtAuthenticatedExpiry = state.unlocked;
        final locksAtAuthenticatedExpiry = persistedLocks;
        state.dispose();

        expect(unlockedAtAuthenticatedExpiry, isFalse);
        expect(locksAtAuthenticatedExpiry, 1);
      },
    );

    testWidgets(
      'authenticated lifetime completion cannot revive a concurrently locked session',
      (tester) async {
        _setAuthenticationResult(true);
        final authenticatedLifetimeStarted = Completer<void>();
        final authenticatedLifetimeGate = Completer<Duration?>();
        final concurrentLockStarted = Completer<void>();
        Future<void>? concurrentLock;
        var deletionCalls = 0;
        final state = AppState(
          readAuthenticatedSessionRemainingLifetime: () {
            authenticatedLifetimeStarted.complete();
            return authenticatedLifetimeGate.future;
          },
          syncReminders: () async {},
          lockSession: () async {
            deletionCalls++;
            await SessionService.instance.lock();
          },
        );

        final unlock = state.unlock();
        await authenticatedLifetimeStarted.future;
        unawaited(
          authenticatedLifetimeGate.future.then<void>((_) {
            concurrentLock = state.lock();
            concurrentLockStarted.complete();
          }),
        );

        authenticatedLifetimeGate.complete(
          const Duration(hours: 1, minutes: 59),
        );
        await concurrentLockStarted.future;
        final unlockResult = await unlock;
        await concurrentLock;
        final finalUnlocked = state.unlocked;
        final persistedSessionValid = await state.session.isSessionValid();
        state.dispose();

        expect(unlockResult, isFalse);
        expect(finalUnlocked, isFalse);
        expect(persistedSessionValid, isFalse);
        expect(deletionCalls, 2);
      },
    );

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
    testWidgets(
      'registers deletion before notifying a reentrant unlock listener',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final deletionGate = Completer<void>();
        var authenticationCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_localAuthChannel, (call) async {
              if (call.method == 'authenticate') {
                authenticationCalls++;
                return true;
              }
              return null;
            });
        final state = AppState(
          initializeNotifications: () async {},
          readInitialized: () async => true,
          readSessionRemainingLifetime: () async => const Duration(minutes: 10),
          syncReminders: () async {},
          lockSession: () => deletionGate.future,
        );
        await state.bootstrap();
        Future<bool>? unlock;
        state.addListener(() {
          if (!state.unlocked && unlock == null) {
            unlock = state.unlock();
          }
        });

        final lock = state.lock();
        await tester.pump();

        expect(unlock, isNotNull);
        expect(authenticationCalls, 0);
        expect(state.unlocked, isFalse);

        deletionGate.complete();
        await lock;
        await tester.pump();
        expect(await unlock!, isTrue);
        expect(authenticationCalls, 1);
        state.dispose();
      },
    );

    testWidgets('manual lock cancels the pending expiry callback', (
      tester,
    ) async {
      var persistedLocks = 0;
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        readSessionRemainingLifetime: () async => const Duration(minutes: 10),
        syncReminders: () async {},
        lockSession: () async {
          persistedLocks++;
        },
      );
      await state.bootstrap();
      var notifications = 0;
      state.addListener(() {
        notifications++;
      });

      await state.lock();
      await tester.pump(const Duration(minutes: 10));
      await tester.pump();

      expect(state.unlocked, isFalse);
      expect(persistedLocks, 1);
      expect(notifications, 1);
      state.dispose();
    });

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
        await _authenticateVault();
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
        expect(events, ['delete-start', 'notify']);
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
      await _authenticateVault();

      await expectLater(state.lock(), throwsA(same(failure)));

      expect(state.unlocked, isFalse);
      expect(SessionService.instance.isVaultSessionValid, isFalse);
    });
  });

  group('AppState.revalidateSession', () {
    testWidgets('invalid persisted session fails closed', (tester) async {
      var lifetimeReads = 0;
      var persistedLocks = 0;
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        readSessionRemainingLifetime: () async {
          lifetimeReads++;
          return lifetimeReads == 1 ? const Duration(minutes: 10) : null;
        },
        syncReminders: () async {},
        lockSession: () async {
          persistedLocks++;
        },
      );
      await state.bootstrap();
      await _authenticateVault();
      var notifications = 0;
      state.addListener(() {
        notifications++;
      });

      expect(await state.revalidateSession(), isFalse);
      await tester.pump();

      expect(state.unlocked, isFalse);
      expect(SessionService.instance.isVaultSessionValid, isFalse);
      expect(persistedLocks, 1);
      expect(notifications, 1);
      state.dispose();
    });

    testWidgets('validation and deletion exceptions still fail closed', (
      tester,
    ) async {
      var lifetimeReads = 0;
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        readSessionRemainingLifetime: () async {
          lifetimeReads++;
          if (lifetimeReads == 1) return const Duration(minutes: 10);
          throw StateError('secure storage read failed');
        },
        syncReminders: () async {},
        lockSession: () async => throw StateError('secure deletion failed'),
      );
      await state.bootstrap();
      await _authenticateVault();

      expect(await state.revalidateSession(), isFalse);
      await tester.pump();

      expect(state.unlocked, isFalse);
      expect(SessionService.instance.isVaultSessionValid, isFalse);
      expect(tester.takeException(), isNull);
      state.dispose();
    });

    testWidgets('valid result replaces the timer with latest remaining time', (
      tester,
    ) async {
      var lifetimeReads = 0;
      var persistedLocks = 0;
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        readSessionRemainingLifetime: () async {
          lifetimeReads++;
          return lifetimeReads == 1
              ? const Duration(minutes: 10)
              : const Duration(minutes: 20);
        },
        syncReminders: () async {},
        lockSession: () async {
          persistedLocks++;
        },
      );
      await state.bootstrap();
      await tester.pump(const Duration(minutes: 5));

      expect(await state.revalidateSession(), isTrue);

      await tester.pump(const Duration(minutes: 5));
      expect(state.unlocked, isTrue);
      expect(persistedLocks, 0);

      await tester.pump(const Duration(minutes: 15));
      await tester.pump();
      expect(state.unlocked, isFalse);
      expect(persistedLocks, 1);
      state.dispose();
    });

    testWidgets('coalesces concurrent validation reads', (tester) async {
      final validationGate = Completer<Duration?>();
      var lifetimeReads = 0;
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        readSessionRemainingLifetime: () {
          lifetimeReads++;
          return lifetimeReads == 1
              ? Future<Duration?>.value(const Duration(minutes: 10))
              : validationGate.future;
        },
        syncReminders: () async {},
      );
      await state.bootstrap();

      final first = state.revalidateSession();
      final second = state.revalidateSession();

      expect(identical(first, second), isTrue);
      expect(lifetimeReads, 2);

      validationGate.complete(const Duration(minutes: 20));
      expect(await first, isTrue);
      expect(await second, isTrue);
      state.dispose();
    });

    testWidgets(
      'new session starts a fresh revalidation while an older read is pending',
      (tester) async {
        _setAuthenticationResult(true);
        final oldValidationGate = Completer<Duration?>();
        var lifetimeReads = 0;
        final state = AppState(
          initializeNotifications: () async {},
          readInitialized: () async => true,
          readSessionRemainingLifetime: () {
            lifetimeReads++;
            return switch (lifetimeReads) {
              1 => Future<Duration?>.value(const Duration(minutes: 10)),
              2 => oldValidationGate.future,
              _ => Future<Duration?>.value(const Duration(minutes: 20)),
            };
          },
          syncReminders: () async {},
          lockSession: () async {},
        );
        await state.bootstrap();

        final oldValidation = state.revalidateSession();
        await state.lock();
        expect(await state.unlock(), isTrue);

        final newValidation = state.revalidateSession();

        expect(lifetimeReads, 3);
        expect(await newValidation, isTrue);

        oldValidationGate.complete(null);
        await oldValidation;
        await tester.pump();

        final newSessionStayedUnlocked = state.unlocked;
        state.dispose();

        expect(newSessionStayedUnlocked, isTrue);
      },
    );

    testWidgets('stale invalid result cannot lock a newly unlocked session', (
      tester,
    ) async {
      _setAuthenticationResult(true);
      final validationGate = Completer<Duration?>();
      var lifetimeReads = 0;
      final state = AppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        readSessionRemainingLifetime: () {
          lifetimeReads++;
          return lifetimeReads == 1
              ? Future<Duration?>.value(const Duration(minutes: 10))
              : validationGate.future;
        },
        syncReminders: () async {},
      );
      await state.bootstrap();

      final validation = state.revalidateSession();
      expect(await state.unlock(), isTrue);
      validationGate.complete(null);
      await validation;

      expect(state.unlocked, isTrue);
      await tester.pump(const Duration(minutes: 10));
      expect(state.unlocked, isTrue);
      state.dispose();
    });
  });

  group('AppState session lifecycle', () {
    testWidgets(
      'deactivation waits for delayed authentication cancellation before reactivation',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final firstAuthenticationStarted = Completer<void>();
        final firstAuthentication = Completer<bool>();
        final secondAuthenticationStarted = Completer<void>();
        final secondAuthentication = Completer<bool>();
        final cancellationStarted = Completer<void>();
        final cancellationGate = Completer<bool>();
        var authenticationCalls = 0;
        var cancellationCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_localAuthChannel, (call) async {
              if (call.method == 'authenticate') {
                authenticationCalls++;
                if (authenticationCalls == 1) {
                  firstAuthenticationStarted.complete();
                  return firstAuthentication.future;
                }
                secondAuthenticationStarted.complete();
                return secondAuthentication.future;
              }
              if (call.method == 'stopAuthentication') {
                cancellationCalls++;
                cancellationStarted.complete();
                return cancellationGate.future;
              }
              return null;
            });
        final state = AppState(syncReminders: () async {});

        final firstUnlock = state.unlock();
        await tester.pump();
        await firstAuthenticationStarted.future;

        final deactivation = state.deactivateSessionLifecycle();
        var activationCompleted = false;
        final activation = state.activateSessionLifecycle()
          ..then((_) => activationCompleted = true);
        final secondUnlock = activation.then((_) => state.unlock());
        await tester.pump();
        await cancellationStarted.future;

        firstAuthentication.complete(false);
        await tester.pump();
        await tester.pump();
        final activatedBeforeCancellationCompleted = activationCompleted;
        final callsBeforeCancellationCompleted = authenticationCalls;

        cancellationGate.complete(true);
        await activation;
        await tester.pump();
        await secondAuthenticationStarted.future;
        secondAuthentication.complete(false);

        expect(await firstUnlock, isFalse);
        expect(await secondUnlock, isFalse);
        await deactivation;
        state.dispose();

        expect(activatedBeforeCancellationCompleted, isFalse);
        expect(callsBeforeCancellationCompleted, 1);
        expect(cancellationCalls, 1);
      },
    );

    testWidgets(
      'deactivation skips biometric cancellation when no authentication is pending',
      (tester) async {
        final cancellationGate = Completer<bool>();
        var cancellationCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_localAuthChannel, (call) async {
              if (call.method == 'stopAuthentication') {
                cancellationCalls++;
                return cancellationGate.future;
              }
              return null;
            });
        final state = AppState(syncReminders: () async {});

        final deactivation = state.deactivateSessionLifecycle();
        await tester.pump();
        await deactivation;
        final callsWithoutAuthentication = cancellationCalls;

        if (!cancellationGate.isCompleted) cancellationGate.complete(true);
        state.dispose();

        expect(callsWithoutAuthentication, 0);
      },
    );
  });

  group('AppState.dispose', () {
    testWidgets('cancels expiry without late notification or deletion', (
      tester,
    ) async {
      var persistedLocks = 0;
      var notifications = 0;
      final state =
          AppState(
            initializeNotifications: () async {},
            readInitialized: () async => true,
            readSessionRemainingLifetime: () async =>
                const Duration(minutes: 10),
            syncReminders: () async {},
            lockSession: () async {
              persistedLocks++;
            },
          )..addListener(() {
            notifications++;
          });
      await state.bootstrap();
      notifications = 0;

      state.dispose();
      await tester.pump(const Duration(minutes: 10));
      await tester.pump();

      expect(notifications, 0);
      expect(persistedLocks, 0);
      expect(tester.takeException(), isNull);
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

Future<VaultSessionCapability> _authenticateVault() async {
  _setAuthenticationResult(true);
  final capability = await SessionService.instance.authenticateVault(
    reason: 'Test vault',
  );
  expect(capability, isNotNull);
  return capability!;
}
