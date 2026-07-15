import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/repositories/schedule_repository.dart';
import 'package:personal_butler/core/services/system_settings_service.dart';
import 'package:personal_butler/features/settings/settings_screen.dart';
import 'package:provider/provider.dart';

const _safeFailureMessage = '无法打开系统通知设置，请手动前往应用设置';

void main() {
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
}

class _SettingsAppState extends AppState {
  _SettingsAppState()
    : super(
        initializeNotifications: () async {},
        readInitialized: () async => false,
        validateSession: () async => false,
        syncReminders: () async {},
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
