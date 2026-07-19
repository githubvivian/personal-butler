import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:personal_butler/app.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/security/session_service.dart';
import 'package:personal_butler/features/auth/lock_screen.dart';
import 'package:personal_butler/features/inbox/gallery_picker_screen.dart';
import 'package:personal_butler/features/inbox/inbox_screen.dart';
import 'package:personal_butler/features/shell/main_shell.dart';

const _localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

void main() {
  tearDown(() {
    PhotoManager.withPlugin(PhotoManagerPlugin());
    SessionService.instance.clearSessionRevocationFailure();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, null);
  });

  testWidgets('pending bootstrap only shows the startup loading screen', (
    tester,
  ) async {
    final bootstrapGate = Completer<void>();
    final appState = _TrackingAppState(
      initializeNotifications: () => bootstrapGate.future,
      readInitialized: () async => false,
      validateSession: () async => false,
      syncReminders: () async {},
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('startup-loading-screen')), findsOneWidget);
    expect(find.text('正在安全启动…'), findsOneWidget);
    expect(find.byType(InboxScreen), findsNothing);
    expect(find.byType(MainShell), findsNothing);
    expect(find.byType(LockScreen), findsNothing);
    expect(appState.setupFirstRunAttempts, 0);
    expect(appState.unlockAttempts, 0);
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first run routes to setup without session validation or sync', (
    tester,
  ) async {
    var validateSessionAttempts = 0;
    var syncRemindersAttempts = 0;
    final appState = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => false,
      validateSession: () async {
        validateSessionAttempts++;
        return true;
      },
      syncReminders: () async {
        syncRemindersAttempts++;
      },
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(InboxScreen), findsNothing);
    expect(find.byType(MainShell), findsNothing);
    expect(appState.setupFirstRunAttempts, 1);
    expect(appState.unlockAttempts, 0);
    expect(validateSessionAttempts, 0);
    expect(syncRemindersAttempts, 0);
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid session syncs once and routes directly to the inbox', (
    tester,
  ) async {
    var validateSessionAttempts = 0;
    var syncRemindersAttempts = 0;
    final appState = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async {
        validateSessionAttempts++;
        return true;
      },
      syncReminders: () async {
        syncRemindersAttempts++;
      },
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.byType(LockScreen), findsNothing);
    expect(validateSessionAttempts, 1);
    expect(syncRemindersAttempts, 1);
    expect(appState.setupFirstRunAttempts, 0);
    expect(appState.unlockAttempts, 0);
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume with an invalid session fails closed', (tester) async {
    var lifetimeReads = 0;
    var persistedLocks = 0;
    final appState = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async => false,
      readSessionRemainingLifetime: () async {
        lifetimeReads++;
        return lifetimeReads == 1 ? const Duration(minutes: 10) : null;
      },
      syncReminders: () async {},
      lockSession: () async {
        persistedLocks++;
      },
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);
    expect(find.byType(InboxScreen), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpFrames(tester);

    expect(lifetimeReads, 2);
    expect(persistedLocks, 1);
    expect(appState.unlocked, isFalse);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(InboxScreen).hitTestable(), findsNothing);
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume validation exception also fails closed', (tester) async {
    var lifetimeReads = 0;
    final appState = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async => false,
      readSessionRemainingLifetime: () async {
        lifetimeReads++;
        if (lifetimeReads == 1) return const Duration(minutes: 10);
        throw StateError('secure storage unavailable');
      },
      syncReminders: () async {},
      lockSession: () async => throw StateError('secure deletion failed'),
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);
    expect(find.byType(InboxScreen), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpFrames(tester);

    expect(lifetimeReads, 2);
    expect(appState.unlocked, isFalse);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(InboxScreen).hitTestable(), findsNothing);
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the app does not dispose an injected AppState', (
    tester,
  ) async {
    var lifetimeReads = 0;
    var persistedLocks = 0;
    final appState = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async => false,
      readSessionRemainingLifetime: () async {
        lifetimeReads++;
        return const Duration(minutes: 10);
      },
      syncReminders: () async {},
      lockSession: () async {
        persistedLocks++;
      },
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);
    await tester.pumpWidget(const SizedBox.shrink());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 10));
    await tester.pump();

    expect(appState.disposeAttempts, 0);
    expect(lifetimeReads, 1);
    expect(persistedLocks, 0);
    appState.dispose();
    expect(appState.disposeAttempts, 1);
  });

  testWidgets('rebinds lifecycle handling to a replacement injected AppState', (
    tester,
  ) async {
    var firstLifetimeReads = 0;
    var secondLifetimeReads = 0;
    final first = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async => false,
      readSessionRemainingLifetime: () async {
        firstLifetimeReads++;
        return const Duration(minutes: 10);
      },
      syncReminders: () async {},
    );
    final second = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async => false,
      readSessionRemainingLifetime: () async {
        secondLifetimeReads++;
        return const Duration(minutes: 10);
      },
      syncReminders: () async {},
    );

    await tester.pumpWidget(PersonalButlerApp(appState: first));
    await _pumpFrames(tester);
    await tester.pumpWidget(PersonalButlerApp(appState: second));
    await _pumpFrames(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpFrames(tester);

    expect(firstLifetimeReads, 1);
    expect(secondLifetimeReads, 2);
    expect(first.disposeAttempts, 0);
    expect(second.disposeAttempts, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    second.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replacement injected AppState cancels the previous session expiry',
    (tester) async {
      var firstPersistedLocks = 0;
      var secondPersistedLocks = 0;
      final first = _TrackingAppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        validateSession: () async => false,
        readSessionRemainingLifetime: () async => const Duration(minutes: 1),
        syncReminders: () async {},
        lockSession: () async {
          firstPersistedLocks++;
        },
      );
      final second = _TrackingAppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        validateSession: () async => false,
        readSessionRemainingLifetime: () async => const Duration(minutes: 10),
        syncReminders: () async {},
        lockSession: () async {
          secondPersistedLocks++;
        },
      );

      await tester.pumpWidget(PersonalButlerApp(appState: first));
      await _pumpFrames(tester);
      await tester.pumpWidget(PersonalButlerApp(appState: second));
      await _pumpFrames(tester);

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      final firstLocksAfterOriginalExpiry = firstPersistedLocks;
      final secondStillUnlocked = second.unlocked;
      final secondLocksAfterOriginalExpiry = secondPersistedLocks;

      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      second.dispose();
      await tester.pump();

      expect(firstLocksAfterOriginalExpiry, 0);
      expect(secondStillUnlocked, isTrue);
      expect(secondLocksAfterOriginalExpiry, 0);
      expect(first.disposeAttempts, 1);
      expect(second.disposeAttempts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacement waits for old authentication cleanup without late LockScreen setState',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final authenticationStarted = Completer<void>();
      final authenticationGate = Completer<bool>();
      final deletionStarted = Completer<void>();
      final deletionGate = Completer<void>();
      final secondBootstrapStarted = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            if (call.method == 'authenticate') {
              authenticationStarted.complete();
              return authenticationGate.future;
            }
            if (call.method == 'stopAuthentication') return true;
            return null;
          });
      final first = _TrackingAppState(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        validateSession: () async => false,
        readSessionRemainingLifetime: () async => null,
        syncReminders: () async {},
        lockSession: () async {
          await SessionService.instance.lock();
          deletionStarted.complete();
          await deletionGate.future;
        },
        useRealAuthentication: true,
      );
      var secondBootstrapReads = 0;
      final second = _TrackingAppState(
        initializeNotifications: () async {},
        readInitialized: () async {
          secondBootstrapReads++;
          secondBootstrapStarted.complete();
          return true;
        },
        validateSession: () async => false,
        readSessionRemainingLifetime: () async => const Duration(minutes: 10),
        syncReminders: () async {},
      );

      await tester.pumpWidget(PersonalButlerApp(appState: first));
      await _pumpUntil(tester, () => authenticationStarted.isCompleted);

      await tester.pumpWidget(PersonalButlerApp(appState: second));

      expect(find.byKey(const Key('startup-loading-screen')), findsOneWidget);
      expect(secondBootstrapReads, 0);

      authenticationGate.complete(true);
      await _pumpUntil(tester, () => deletionStarted.isCompleted);

      expect(find.byKey(const Key('startup-loading-screen')), findsOneWidget);
      expect(secondBootstrapReads, 0);

      deletionGate.complete();
      await _pumpUntil(tester, () => secondBootstrapStarted.isCompleted);
      await _pumpUntil(tester, () => !second.loading);
      await _pumpUntil(
        tester,
        () => find.byType(InboxScreen).evaluate().isNotEmpty,
      );
      final lateException = tester.takeException();
      final secondStartedSafely = secondBootstrapReads == 1 && second.unlocked;

      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      second.dispose();
      await tester.pump();

      expect(lateException, isNull);
      expect(secondStartedSafely, isTrue);
    },
  );

  testWidgets('notification init failure still routes to the inbox', (
    tester,
  ) async {
    var readInitializedAttempts = 0;
    var validateSessionAttempts = 0;
    var syncRemindersAttempts = 0;
    final appState = _TrackingAppState(
      initializeNotifications: () async {
        throw StateError('notification init failed');
      },
      readInitialized: () async {
        readInitializedAttempts++;
        return true;
      },
      validateSession: () async {
        validateSessionAttempts++;
        return true;
      },
      syncReminders: () async {
        syncRemindersAttempts++;
      },
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.byKey(const Key('startup-error-screen')), findsNothing);
    expect(find.byType(LockScreen), findsNothing);
    expect(readInitializedAttempts, 1);
    expect(validateSessionAttempts, 1);
    expect(syncRemindersAttempts, 1);
    expect(appState.loading, isFalse);
    expect(appState.unlocked, isTrue);
    expect(appState.bootstrapError, isNull);
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets('limited photo access opens the image gallery', (tester) async {
    final photoManagerPlugin = _InboxPhotoManagerPlugin(
      PermissionState.limited,
    );
    PhotoManager.withPlugin(photoManagerPlugin);
    final appState = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async => true,
      syncReminders: () async {},
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);
    await tester.tap(find.text('截图导入'));
    await _pumpFrames(tester, 10);

    expect(find.byType(GalleryPickerScreen), findsOneWidget);
    expect(
      photoManagerPlugin.requestOption?.androidPermission.type,
      RequestType.image,
    );
    expect(
      photoManagerPlugin.requestOption?.androidPermission.mediaLocation,
      isFalse,
    );
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied photo access can be cancelled without opening settings', (
    tester,
  ) async {
    final photoManagerPlugin = _InboxPhotoManagerPlugin(PermissionState.denied);
    PhotoManager.withPlugin(photoManagerPlugin);
    final appState = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async => true,
      syncReminders: () async {},
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);
    await tester.tap(find.text('截图导入'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('需要相册权限'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.byType(GalleryPickerScreen), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(photoManagerPlugin.openSettingCalls, 0);
    expect(find.byType(GalleryPickerScreen), findsNothing);
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied photo access opens settings only after confirmation', (
    tester,
  ) async {
    final photoManagerPlugin = _InboxPhotoManagerPlugin(PermissionState.denied);
    PhotoManager.withPlugin(photoManagerPlugin);
    final appState = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async => true,
      syncReminders: () async {},
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);
    await tester.tap(find.text('截图导入'));
    await tester.pumpAndSettle();

    expect(photoManagerPlugin.openSettingCalls, 0);
    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();

    expect(photoManagerPlugin.openSettingCalls, 1);
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.byType(GalleryPickerScreen), findsNothing);
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings failure stays in inbox and shows a safe message', (
    tester,
  ) async {
    final photoManagerPlugin = _InboxPhotoManagerPlugin(
      PermissionState.denied,
      openSettingError: StateError('private path token'),
    );
    PhotoManager.withPlugin(photoManagerPlugin);
    final appState = _TrackingAppState(
      initializeNotifications: () async {},
      readInitialized: () async => true,
      validateSession: () async => true,
      syncReminders: () async {},
    );

    await tester.pumpWidget(PersonalButlerApp(appState: appState));
    await _pumpFrames(tester);
    await tester.tap(find.text('截图导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去设置'));
    await _pumpFrames(tester);

    expect(photoManagerPlugin.openSettingCalls, 1);
    expect(find.text('无法打开系统设置，请手动前往应用设置'), findsOneWidget);
    expect(find.textContaining('private path token'), findsNothing);
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.byType(GalleryPickerScreen), findsNothing);
    await _disposeInjectedApp(tester, appState);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'secure bootstrap failure shows a safe retry page and stays locked',
    (tester) async {
      final appState = _TrackingAppState(
        initializeNotifications: () async {},
        readInitialized: () async {
          throw StateError('敏感启动细节');
        },
        validateSession: () async => true,
        syncReminders: () async {},
      );

      await tester.pumpWidget(PersonalButlerApp(appState: appState));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('startup-error-screen')), findsOneWidget);
      expect(find.text('安全启动失败'), findsOneWidget);
      expect(find.text('无法安全验证应用状态，请重试。'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.textContaining('敏感启动细节'), findsNothing);
      expect(find.byType(InboxScreen), findsNothing);
      expect(find.byType(MainShell), findsNothing);
      expect(find.byType(LockScreen), findsNothing);
      expect(appState.loading, isFalse);
      expect(appState.unlocked, isFalse);
      expect(appState.bootstrapError, isNotNull);
      expect(appState.setupFirstRunAttempts, 0);
      expect(appState.unlockAttempts, 0);
      await _disposeInjectedApp(tester, appState);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retry clears the old error and can complete to the lock screen',
    (tester) async {
      var attempts = 0;
      final retryGate = Completer<void>();
      final appState = _TrackingAppState(
        initializeNotifications: () async {},
        readInitialized: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('first failure');
          }
          await retryGate.future;
          return true;
        },
        validateSession: () async => false,
        syncReminders: () async {},
      );

      await tester.pumpWidget(PersonalButlerApp(appState: appState));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('startup-error-screen')), findsOneWidget);

      await tester.tap(find.byKey(const Key('startup-retry-button')));
      await tester.pump();
      await tester.pump();

      expect(appState.loading, isTrue);
      expect(appState.bootstrapError, isNull);
      expect(appState.unlocked, isFalse);
      expect(find.byKey(const Key('startup-loading-screen')), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);

      retryGate.complete();
      await _pumpFrames(tester);

      expect(appState.loading, isFalse);
      expect(appState.bootstrapError, isNull);
      expect(appState.initialized, isTrue);
      expect(appState.unlocked, isFalse);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(InboxScreen), findsNothing);
      expect(appState.setupFirstRunAttempts, 0);
      expect(appState.unlockAttempts, 1);
      await _disposeInjectedApp(tester, appState);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 20 && !condition(); i++) {
    await tester.pump();
  }
  expect(condition(), isTrue);
}

