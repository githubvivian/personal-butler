import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/services/notification_permission_coordinator.dart';
import 'package:personal_butler/features/inbox/ocr_confirm_screen.dart';
import 'package:personal_butler/features/items/item_screens.dart';

void main() {
  group('ItemDetailScreen load state', () {
    testWidgets('missing item ends loading with a not-found message', (
      tester,
    ) async {
      final repository = _FakeItemRepository(getByIdResults: [null]);

      await tester.pumpWidget(
        MaterialApp(
          home: ItemDetailScreen(
            itemId: 'missing-detail',
            itemRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('事项不存在或已删除'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('load failure is sanitized and can retry successfully', (
      tester,
    ) async {
      const privateError = 'private detail database path';
      final item = _item('detail-retry');
      final repository = _FakeItemRepository(
        getByIdResults: [_Failure(StateError(privateError)), item],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ItemDetailScreen(itemId: item.id, itemRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('事项加载失败，请重试'), findsOneWidget);
      expect(find.text(privateError), findsNothing);
      expect(find.textContaining(privateError), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text(item.title), findsOneWidget);
      expect(find.text('事项加载失败，请重试'), findsNothing);
      expect(repository.getByIdCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposed screen ignores a delayed item result', (
      tester,
    ) async {
      final result = Completer<ItemModel?>();
      final repository = _FakeItemRepository(getByIdResults: [result.future]);

      await tester.pumpWidget(
        MaterialApp(
          home: ItemDetailScreen(
            itemId: 'delayed-detail',
            itemRepository: repository,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      result.complete(_item('delayed-detail'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('OcrConfirmScreen load and save state', () {
    testWidgets('missing item ends loading with a not-found message', (
      tester,
    ) async {
      final repository = _FakeItemRepository(getByIdResults: [null]);

      await tester.pumpWidget(
        MaterialApp(
          home: OcrConfirmScreen(
            itemId: 'missing-ocr',
            itemRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('事项不存在或已删除'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('load failure is sanitized and can retry successfully', (
      tester,
    ) async {
      const privateError = 'private OCR database token';
      final item = _item('ocr-retry', ocrText: 'Retry OCR text');
      final repository = _FakeItemRepository(
        getByIdResults: [_Failure(StateError(privateError)), item],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OcrConfirmScreen(itemId: item.id, itemRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('事项加载失败，请重试'), findsOneWidget);
      expect(find.text(privateError), findsNothing);
      expect(find.textContaining(privateError), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text(item.title), findsOneWidget);
      expect(find.text('事项加载失败，请重试'), findsNothing);
      expect(repository.getByIdCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposed screen never writes delayed data to controllers', (
      tester,
    ) async {
      final result = Completer<ItemModel?>();
      final repository = _FakeItemRepository(getByIdResults: [result.future]);

      await tester.pumpWidget(
        MaterialApp(
          home: OcrConfirmScreen(
            itemId: 'delayed-ocr',
            itemRepository: repository,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      result.complete(_item('delayed-ocr', ocrText: 'private delayed text'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('attachment lookup failure keeps the editable form usable', (
      tester,
    ) async {
      final item = _item('ocr-no-preview', ocrText: 'OCR body');
      final repository = _FakeItemRepository(
        getByIdResults: [item],
        attachmentResults: [_Failure(StateError('private asset path'))],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OcrConfirmScreen(itemId: item.id, itemRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(item.title), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('private asset path'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirming after the item disappears does not save or leave', (
      tester,
    ) async {
      final item = _item('ocr-disappears', ocrText: 'OCR body');
      final repository = _FakeItemRepository(getByIdResults: [item, null]);

      await tester.pumpWidget(
        MaterialApp(
          home: OcrConfirmScreen(itemId: item.id, itemRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('事项不存在或已删除'), findsOneWidget);
      expect(find.byType(OcrConfirmScreen), findsOneWidget);
      expect(repository.saveCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid double confirm persists only once', (tester) async {
      final item = _item('ocr-double-save', ocrText: 'OCR body');
      final saveGate = Completer<void>();
      final repository = _FakeItemRepository(
        getByIdResults: [item, item, item],
        saveGate: saveGate,
      );
      final router = GoRouter(
        initialLocation: '/ocr',
        routes: [
          GoRoute(
            path: '/ocr',
            builder: (_, _) => OcrConfirmScreen(
              itemId: item.id,
              itemRepository: repository,
              notificationPermissionCoordinator:
                  NotificationPermissionCoordinator(
                    requestPermission: () async => true,
                  ),
            ),
          ),
          GoRoute(
            path: '/calendar',
            builder: (_, _) => const Scaffold(body: Text('calendar-target')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final confirmButton = find.byType(FilledButton);
      await tester.tap(confirmButton);
      await tester.tap(confirmButton);
      await tester.pump();

      expect(repository.saveCalls, 1);

      saveGate.complete();
      await tester.pumpAndSettle();

      expect(find.text('calendar-target'), findsOneWidget);
      expect(repository.saveCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('save failure is sanitized and re-enables confirmation', (
      tester,
    ) async {
      const privateError = 'private SQLCipher file path';
      final item = _item('ocr-save-failure', ocrText: 'OCR body');
      final repository = _FakeItemRepository(
        getByIdResults: [item, item],
        saveError: StateError(privateError),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OcrConfirmScreen(
            itemId: item.id,
            itemRepository: repository,
            notificationPermissionCoordinator:
                NotificationPermissionCoordinator(
                  requestPermission: () async => true,
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('保存失败，请重试'), findsOneWidget);
      expect(find.text(privateError), findsNothing);
      expect(find.textContaining(privateError), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(repository.saveCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeItemRepository extends ItemRepository {
  _FakeItemRepository({
    required List<Object?> getByIdResults,
    List<Object> attachmentResults = const [],
    this.saveGate,
    this.saveError,
  }) : _getByIdResults = List<Object?>.of(getByIdResults),
       _attachmentResults = List<Object>.of(attachmentResults);

  final List<Object?> _getByIdResults;
  final List<Object> _attachmentResults;
  final Completer<void>? saveGate;
  final Object? saveError;
  int getByIdCalls = 0;
  int saveCalls = 0;
  final List<ItemModel> savedItems = [];

  @override
  Future<ItemModel?> getById(String id) async {
    getByIdCalls += 1;
    if (_getByIdResults.isEmpty) {
      throw StateError('unexpected getById call for $id');
    }
    final result = _getByIdResults.removeAt(0);
    if (result is _Failure) throw result.error;
    if (result is Future<ItemModel?>) return result;
    return result as ItemModel?;
  }

  @override
  Future<List<AttachmentModel>> getAttachments(String itemId) async {
    if (_attachmentResults.isEmpty) return [];
    final result = _attachmentResults.removeAt(0);
    if (result is _Failure) throw result.error;
    if (result is Future<List<AttachmentModel>>) return result;
    return (result as List).cast<AttachmentModel>();
  }

  @override
  Future<void> save(ItemModel item) async {
    saveCalls += 1;
    savedItems.add(item);
    final error = saveError;
    if (error != null) throw error;
    final gate = saveGate;
    if (gate != null) await gate.future;
  }
}

class _Failure {
  const _Failure(this.error);

  final Object error;
}

ItemModel _item(String id, {String? ocrText}) {
  final now = DateTime.utc(2026, 7, 15, 8, 30);
  return ItemModel(
    id: id,
    type: 'meeting',
    title: 'Test item $id',
    ocrText: ocrText,
    inboxStatus: 'inbox',
    createdAt: now,
    updatedAt: now,
  );
}
