import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/services/notification_permission_coordinator.dart';
import 'package:personal_butler/features/birthday/birthday_screen.dart';

void main() {
  testWidgets('birthday dialog visibly defaults month and day to one', (
    tester,
  ) async {
    final repository = _SpyBirthdayRepository();
    var permissionRequests = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: BirthdayScreen(
          birthdayRepository: repository,
          notificationPermissionCoordinator: NotificationPermissionCoordinator(
            requestPermission: () async {
              permissionRequests += 1;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList(growable: false);
    expect(fields[2].controller?.text, '1');
    expect(fields[3].controller?.text, '1');

    await tester.enterText(find.byType(TextField).first, 'Default date');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(permissionRequests, 1);
    expect(repository.created, [
      (isLunar: false, month: 1, day: 1),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid birthday is rejected before permission request and persistence',
    (tester) async {
      final repository = _SpyBirthdayRepository();
      var permissionRequests = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: BirthdayScreen(
            birthdayRepository: repository,
            notificationPermissionCoordinator:
                NotificationPermissionCoordinator(
                  requestPermission: () async {
                    permissionRequests += 1;
                    return true;
                  },
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Invalid date');
      await tester.enterText(find.byType(TextField).at(2), '2');
      await tester.enterText(find.byType(TextField).at(3), '30');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(permissionRequests, 0);
      expect(repository.created, isEmpty);
      expect(find.text('请输入有效的生日日期'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _SpyBirthdayRepository extends BirthdayRepository {
  final created = <({bool isLunar, int month, int day})>[];

  @override
  Future<List<BirthdayModel>> getAll() async => [];

  @override
  Future<BirthdayModel> create({
    required String name,
    required bool isLunar,
    required int month,
    required int day,
    String relation = '',
    bool isLeapMonth = false,
    int remindDaysBefore = 3,
  }) async {
    created.add((isLunar: isLunar, month: month, day: day));
    return BirthdayModel(
      id: 'birthday-1',
      name: name,
      relation: relation,
      isLunar: isLunar,
      month: month,
      day: day,
      isLeapMonth: isLeapMonth,
      remindDaysBefore: remindDaysBefore,
      createdAt: DateTime(2026, 7, 16),
    );
  }
}