Future<void> _disposeInjectedApp(
  WidgetTester tester,
  _TrackingAppState appState,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  appState.dispose();
  await tester.pump();
}

class _TrackingAppState extends AppState {
  _TrackingAppState({
    required super.initializeNotifications,
    required super.readInitialized,
    required super.validateSession,
    super.readSessionRemainingLifetime,
    required super.syncReminders,
    super.lockSession,
    this.useRealAuthentication = false,
  });

  final ItemRepository _items = _EmptyItemRepository();
  int setupFirstRunAttempts = 0;
  int unlockAttempts = 0;
  int disposeAttempts = 0;
  final bool useRealAuthentication;
  final Completer<bool> _authentication = Completer<bool>();

  @override
  ItemRepository get items => _items;

  @override
  Future<bool> setupFirstRun() {
    setupFirstRunAttempts++;
    if (useRealAuthentication) return super.setupFirstRun();
    return _authentication.future;
  }

  @override
  Future<bool> unlock() {
    unlockAttempts++;
    if (useRealAuthentication) return super.unlock();
    return _authentication.future;
  }

  @override
  void dispose() {
    disposeAttempts++;
    super.dispose();
  }
}

class _EmptyItemRepository extends ItemRepository {
  @override
  Future<List<ItemModel>> getInboxItems() async => [];

  @override
  Future<Map<String, int>> getTodayStats() async => {};
}

class _InboxPhotoManagerPlugin extends PhotoManagerPlugin {
  _InboxPhotoManagerPlugin(this.permissionState, {this.openSettingError});

  final PermissionState permissionState;
  final Object? openSettingError;
  PermissionRequestOption? requestOption;
  int openSettingCalls = 0;

  @override
  Future<PermissionState> requestPermissionExtend(
    PermissionRequestOption requestOption,
  ) async {
    this.requestOption = requestOption;
    return permissionState;
  }

  @override
  Future<void> openSetting() async {
    openSettingCalls++;
    final error = openSettingError;
    if (error != null) throw error;
  }

  @override
  Future<List<AssetPathEntity>> getAssetPathList({
    bool hasAll = true,
    bool onlyAll = false,
    RequestType type = RequestType.common,
    PMFilter? filterOption,
    required PMPathFilter pathFilterOption,
  }) async {
    return [];
  }
}
