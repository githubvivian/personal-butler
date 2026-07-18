import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/services/notification_permission_coordinator.dart';
import 'package:personal_butler/features/birthday/birthday_screen.dart';
import 'package:personal_butler/features/inbox/ocr_confirm_screen.dart';
import 'package:personal_butler/features/items/item_screens.dart';
import 'package:personal_butler/features/pending/pending_screen.dart';
import 'package:personal_butler/features/widgets/common_widgets.dart';

void main() {
  testWidgets('CreateItem requests before saving an active pending reminder', (
    tester,
  ) async {
    final repository = _SpyItemRepository();
    final events = <String>[];
    final coordinator = NotificationPermissionCoordinator(
      requestPermission: () async {
        events.add('request');
        return false;
      },
    );
    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (_, _) => const Scaffold(body: Text('host')),
        ),
        GoRoute(
          path: '/create',
          builder: (_, _) => CreateItemScreen(
            itemRepository: repository,
            notificationPermissionCoordinator: coordinator,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    repository.onSave = (_) async => events.add('persist');

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/create');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '报账事项');
    final reimbursementChip = find.widgetWithText(ChoiceChip, '报账');
    await tester.ensureVisible(reimbursementChip);
    await tester.tap(reimbursementChip);
    await tester.pump();
    await _tapCreateSave(tester);
    await tester.pumpAndSettle();

    expect(events, ['request', 'persist']);
    expect(repository.saved.single.isPendingType, isTrue);
    expect(repository.saved.single.nextFollowUpAt, isNotNull);
    expect(find.text('通知权限未开启，内容已保存'), findsOneWidget);
    expect(find.text('host'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CreateItem saves a task as a pending follow-up', (tester) async {
    final repository = _SpyItemRepository();
    final events = <String>[];
    final coordinator = NotificationPermissionCoordinator(
      requestPermission: () async {
        events.add('request');
        return true;
      },
    );
    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (_, _) => const Scaffold(body: Text('host')),
        ),
        GoRoute(
          path: '/create',
          builder: (_, _) => CreateItemScreen(
            itemRepository: repository,
            notificationPermissionCoordinator: coordinator,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    repository.onSave = (_) async => events.add('persist');

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/create');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '待处理任务');
    final taskChip = find.widgetWithText(ChoiceChip, '任务');
    await tester.ensureVisible(taskChip);
    await tester.tap(taskChip);
    await tester.pump();
    await _tapCreateSave(tester);
    await tester.pumpAndSettle();

    expect(events, ['request', 'persist']);
    expect(repository.saved.single.type, 'task');
    expect(repository.saved.single.isPendingType, isTrue);
    expect(repository.saved.single.pendingStatus, 'submitted');
    expect(repository.saved.single.nextFollowUpAt, isNotNull);
    expect(find.text('host'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CreateItem ignores a rapid duplicate save tap', (tester) async {
    final repository = _SpyItemRepository();
    repository.onSave = (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    };
    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (_, _) => const Scaffold(body: Text('host')),
        ),
        GoRoute(
          path: '/create',
          builder: (_, _) => CreateItemScreen(
            itemRepository: repository,
            notificationPermissionCoordinator:
                NotificationPermissionCoordinator(
                  requestPermission: () async => true,
                ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/create');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '连点测试');
    final taskChip = find.widgetWithText(ChoiceChip, '任务');
    await tester.ensureVisible(taskChip);
    await tester.tap(taskChip);
    await tester.pump();
    await _scrollToCreateSave(tester);
    final save = find.byKey(const Key('create-save'));
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(1));
    expect(find.text('host'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CreateItem reports save failures and re-enables the button', (
    tester,
  ) async {
    final repository = _SpyItemRepository()
      ..onSave = (_) async => throw StateError('private persistence failure');
    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (_, _) => const Scaffold(body: Text('host')),
        ),
        GoRoute(
          path: '/create',
          builder: (_, _) => CreateItemScreen(
            itemRepository: repository,
            notificationPermissionCoordinator:
                NotificationPermissionCoordinator(
                  requestPermission: () async => true,
                ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/create');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '失败重试测试');
    final taskChip = find.widgetWithText(ChoiceChip, '任务');
    await tester.ensureVisible(taskChip);
    await tester.tap(taskChip);
    await tester.pump();
    await _scrollToCreateSave(tester);
    await tester.tap(find.byKey(const Key('create-save')));
    await tester.pumpAndSettle();

    expect(find.text('保存失败，请重试'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('create-save')),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('host'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CreateItem rejects an untimed non-pending item', (tester) async {
    final repository = _SpyItemRepository();
    var requests = 0;
    final coordinator = NotificationPermissionCoordinator(
      requestPermission: () async {
        requests++;
        return true;
      },
    );
    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (_, _) => const Scaffold(body: Text('host')),
        ),
        GoRoute(
          path: '/create',
          builder: (_, _) => CreateItemScreen(
            itemRepository: repository,
            notificationPermissionCoordinator: coordinator,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/create');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '无提醒事项');
    await _tapCreateSave(tester);
    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(repository.saved, isEmpty);
    expect(find.text('请设置时间'), findsOneWidget);
    expect(find.text('host'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OcrConfirm rejects a blank title before persistence', (
    tester,
  ) async {
    final draft = _item(
      id: 'ocr-blank-title',
      type: 'review',
      inboxStatus: 'inbox',
      pendingStatus: 'submitted',
    );
    final repository = _SpyItemRepository(itemById: draft);
    var requests = 0;
    final router = GoRouter(
      initialLocation: '/ocr',
      routes: [
        GoRoute(
          path: '/ocr',
          builder: (_, _) => OcrConfirmScreen(
            itemId: draft.id,
            itemRepository: repository,
            notificationPermissionCoordinator:
                NotificationPermissionCoordinator(
                  requestPermission: () async {
                    requests++;
                    return true;
                  },
                ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.tap(find.widgetWithText(FilledButton, '确认入库'));
    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(repository.saved, isEmpty);
    expect(find.text('请输入标题'), findsOneWidget);
    expect(find.byType(OcrConfirmScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OcrConfirm rejects an untimed non-pending item', (tester) async {
    final draft = _item(
      id: 'ocr-untimed-meeting',
      type: 'meeting',
      inboxStatus: 'inbox',
    );
    final repository = _SpyItemRepository(itemById: draft);
    var requests = 0;
    final router = GoRouter(
      initialLocation: '/ocr',
      routes: [
        GoRoute(
          path: '/ocr',
          builder: (_, _) => OcrConfirmScreen(
            itemId: draft.id,
            itemRepository: repository,
            notificationPermissionCoordinator:
                NotificationPermissionCoordinator(
                  requestPermission: () async {
                    requests++;
                    return true;
                  },
                ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认入库'));
    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(repository.saved, isEmpty);
    expect(find.text('请设置时间'), findsOneWidget);
    expect(find.byType(OcrConfirmScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OcrConfirm contains permission errors, saves, and navigates', (
    tester,
  ) async {
    final draft = _item(
      id: 'ocr-draft',
      type: 'review',
      inboxStatus: 'inbox',
      pendingStatus: 'submitted',
    );
    final repository = _SpyItemRepository(itemById: draft);
    var requests = 0;
    final coordinator = NotificationPermissionCoordinator(
      requestPermission: () async {
        requests++;
        throw StateError('private permission exception');
      },
    );
    final router = GoRouter(
      initialLocation: '/ocr',
      routes: [
        GoRoute(
          path: '/ocr',
          builder: (_, _) => OcrConfirmScreen(
            itemId: draft.id,
            itemRepository: repository,
            notificationPermissionCoordinator: coordinator,
          ),
        ),
        GoRoute(
          path: '/pending',
          builder: (_, _) => const Scaffold(body: Text('pending-target')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认入库'));
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.inboxStatus, 'confirmed');
    expect(repository.saved.single.nextFollowUpAt, isNotNull);
    expect(find.text('通知权限暂不可用，内容已保存'), findsOneWidget);
    expect(find.textContaining('private permission exception'), findsNothing);
    expect(find.text('pending-target'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'Pending postpone requests permission and persists when denied',
    () async {
      final item = _activePendingItem();
      final repository = _SpyItemRepository(itemById: item);
      var requests = 0;
      final coordinator = NotificationPermissionCoordinator(
        requestPermission: () async {
          requests++;
          return false;
        },
      );
      final actions = PendingReminderActions(
        itemRepository: repository,
        notificationPermissionCoordinator: coordinator,
      );

      final result = await actions.postpone(item);

      expect(result, NotificationPermissionResult.denied);
      expect(requests, 1);
      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.nextFollowUpAt, isNotNull);
    },
  );

  test('Pending marking done does not request permission', () async {
    final item = _activePendingItem();
    final repository = _SpyItemRepository(itemById: item);
    var requests = 0;
    final actions = PendingReminderActions(
      itemRepository: repository,
      notificationPermissionCoordinator: NotificationPermissionCoordinator(
        requestPermission: () async {
          requests++;
          return true;
        },
      ),
    );

    final result = await actions.updateStatus(item, 'done');

    expect(result, NotificationPermissionResult.notRequired);
    expect(requests, 0);
    expect(repository.saved.single.status, 'done');
  });

  test('Pending restoring a done item requests and marks it active', () async {
    final item = _activePendingItem(status: 'done', pendingStatus: 'done');
    final repository = _SpyItemRepository(itemById: item);
    var requests = 0;
    final coordinator = NotificationPermissionCoordinator(
      requestPermission: () async {
        requests++;
        return true;
      },
    );
    final actions = PendingReminderActions(
      itemRepository: repository,
      notificationPermissionCoordinator: coordinator,
    );

    final result = await actions.updateStatus(item, 'reviewing');

    expect(result, NotificationPermissionResult.granted);
    expect(requests, 1);
    expect(repository.saved.single.pendingStatus, 'reviewing');
    expect(repository.saved.single.status, 'active');
  });

  testWidgets('PendingScreen renders its default non-empty card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = _activePendingItem();
    final repository = _SpyItemRepository(pendingItems: [item]);

    await tester.pumpWidget(
      MaterialApp(home: PendingScreen(itemRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AppCard), findsOneWidget);
    expect(find.text(item.title), findsOneWidget);
  });

  testWidgets(
    'PendingScreen postpone requests before saving and warns when denied',
    (tester) async {
      final events = <String>[];
      final repository = _SpyItemRepository(
        pendingItems: [_activePendingItem()],
      )..onSave = (_) async => events.add('persist');
      final coordinator = NotificationPermissionCoordinator(
        requestPermission: () async {
          events.add('request');
          return false;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PendingScreen(
            itemRepository: repository,
            notificationPermissionCoordinator: coordinator,
            itemBuilder: _pendingTestItemBuilder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-postpone')));
      await tester.pumpAndSettle();

      expect(events, ['request', 'persist']);
      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.nextFollowUpAt, isNotNull);
      expect(repository.pendingLoads, greaterThanOrEqualTo(2));
      expect(find.text('通知权限未开启，内容已保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PendingScreen marking a timed item done saves without requesting',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _SpyItemRepository(
        pendingItems: [_activePendingItem(startAt: DateTime(2026, 7, 16, 10))],
      );
      var requests = 0;
      final coordinator = NotificationPermissionCoordinator(
        requestPermission: () async {
          requests++;
          throw StateError('private notification failure');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PendingScreen(
            itemRepository: repository,
            notificationPermissionCoordinator: coordinator,
            itemBuilder: _pendingTestItemBuilder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-update-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已完成').last);
      await tester.pumpAndSettle();

      expect(requests, 0);
      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.status, 'done');
      expect(find.textContaining('private notification failure'), findsNothing);
      expect(find.text('通知权限暂不可用，内容已保存'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Birthday add always requests and still persists when denied', (
    tester,
  ) async {
    final repository = _SpyBirthdayRepository();
    var requests = 0;
    final coordinator = NotificationPermissionCoordinator(
      requestPermission: () async {
        requests++;
        return false;
      },
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
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '小明');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(repository.createdNames, ['小明']);
    expect(repository.loads, greaterThanOrEqualTo(2));
    expect(find.text('通知权限未开启，内容已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tapCreateSave(WidgetTester tester) async {
  await _scrollToCreateSave(tester);
  await tester.tap(find.byKey(const Key('create-save')));
}

Future<void> _scrollToCreateSave(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(find.text('保存'), 250, scrollable: scrollable);
  await tester.drag(scrollable, const Offset(0, -80));
  await tester.pumpAndSettle();
}

class _SpyItemRepository extends ItemRepository {
  _SpyItemRepository({this.itemById, List<ItemModel>? pendingItems})
    : pendingItems = pendingItems ?? [];

  ItemModel? itemById;
  final List<ItemModel> pendingItems;
  final List<ItemModel> saved = [];
  Future<void> Function(ItemModel)? onSave;
  int pendingLoads = 0;

  @override
  Future<void> save(ItemModel item) async {
    await _recordMutation(item);
  }

  @override
  Future<ItemModel?> getById(String id) async {
    final currentItem = itemById;
    if (currentItem?.id == id) return currentItem;
    for (final item in pendingItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<ItemModel?> updatePendingFollowUp(
    String id,
    DateTime nextFollowUpAt,
  ) async {
    final current = await getById(id);
    if (current == null) return null;
    final updated = current.copyWith(nextFollowUpAt: nextFollowUpAt);
    await _recordMutation(updated);
    return updated;
  }

  @override
  Future<ItemModel?> updatePendingStatus(
    String id, {
    required String pendingStatus,
    required String status,
  }) async {
    final current = await getById(id);
    if (current == null) return null;
    final updated = current.copyWith(
      pendingStatus: pendingStatus,
      status: status,
    );
    await _recordMutation(updated);
    return updated;
  }

  Future<void> _recordMutation(ItemModel item) async {
    saved.add(item);
    itemById = item;
    final index = pendingItems.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (index >= 0) pendingItems[index] = item;
    await onSave?.call(item);
    notifyListeners();
  }

  @override
  Future<List<AttachmentModel>> getAttachments(String itemId) async => [];

  @override
  Future<List<ItemModel>> getPendingItems({bool includeDone = false}) async {
    pendingLoads++;
    return List.of(pendingItems);
  }
}

class _SpyBirthdayRepository extends BirthdayRepository {
  final createdNames = <String>[];
  int loads = 0;

  @override
  Future<List<BirthdayModel>> getAll() async {
    loads++;
    return [];
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
  }) async {
    createdNames.add(name);
    return BirthdayModel(
      id: 'birthday-1',
      name: name,
      relation: relation,
      isLunar: isLunar,
      month: month,
      day: day,
      isLeapMonth: isLeapMonth,
      remindDaysBefore: remindDaysBefore,
      createdAt: DateTime(2026, 7, 15),
    );
  }
}

ItemModel _activePendingItem({
  String status = 'active',
  String pendingStatus = 'submitted',
  DateTime? startAt,
}) {
  return _item(
    id: 'pending-1',
    type: 'review',
    status: status,
    pendingStatus: pendingStatus,
    startAt: startAt,
    nextFollowUpAt: DateTime(2026, 7, 22),
  );
}

ItemModel _item({
  required String id,
  String type = 'other',
  String status = 'active',
  String inboxStatus = 'confirmed',
  String? pendingStatus,
  DateTime? startAt,
  DateTime? nextFollowUpAt,
}) {
  final now = DateTime(2026, 7, 15);
  return ItemModel(
    id: id,
    type: type,
    title: '测试事项',
    status: status,
    inboxStatus: inboxStatus,
    pendingStatus: pendingStatus,
    startAt: startAt,
    nextFollowUpAt: nextFollowUpAt,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _pendingTestItemBuilder(
  BuildContext context,
  ItemModel item,
  VoidCallback onPostpone,
  VoidCallback onUpdateStatus,
) {
  return Card(
    child: Row(
      children: [
        Expanded(child: Text(item.title)),
        TextButton(
          key: const Key('pending-postpone'),
          onPressed: onPostpone,
          child: const Text('延期提醒'),
        ),
        TextButton(
          key: const Key('pending-update-status'),
          onPressed: onUpdateStatus,
          child: const Text('更新状态'),
        ),
      ],
    ),
  );
}
