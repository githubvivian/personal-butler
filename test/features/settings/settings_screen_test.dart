import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/repositories/schedule_repository.dart';
import 'package:personal_butler/core/security/session_service.dart';
import 'package:personal_butler/core/services/system_settings_service.dart';
import 'package:personal_butler/features/settings/settings_screen.dart';
import 'package:provider/provider.dart';

const _safeFailureMessage = '无法打开系统通知设置，请手动前往应用设置';
const _exactAlarmTitle = '提高提醒准点性';
const _exactAlarmSubtitle = '进入系统精确闹钟授权，帮助事项和生日提醒更准时';
const _exactAlarmSuccessMessage = '精确闹钟权限已开启，事项和生日提醒已重新同步';
const _exactAlarmDeniedMessage = '未获得精确闹钟权限，事项和生日提醒仍将使用普通模式';
const _exactAlarmRequestFailureMessage = '无法请求精确闹钟权限，请稍后重试';
const _exactAlarmReconcileFailureMessage = '权限已开启，但事项和生日提醒重新同步失败，请稍后重试';
const _lockFailureMessage = '会话已锁定，但安全清理未完成，请稍后重试';

void main() {
  setUp(SessionService.instance.clearSessionRevocationFailure);

  Future<void> pumpSettings(
    WidgetTester tester,
    NotificationSettingsOpener opener,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: _SettingsAppState(),
        child: MaterialApp(
          home: SettingsScreen(notificationSettingsOpener: opener),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('通知设置'),
      200,
      scrollable: find.byType(Scrollable),
    );
  }

  Future<void> pumpExactAlarmSettings(
    WidgetTester tester, {
    required Future<bool?> Function() requester,
    required Future<void> Function({
      required ItemRepository items,
      required BirthdayRepository birthdays,
    })
    reconciler,
    _SettingsAppState? appState,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState ?? _SettingsAppState(),
        child: MaterialApp(
          home: SettingsScreen(
            exactAlarmPermissionRequester: requester,
            reminderReconciler: reconciler,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(_exactAlarmTitle),
      200,
      scrollable: find.byType(Scrollable),
    );
  }

  testWidgets('successful notification settings launch calls opener once', (
    tester,
  ) async {
    var calls = 0;
    await pumpSettings(tester, () async {
      calls++;
      return SystemSettingsLaunchResult.launched;
    });

    await tester.tap(find.text('通知设置'));
    await tester.pump();

    expect(calls, 1);
    expect(find.text(_safeFailureMessage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable notification settings shows a fixed safe message', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      () async => SystemSettingsLaunchResult.unavailable,
    );

    await tester.tap(find.text('通知设置'));
    await tester.pump();

    expect(find.text(_safeFailureMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('raw opener exception is redacted behind the safe message', (
    tester,
  ) async {
    const sensitiveMarker = 'private-path-token-7f93';
    await pumpSettings(tester, () async {
      throw StateError(sensitiveMarker);
    });

    await tester.tap(find.text('通知设置'));
    await tester.pump();

    expect(find.text(_safeFailureMessage), findsOneWidget);
    expect(find.textContaining(sensitiveMarker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opener completion after disposal does not use stale context', (
    tester,
  ) async {
    final completer = Completer<SystemSettingsLaunchResult>();
    var calls = 0;
    await pumpSettings(tester, () {
      calls++;
      return completer.future;
    });

    await tester.tap(find.text('通知设置'));
    await tester.pump();
    expect(calls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    completer.complete(SystemSettingsLaunchResult.unavailable);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lock fails closed immediately and consumes persistent deletion failure',
    (tester) async {
      const sensitiveMarker = 'session-private-path-token-2d61';
      final deletion = Completer<void>();
      var deletionCalls = 0;
      final appState = _SettingsAppState(
        initiallyUnlocked: true,
        sessionLock: () {
          deletionCalls++;
          return deletion.future;
        },
      );
      await appState.bootstrap();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('立即锁定'),
        200,
        scrollable: find.byType(Scrollable),
      );

      await tester.tap(find.text('立即锁定'));
      await tester.pump();

      expect(deletionCalls, 1);
      expect(appState.unlocked, isFalse);
      expect(find.text(_lockFailureMessage), findsNothing);

      deletion.completeError(StateError(sensitiveMarker));
      await tester.pumpAndSettle();

      expect(find.text(_lockFailureMessage), findsOneWidget);
      expect(find.textContaining(sensitiveMarker), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lock failure after disposal does not use stale context', (
    tester,
  ) async {
    const sensitiveMarker = 'disposed-session-private-path-token-5a84';
    final deletion = Completer<void>();
    final appState = _SettingsAppState(
      initiallyUnlocked: true,
      sessionLock: () => deletion.future,
    );
    await appState.bootstrap();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('立即锁定'),
      200,
      scrollable: find.byType(Scrollable),
    );

    await tester.tap(find.text('立即锁定'));
    await tester.pump();
    expect(appState.unlocked, isFalse);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(find.byType(SettingsScreen), findsNothing);

    deletion.completeError(StateError(sensitiveMarker));
    await tester.pump();

    expect(find.textContaining(sensitiveMarker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exact alarm entry does not request permission during pump', (
    tester,
  ) async {
    var requestCalls = 0;
    var reconcileCalls = 0;
    await pumpExactAlarmSettings(
      tester,
      requester: () async {
        requestCalls++;
        return true;
      },
      reconciler: ({required items, required birthdays}) async {
        reconcileCalls++;
      },
    );

    expect(find.text(_exactAlarmTitle), findsOneWidget);
    expect(find.text(_exactAlarmSubtitle), findsOneWidget);
    expect(requestCalls, 0);
    expect(reconcileCalls, 0);
  });

  testWidgets('granted exact alarm permission awaits one reconciliation', (
    tester,
  ) async {
    final appState = _SettingsAppState();
    final reconcileCompleter = Completer<void>();
    var requestCalls = 0;
    var reconcileCalls = 0;
    await pumpExactAlarmSettings(
      tester,
      appState: appState,
      requester: () async {
        requestCalls++;
        return true;
      },
      reconciler: ({required items, required birthdays}) {
        reconcileCalls++;
        expect(identical(items, appState.items), isTrue);
        expect(identical(birthdays, appState.birthdays), isTrue);
        return reconcileCompleter.future;
      },
    );

    await tester.tap(find.text(_exactAlarmTitle));
    await tester.pump();

    expect(requestCalls, 1);
    expect(reconcileCalls, 1);
    expect(find.text(_exactAlarmSuccessMessage), findsNothing);

    reconcileCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text(_exactAlarmSuccessMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'coalesces rapid taps and starts a new request after completion',
    (tester) async {
      final firstRequest = Completer<bool?>();
      final secondRequest = Completer<bool?>();
      var requestCalls = 0;
      var reconcileCalls = 0;
      await pumpExactAlarmSettings(
        tester,
        requester: () {
          requestCalls++;
          return requestCalls == 1 ? firstRequest.future : secondRequest.future;
        },
        reconciler: ({required items, required birthdays}) async {
          reconcileCalls++;
        },
      );

      await tester.tap(find.text(_exactAlarmTitle));
      await tester.tap(find.text(_exactAlarmTitle));
      await tester.pump();

      expect(requestCalls, 1);
      expect(reconcileCalls, 0);

      firstRequest.complete(true);
      await tester.pumpAndSettle();

      expect(requestCalls, 1);
      expect(reconcileCalls, 1);
      expect(find.text(_exactAlarmSuccessMessage), findsOneWidget);

      await tester.tap(find.text(_exactAlarmTitle));
      await tester.pump();

      expect(requestCalls, 2);
      expect(reconcileCalls, 1);

      secondRequest.complete(false);
      await tester.pumpAndSettle();

      expect(reconcileCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('requester failure clears the in-flight guard for retry', (
    tester,
  ) async {
    final retryRequest = Completer<bool?>();
    var requestCalls = 0;
    var reconcileCalls = 0;
    await pumpExactAlarmSettings(
      tester,
      requester: () {
        requestCalls++;
        if (requestCalls == 1) {
          throw StateError('first-request-failure-marker');
        }
        return retryRequest.future;
      },
      reconciler: ({required items, required birthdays}) async {
        reconcileCalls++;
      },
    );

    await tester.tap(find.text(_exactAlarmTitle));
    await tester.pumpAndSettle();
    expect(requestCalls, 1);

    await tester.tap(find.text(_exactAlarmTitle));
    await tester.pump();

    expect(requestCalls, 2);
    expect(reconcileCalls, 0);

    retryRequest.complete(false);
    await tester.pumpAndSettle();

    expect(reconcileCalls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final permissionResult in <bool?>[false, null]) {
    testWidgets(
      '$permissionResult exact alarm permission does not reconcile reminders',
      (tester) async {
        var requestCalls = 0;
        var reconcileCalls = 0;
        await pumpExactAlarmSettings(
          tester,
          requester: () async {
            requestCalls++;
            return permissionResult;
          },
          reconciler: ({required items, required birthdays}) async {
            reconcileCalls++;
          },
        );

        await tester.tap(find.text(_exactAlarmTitle));
        await tester.pumpAndSettle();

        expect(requestCalls, 1);
        expect(reconcileCalls, 0);
        expect(find.text(_exactAlarmDeniedMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('exact alarm requester failure shows a redacted safe message', (
    tester,
  ) async {
    const sensitiveMarker = 'permission-private-path-token-4b19';
    var reconcileCalls = 0;
    await pumpExactAlarmSettings(
      tester,
      requester: () async {
        throw StateError(sensitiveMarker);
      },
      reconciler: ({required items, required birthdays}) async {
        reconcileCalls++;
      },
    );

    await tester.tap(find.text(_exactAlarmTitle));
    await tester.pumpAndSettle();

    expect(reconcileCalls, 0);
    expect(find.text(_exactAlarmRequestFailureMessage), findsOneWidget);
    expect(find.textContaining(sensitiveMarker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconcile failure is distinct and redacts the raw exception', (
    tester,
  ) async {
    const sensitiveMarker = 'reconcile-private-path-token-8e53';
    var reconcileCalls = 0;
    await pumpExactAlarmSettings(
      tester,
      requester: () async => true,
      reconciler: ({required items, required birthdays}) async {
        reconcileCalls++;
        throw StateError(sensitiveMarker);
      },
    );

    await tester.tap(find.text(_exactAlarmTitle));
    await tester.pumpAndSettle();

    expect(reconcileCalls, 1);
    expect(find.text(_exactAlarmReconcileFailureMessage), findsOneWidget);
    expect(find.text(_exactAlarmDeniedMessage), findsNothing);
    expect(find.textContaining(sensitiveMarker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('async completion after disposal does not use stale context', (
    tester,
  ) async {
    final requestCompleter = Completer<bool?>();
    final reconcileCompleter = Completer<void>();
    var reconcileCalls = 0;
    await pumpExactAlarmSettings(
      tester,
      requester: () => requestCompleter.future,
      reconciler: ({required items, required birthdays}) {
        reconcileCalls++;
        return reconcileCompleter.future;
      },
    );

    await tester.tap(find.text(_exactAlarmTitle));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    requestCompleter.complete(true);
    await tester.pump();
    expect(reconcileCalls, 1);

    reconcileCompleter.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _SettingsAppState extends AppState {
  _SettingsAppState({
    bool initiallyUnlocked = false,
    SessionLockAction? sessionLock,
  }) : super(
         initializeNotifications: () async {},
         readInitialized: () async => initiallyUnlocked,
         validateSession: () async => initiallyUnlocked,
         syncReminders: () async {},
         lockSession: sessionLock,
       );

  final _emptyItems = _EmptyItemRepository();
  final _emptyIdeas = _EmptyIdeaRepository();
  final _emptyBirthdays = _EmptyBirthdayRepository();
  final _emptySchedules = _EmptyScheduleRepository();

  @override
  ItemRepository get items => _emptyItems;

  @override
  IdeaRepository get ideas => _emptyIdeas;

  @override
  BirthdayRepository get birthdays => _emptyBirthdays;

  @override
  ScheduleRepository get schedules => _emptySchedules;
}

class _EmptyItemRepository extends ItemRepository {
  @override
  Future<Map<String, int>> getTodayStats() async => {
    'inbox': 0,
    'pending': 0,
    'today': 0,
  };
}

class _EmptyIdeaRepository extends IdeaRepository {
  @override
  Future<List<IdeaModel>> getAll({String? tag}) async => [];
}

class _EmptyBirthdayRepository extends BirthdayRepository {
  @override
  Future<List<BirthdayModel>> getAll() async => [];
}

class _EmptyScheduleRepository extends ScheduleRepository {
  @override
  Future<ScheduleSettingsModel> getSettings() async =>
      ScheduleSettingsModel(updatedAt: DateTime(2026));
}
