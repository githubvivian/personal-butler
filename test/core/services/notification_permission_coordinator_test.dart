import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/services/notification_permission_coordinator.dart';

void main() {
  group('NotificationPermissionCoordinator', () {
    test('maps a granted platform result', () async {
      final coordinator = NotificationPermissionCoordinator(
        requestPermission: () async => true,
      );

      final result = await coordinator.requestThenPersist(
        requiresPermission: true,
        persist: () async {},
      );

      expect(result, NotificationPermissionResult.granted);
    });

    test('maps a denied platform result and still persists', () async {
      var persisted = false;
      final coordinator = NotificationPermissionCoordinator(
        requestPermission: () async => false,
      );

      final result = await coordinator.requestThenPersist(
        requiresPermission: true,
        persist: () async => persisted = true,
      );

      expect(result, NotificationPermissionResult.denied);
      expect(persisted, isTrue);
    });

    test(
      'maps a null platform result to unavailable and still persists',
      () async {
        var persisted = false;
        final coordinator = NotificationPermissionCoordinator(
          requestPermission: () async => null,
        );

        final result = await coordinator.requestThenPersist(
          requiresPermission: true,
          persist: () async => persisted = true,
        );

        expect(result, NotificationPermissionResult.unavailable);
        expect(persisted, isTrue);
      },
    );

    test('contains requester exceptions and still persists', () async {
      var persisted = false;
      final coordinator = NotificationPermissionCoordinator(
        requestPermission: () async => throw StateError('private token'),
      );

      final result = await coordinator.requestThenPersist(
        requiresPermission: true,
        persist: () async => persisted = true,
      );

      expect(result, NotificationPermissionResult.unavailable);
      expect(persisted, isTrue);
    });

    test(
      'does not request when no active reminder is being persisted',
      () async {
        var requests = 0;
        var persisted = false;
        final coordinator = NotificationPermissionCoordinator(
          requestPermission: () async {
            requests++;
            return true;
          },
        );

        final result = await coordinator.requestThenPersist(
          requiresPermission: false,
          persist: () async => persisted = true,
        );

        expect(result, NotificationPermissionResult.notRequired);
        expect(requests, 0);
        expect(persisted, isTrue);
      },
    );

    test('requests before persistence', () async {
      final events = <String>[];
      final coordinator = NotificationPermissionCoordinator(
        requestPermission: () async {
          events.add('request');
          return true;
        },
      );

      await coordinator.requestThenPersist(
        requiresPermission: true,
        persist: () async => events.add('persist'),
      );

      expect(events, ['request', 'persist']);
    });

    test(
      'shares only an in-flight request between concurrent callers',
      () async {
        final permission = Completer<bool?>();
        var requests = 0;
        var persists = 0;
        final coordinator = NotificationPermissionCoordinator(
          requestPermission: () {
            requests++;
            return permission.future;
          },
        );

        final first = coordinator.requestThenPersist(
          requiresPermission: true,
          persist: () async => persists++,
        );
        final second = coordinator.requestThenPersist(
          requiresPermission: true,
          persist: () async => persists++,
        );

        expect(requests, 1);
        expect(persists, 0);
        permission.complete(true);

        expect(await Future.wait([first, second]), [
          NotificationPermissionResult.granted,
          NotificationPermissionResult.granted,
        ]);
        expect(persists, 2);
      },
    );

    test('clears the in-flight request so a later attempt can retry', () async {
      var requests = 0;
      final coordinator = NotificationPermissionCoordinator(
        requestPermission: () async {
          requests++;
          return requests == 1 ? false : true;
        },
      );

      final first = await coordinator.requestThenPersist(
        requiresPermission: true,
        persist: () async {},
      );
      final second = await coordinator.requestThenPersist(
        requiresPermission: true,
        persist: () async {},
      );

      expect(first, NotificationPermissionResult.denied);
      expect(second, NotificationPermissionResult.granted);
      expect(requests, 2);
    });

    test('propagates persistence failures unchanged', () async {
      final failure = StateError('database write failed');
      final coordinator = NotificationPermissionCoordinator(
        requestPermission: () async => false,
      );

      await expectLater(
        coordinator.requestThenPersist(
          requiresPermission: true,
          persist: () async => throw failure,
        ),
        throwsA(same(failure)),
      );
    });
  });

  group('itemHasActiveReminder', () {
    test('accepts a confirmed non-deleted item with a start time', () {
      expect(
        itemHasActiveReminder(_item(startAt: DateTime(2026, 7, 15, 10))),
        isTrue,
      );
    });

    test('accepts an unfinished pending item with a follow-up time', () {
      expect(
        itemHasActiveReminder(
          _item(
            type: 'review',
            pendingStatus: 'submitted',
            nextFollowUpAt: DateTime(2026, 7, 22),
          ),
        ),
        isTrue,
      );
    });

    test('rejects deleted, draft, completed, and untimed items', () {
      expect(
        itemHasActiveReminder(
          _item(isDeleted: true, startAt: DateTime(2026, 7, 15)),
        ),
        isFalse,
      );
      expect(
        itemHasActiveReminder(
          _item(inboxStatus: 'inbox', startAt: DateTime(2026, 7, 15)),
        ),
        isFalse,
      );
      expect(
        itemHasActiveReminder(
          _item(
            type: 'review',
            status: 'done',
            nextFollowUpAt: DateTime(2026, 7, 22),
          ),
        ),
        isFalse,
      );
      expect(itemHasActiveReminder(_item()), isFalse);
    });

    test('requires a pending item type for follow-up-only reminders', () {
      expect(
        itemHasActiveReminder(_item(nextFollowUpAt: DateTime(2026, 7, 22))),
        isFalse,
      );
    });

    test('rejects a completed pending item even when it has a start time', () {
      expect(
        itemHasActiveReminder(
          _item(
            type: 'review',
            status: 'done',
            pendingStatus: 'done',
            startAt: DateTime(2026, 7, 15, 10),
            nextFollowUpAt: DateTime(2026, 7, 22),
          ),
        ),
        isFalse,
      );
    });
  });
}

ItemModel _item({
  String type = 'other',
  String status = 'active',
  String inboxStatus = 'confirmed',
  String? pendingStatus,
  DateTime? startAt,
  DateTime? nextFollowUpAt,
  bool isDeleted = false,
}) {
  final now = DateTime(2026, 7, 15);
  return ItemModel(
    id: 'item-1',
    type: type,
    title: '事项',
    status: status,
    inboxStatus: inboxStatus,
    pendingStatus: pendingStatus,
    startAt: startAt,
    nextFollowUpAt: nextFollowUpAt,
    isDeleted: isDeleted,
    createdAt: now,
    updatedAt: now,
  );
}
