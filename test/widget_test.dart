import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:personal_butler/app.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/features/auth/lock_screen.dart';
import 'package:personal_butler/features/inbox/gallery_picker_screen.dart';
import 'package:personal_butler/features/inbox/inbox_screen.dart';
import 'package:personal_butler/features/shell/main_shell.dart';

void main() {
  tearDown(() {
    PhotoManager.withPlugin(PhotoManagerPlugin());
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
    expect(tester.takeException(), isNull);
  });

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
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _TrackingAppState extends AppState {
  _TrackingAppState({
    required Future<void> Function() initializeNotifications,
    required Future<bool> Function() readInitialized,
    required Future<bool> Function() validateSession,
    required Future<void> Function() syncReminders,
  }) : super(
         initializeNotifications: initializeNotifications,
         readInitialized: readInitialized,
         validateSession: validateSession,
         syncReminders: syncReminders,
       );

  final ItemRepository _items = _EmptyItemRepository();
  int setupFirstRunAttempts = 0;
  int unlockAttempts = 0;
  final Completer<bool> _authentication = Completer<bool>();

  @override
  ItemRepository get items => _items;

  @override
  Future<bool> setupFirstRun() {
    setupFirstRunAttempts++;
    return _authentication.future;
  }

  @override
  Future<bool> unlock() {
    unlockAttempts++;
    return _authentication.future;
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
