import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/services/notification_permission_coordinator.dart';
import 'package:personal_butler/features/birthday/birthday_screen.dart';

const _loadFailureMessage = '数据加载失败，请重试';

void main() {
  testWidgets('birthday load ignores a stale result after repository change', (
    tester,
  ) async {
    final staleResult = Completer<List<BirthdayModel>>();
    final firstRepository = _ScriptedBirthdayRepository(
      getAllResults: [staleResult.future],
    );
    final secondRepository = _ScriptedBirthdayRepository(
      getAllResults: [
        [_birthday('newest-birthday')],
      ],
    );
    final repository = ValueNotifier<BirthdayRepository>(firstRepository);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<BirthdayRepository>(
          valueListenable: repository,
          builder: (_, value, _) => BirthdayScreen(
            key: const ValueKey('birthday-screen'),
            birthdayRepository: value,
          ),
        ),
      ),
    );
    await tester.pump();

    repository.value = secondRepository;
    await tester.pumpAndSettle();
    expect(find.text('newest-birthday'), findsOneWidget);

    staleResult.complete([_birthday('stale-birthday')]);
    await tester.pump();

    expect(find.text('newest-birthday'), findsOneWidget);
    expect(find.text('stale-birthday'), findsNothing);
    expect(firstRepository.getAllCalls, 1);
    expect(secondRepository.getAllCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('birthday load failure is sanitized and retryable', (
    tester,
  ) async {
    const privateMarker = 'private SQLCipher birthday path';
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [
        _Failure(StateError(privateMarker)),
        [_birthday('recovered-birthday')],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: BirthdayScreen(birthdayRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text(_loadFailureMessage), findsOneWidget);
    expect(find.text('暂无生日记录'), findsNothing);
    expect(find.textContaining(privateMarker), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('recovered-birthday'), findsOneWidget);
    expect(find.text(_loadFailureMessage), findsNothing);
    expect(repository.getAllCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty birthday list remains pull-to-refreshable', (
    tester,
  ) async {
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [
        <BirthdayModel>[],
        [_birthday('refreshed-birthday')],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: BirthdayScreen(birthdayRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无生日记录'), findsOneWidget);
    expect(
      tester.widget<ListView>(find.byType(ListView)).physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );

    await tester.drag(find.byType(ListView), const Offset(0, 360));
    await tester.pumpAndSettle();

    expect(repository.getAllCalls, 2);
    expect(find.text('refreshed-birthday'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('birthday refresh failure retains the previous snapshot', (
    tester,
  ) async {
    const privateMarker = 'private refreshed birthday failure';
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [
        [_birthday('retained-birthday')],
        _Failure(StateError(privateMarker)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: BirthdayScreen(birthdayRepository: repository)),
    );
    await tester.pumpAndSettle();

    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(find.text('retained-birthday'), findsOneWidget);
    expect(find.text(_loadFailureMessage), findsOneWidget);
    expect(find.textContaining(privateMarker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('birthday ignores an initial load completed after disposal', (
    tester,
  ) async {
    final result = Completer<List<BirthdayModel>>();
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [result.future],
    );

    await tester.pumpWidget(
      MaterialApp(home: BirthdayScreen(birthdayRepository: repository)),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    result.complete([_birthday('disposed-result')]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

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
    expect(repository.created, [(isLunar: false, month: 1, day: 1)]);
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
      expect(find.text('添加生日'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty birthday name is explained without closing the dialog', (
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
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(permissionRequests, 0);
    expect(repository.created, isEmpty);
    expect(find.text('请输入姓名'), findsOneWidget);
    expect(find.text('添加生日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('birthday save failure is sanitized and can be retried', (
    tester,
  ) async {
    const privateMarker = 'private birthday insert token';
    final recovered = _birthday('Recovered birthday');
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [
        <BirthdayModel>[],
        [recovered],
      ],
      createResults: [_Failure(StateError(privateMarker)), recovered],
    );
    final coordinator = NotificationPermissionCoordinator(
      requestPermission: () async => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BirthdayScreen(
          birthdayRepository: repository,
          notificationPermissionCoordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openAndSubmitBirthday(tester, 'First attempt');

    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.textContaining(privateMarker), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .onPressed,
      isNotNull,
    );
    expect(repository.createCalls, 1);

    await _openAndSubmitBirthday(tester, 'Recovered birthday');

    expect(find.text('Recovered birthday'), findsOneWidget);
    expect(repository.createCalls, 2);
    expect(repository.getAllCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame birthday save confirmation persists only once', (
    tester,
  ) async {
    final saved = _birthday('Single save');
    final createResult = Completer<BirthdayModel>();
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [
        <BirthdayModel>[],
        [saved],
      ],
      createResults: [createResult.future],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BirthdayScreen(
          birthdayRepository: repository,
          notificationPermissionCoordinator: NotificationPermissionCoordinator(
            requestPermission: () async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Single save');

    final save = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
        .onPressed!;
    save();
    save();
    await tester.pump();

    expect(repository.createCalls, 1);

    createResult.complete(saved);
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.text('Single save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('birthday save completion after disposal is ignored', (
    tester,
  ) async {
    final createResult = Completer<BirthdayModel>();
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [<BirthdayModel>[]],
      createResults: [createResult.future],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BirthdayScreen(
          birthdayRepository: repository,
          notificationPermissionCoordinator: NotificationPermissionCoordinator(
            requestPermission: () async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Disposed save');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(repository.createCalls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    createResult.complete(_birthday('Disposed save'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('birthday delete uses injection and sanitizes a failure', (
    tester,
  ) async {
    const privateMarker = 'private birthday delete SQL';
    final birthday = _birthday('Delete failure');
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [
        [birthday],
      ],
      deleteResults: [_Failure(StateError(privateMarker))],
    );

    await tester.pumpWidget(
      MaterialApp(home: BirthdayScreen(birthdayRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移入已删除'));
    await tester.pumpAndSettle();

    expect(repository.softDeletedIds, [birthday.id]);
    expect(find.text('删除失败，请重试'), findsOneWidget);
    expect(find.textContaining(privateMarker), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid same-item delete starts one dialog and one mutation', (
    tester,
  ) async {
    final birthday = _birthday('Single delete');
    final deleteGate = Completer<void>();
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [
        [birthday],
        <BirthdayModel>[],
      ],
      deleteResults: [deleteGate.future],
    );

    await tester.pumpWidget(
      MaterialApp(home: BirthdayScreen(birthdayRepository: repository)),
    );
    await tester.pumpAndSettle();

    final delete = tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_outline),
        )
        .onPressed!;
    delete();
    delete();
    await tester.pumpAndSettle();

    expect(find.text('删除生日'), findsOneWidget);
    await tester.tap(find.text('移入已删除'));
    await tester.pump();
    expect(repository.softDeletedIds, [birthday.id]);

    deleteGate.complete();
    await tester.pumpAndSettle();

    expect(repository.softDeletedIds, [birthday.id]);
    expect(find.text('暂无生日记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('birthday delete completion after disposal is ignored', (
    tester,
  ) async {
    final birthday = _birthday('Disposed delete');
    final deleteGate = Completer<void>();
    final repository = _ScriptedBirthdayRepository(
      getAllResults: [
        [birthday],
      ],
      deleteResults: [deleteGate.future],
    );

    await tester.pumpWidget(
      MaterialApp(home: BirthdayScreen(birthdayRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移入已删除'));
    await tester.pump();
    expect(repository.softDeletedIds, [birthday.id]);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    deleteGate.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Future<void> _openAndSubmitBirthday(WidgetTester tester, String name) async {
  await tester.tap(find.byIcon(Icons.add));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, name);
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();
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

class _ScriptedBirthdayRepository extends BirthdayRepository {
  _ScriptedBirthdayRepository({
    required List<Object> getAllResults,
    List<Object> createResults = const [],
    List<Object> deleteResults = const [],
  }) : _getAllResults = List<Object>.of(getAllResults),
       _createResults = List<Object>.of(createResults),
       _deleteResults = List<Object>.of(deleteResults);

  final List<Object> _getAllResults;
  final List<Object> _createResults;
  final List<Object> _deleteResults;
  final List<String> softDeletedIds = [];
  int getAllCalls = 0;
  int createCalls = 0;

  @override
  Future<List<BirthdayModel>> getAll() {
    getAllCalls += 1;
    if (_getAllResults.isEmpty) {
      return Future<List<BirthdayModel>>.error(
        StateError('unexpected birthday getAll call'),
      );
    }
    final result = _getAllResults.removeAt(0);
    if (result is _Failure) {
      return Future<List<BirthdayModel>>.error(result.error);
    }
    if (result is Future<List<BirthdayModel>>) return result;
    return Future<List<BirthdayModel>>.value(
      (result as List).cast<BirthdayModel>(),
    );
  }

  @override
  Future<BirthdayModel> create({
    required String name,
    required bool isLunar,
    required int month,
    required int day,
    String relation = '',
    bool isLeapMonth = false,
    int remindDaysBefore = 3,
  }) {
    createCalls += 1;
    if (_createResults.isEmpty) {
      return Future<BirthdayModel>.value(_birthday(name));
    }
    final result = _createResults.removeAt(0);
    if (result is _Failure) {
      return Future<BirthdayModel>.error(result.error);
    }
    if (result is Future<BirthdayModel>) return result;
    return Future<BirthdayModel>.value(result as BirthdayModel);
  }

  @override
  Future<void> softDelete(String id) {
    softDeletedIds.add(id);
    if (_deleteResults.isEmpty) return Future<void>.value();
    final result = _deleteResults.removeAt(0);
    if (result is _Failure) return Future<void>.error(result.error);
    if (result is Future<void>) return result;
    return Future<void>.value();
  }
}

class _Failure {
  const _Failure(this.error);

  final Object error;
}

BirthdayModel _birthday(String name) {
  return BirthdayModel(
    id: name,
    name: name,
    isLunar: false,
    month: 7,
    day: 19,
    createdAt: DateTime(2026, 7, 19),
  );
}
