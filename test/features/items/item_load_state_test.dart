import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    testWidgets('late A load cannot replace B after itemId changes', (
      tester,
    ) async {
      final aResult = Completer<ItemModel?>();
      final bResult = Completer<ItemModel?>();
      final repository = _FakeItemRepository(
        getByIdResults: [aResult.future, bResult.future],
      );
      final itemId = ValueNotifier<String>('detail-a');
      addTearDown(itemId.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: itemId,
            builder: (_, id, _) => ItemDetailScreen(
              key: const ValueKey('detail-screen'),
              itemId: id,
              itemRepository: repository,
            ),
          ),
        ),
      );
      await tester.pump();

      itemId.value = 'detail-b';
      await tester.pump();

      bResult.complete(_item('detail-b'));
      await tester.pump();

      expect(find.text('Test item detail-b'), findsOneWidget);
      expect(find.text('Test item detail-a'), findsNothing);

      aResult.complete(_item('detail-a'));
      await tester.pump();

      expect(find.text('Test item detail-b'), findsOneWidget);
      expect(find.text('Test item detail-a'), findsNothing);
      expect(repository.getByIdCallIds, ['detail-a', 'detail-b']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('changing the injected repository reloads the current item', (
      tester,
    ) async {
      const itemId = 'detail-repository-change';
      final firstRepository = _FakeItemRepository(
        getByIdResults: [_item(itemId, title: 'First repository item')],
      );
      final secondRepository = _FakeItemRepository(
        getByIdResults: [_item(itemId, title: 'Second repository item')],
      );
      final repository = ValueNotifier<ItemRepository>(firstRepository);
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<ItemRepository>(
            valueListenable: repository,
            builder: (_, value, _) => ItemDetailScreen(
              key: const ValueKey('detail-screen'),
              itemId: itemId,
              itemRepository: value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First repository item'), findsOneWidget);

      repository.value = secondRepository;
      await tester.pumpAndSettle();

      expect(find.text('Second repository item'), findsOneWidget);
      expect(find.text('First repository item'), findsNothing);
      expect(secondRepository.getByIdCallIds, [itemId]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a delete dialog opened for A cannot delete B after an update',
      (tester) async {
        final repository = _FakeItemRepository(
          getByIdResults: [_item('delete-a'), _item('delete-b')],
        );
        final itemId = ValueNotifier<String>('delete-a');
        addTearDown(itemId.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<String>(
              valueListenable: itemId,
              builder: (_, id, _) => ItemDetailScreen(
                key: const ValueKey('detail-screen'),
                itemId: id,
                itemRepository: repository,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();

        itemId.value = 'delete-b';
        await tester.pumpAndSettle();
        await tester.tap(find.text('移入已删除'));
        await tester.pumpAndSettle();

        expect(repository.softDeletedIds, isEmpty);
        expect(repository.hardDeletedIds, isEmpty);
        expect(find.text('Test item delete-b'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('delete failure is sanitized and remains retryable', (
      tester,
    ) async {
      const itemId = 'delete-failure';
      const privateError = 'private delete database path';
      final repository = _FakeItemRepository(
        getByIdResults: [_item(itemId)],
        softDeleteError: StateError(privateError),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ItemDetailScreen(
            itemId: itemId,
            itemRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移入已删除'));
      await tester.pumpAndSettle();

      expect(repository.softDeletedIds, [itemId]);
      expect(find.text('删除事项失败，请重试'), findsOneWidget);
      expect(find.textContaining(privateError), findsNothing);
      expect(find.text('Test item $itemId'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byIcon(Icons.delete_outline),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('same-frame delete taps open only one confirmation', (
      tester,
    ) async {
      const itemId = 'delete-single-flight';
      final repository = _FakeItemRepository(
        getByIdResults: [_item(itemId)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ItemDetailScreen(
            itemId: itemId,
            itemRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.tap(find.byIcon(Icons.delete_outline), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('删除事项'), findsOneWidget);
      expect(repository.softDeletedIds, isEmpty);
      expect(repository.hardDeletedIds, isEmpty);
      expect(tester.takeException(), isNull);
    });

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
    testWidgets('late A load cannot replace B after itemId changes', (
      tester,
    ) async {
      final aResult = Completer<ItemModel?>();
      final bResult = Completer<ItemModel?>();
      final repository = _FakeItemRepository(
        getByIdResults: [aResult.future, bResult.future],
      );
      final itemId = ValueNotifier<String>('ocr-a');
      addTearDown(itemId.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: itemId,
            builder: (_, id, _) => OcrConfirmScreen(
              key: const ValueKey('ocr-screen'),
              itemId: id,
              itemRepository: repository,
            ),
          ),
        ),
      );
      await tester.pump();

      itemId.value = 'ocr-b';
      await tester.pump();

      bResult.complete(_item('ocr-b', ocrText: 'B OCR text'));
      await tester.pump();

      expect(find.text('Test item ocr-b'), findsOneWidget);
      expect(find.text('Test item ocr-a'), findsNothing);

      aResult.complete(_item('ocr-a', ocrText: 'A OCR text'));
      await tester.pump();

      expect(find.text('Test item ocr-b'), findsOneWidget);
      expect(find.text('Test item ocr-a'), findsNothing);
      expect(repository.getByIdCallIds, ['ocr-a', 'ocr-b']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('changing the injected repository reloads the current form', (
      tester,
    ) async {
      const itemId = 'ocr-repository-change';
      final firstRepository = _FakeItemRepository(
        getByIdResults: [_item(itemId, title: 'First repository form')],
      );
      final secondRepository = _FakeItemRepository(
        getByIdResults: [_item(itemId, title: 'Second repository form')],
      );
      final repository = ValueNotifier<ItemRepository>(firstRepository);
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<ItemRepository>(
            valueListenable: repository,
            builder: (_, value, _) => OcrConfirmScreen(
              key: const ValueKey('ocr-screen'),
              itemId: itemId,
              itemRepository: value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First repository form'), findsOneWidget);

      repository.value = secondRepository;
      await tester.pumpAndSettle();

      expect(find.text('Second repository form'), findsOneWidget);
      expect(find.text('First repository form'), findsNothing);
      expect(secondRepository.getByIdCallIds, [itemId]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a date picker opened for A cannot change B after an update', (
      tester,
    ) async {
      final aStartAt = DateTime(2026, 7, 15, 8, 30);
      final bStartAt = DateTime(2026, 8, 20, 9, 45);
      final repository = _FakeItemRepository(
        getByIdResults: [
          _item('picker-a', startAt: aStartAt),
          _item('picker-b', startAt: bStartAt),
        ],
      );
      final itemId = ValueNotifier<String>('picker-a');
      addTearDown(itemId.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: itemId,
            builder: (_, id, _) => OcrConfirmScreen(
              key: const ValueKey('ocr-screen'),
              itemId: id,
              itemRepository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, '时间'));
      await tester.pumpAndSettle();

      itemId.value = 'picker-b';
      await tester.pumpAndSettle();
      expect(
        find.text('2026-08-20 09:45', skipOffstage: false),
        findsOneWidget,
      );
      expect(repository.getByIdCallIds, ['picker-a', 'picker-b']);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      if (find.byType(TimePickerDialog).evaluate().isNotEmpty) {
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      expect(find.text('2026-08-20 09:45'), findsOneWidget);
      expect(find.text('2026-07-15 09:45'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'confirm for A stops if the screen switches to B while querying',
      (tester) async {
        final confirmResult = Completer<ItemModel?>();
        final repository = _FakeItemRepository(
          getByIdResults: [
            _item('confirm-a'),
            confirmResult.future,
            _item('confirm-b'),
          ],
        );
        final itemId = ValueNotifier<String>('confirm-a');
        addTearDown(itemId.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<String>(
              valueListenable: itemId,
              builder: (_, id, _) => OcrConfirmScreen(
                key: const ValueKey('ocr-screen'),
                itemId: id,
                itemRepository: repository,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'Edited A title');
        await tester.tap(find.byType(FilledButton));
        await tester.pump();

        itemId.value = 'confirm-b';
        await tester.pumpAndSettle();
        expect(find.text('Test item confirm-b'), findsOneWidget);

        confirmResult.complete(_item('confirm-a'));
        await tester.pumpAndSettle();

        expect(repository.saveCalls, 0);
        expect(find.text('Test item confirm-b'), findsOneWidget);
        expect(find.text('Edited A title'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'completed A save cannot navigate away from the updated B form',
      (tester) async {
        final saveGate = Completer<void>();
        final repository = _FakeItemRepository(
          getByIdResults: [
            _item('saving-a'),
            _item('saving-a'),
            _item('saving-b'),
          ],
          saveGate: saveGate,
        );
        final itemId = ValueNotifier<String>('saving-a');
        addTearDown(itemId.dispose);
        final router = GoRouter(
          initialLocation: '/ocr',
          routes: [
            GoRoute(
              path: '/ocr',
              builder: (_, _) => ValueListenableBuilder<String>(
                valueListenable: itemId,
                builder: (_, id, _) => OcrConfirmScreen(
                  key: const ValueKey('ocr-screen'),
                  itemId: id,
                  itemRepository: repository,
                  notificationPermissionCoordinator:
                      NotificationPermissionCoordinator(
                        requestPermission: () async => true,
                      ),
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

        await tester.enterText(
          find.byType(TextField).first,
          'Saved A snapshot',
        );
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        expect(repository.saveCalls, 1);

        itemId.value = 'saving-b';
        await tester.pumpAndSettle();
        expect(find.text('Test item saving-b'), findsOneWidget);

        saveGate.complete();
        await tester.pumpAndSettle();

        expect(find.text('calendar-target'), findsNothing);
        expect(find.text('Test item saving-b'), findsOneWidget);
        expect(repository.savedItems.single.id, 'saving-a');
        expect(repository.savedItems.single.title, 'Saved A snapshot');
        expect(tester.takeException(), isNull);
      },
    );

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

    testWidgets('restored local attachment is shown in the OCR editor', (
      tester,
    ) async {
      late Directory directory;
      late File file;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'personal_butler_local_attachment_',
        );
        file = File('${directory.path}/preview.png');
        await file.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
      });
      addTearDown(() async {
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      final item = _item('ocr-local-preview', ocrText: 'OCR body');
      final repository = _FakeItemRepository(
        getByIdResults: [item],
        attachmentResults: [
          [
            AttachmentModel(
              id: 'attachment-1',
              itemId: item.id,
              assetId: 'local:${file.path}',
              createdAt: DateTime.utc(2026, 7, 15),
            ),
          ],
        ],
      );

      // Flutter widget tests use a fake async zone.  Start the widget and
      // perform the real local-file I/O in runAsync, then use bounded frame
      // polling instead of pumpAndSettle so a decoder cannot make the test
      // wait indefinitely.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: OcrConfirmScreen(itemId: item.id, itemRepository: repository),
          ),
        );
        for (var i = 0; i < 40 && find.byType(Image).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });

      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing restored local attachment keeps the editor usable', (
      tester,
    ) async {
      final item = _item('ocr-missing-local-preview', ocrText: 'OCR body');
      final repository = _FakeItemRepository(
        getByIdResults: [item],
        attachmentResults: [
          [
            AttachmentModel(
              id: 'attachment-missing',
              itemId: item.id,
              assetId:
                  'local:${Directory.systemTemp.path}\\missing-preview.png',
              createdAt: DateTime.utc(2026, 7, 15),
            ),
          ],
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OcrConfirmScreen(itemId: item.id, itemRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(item.title), findsOneWidget);
      expect(find.byType(Image), findsNothing);
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
    this.softDeleteError,
  }) : _getByIdResults = List<Object?>.of(getByIdResults),
       _attachmentResults = List<Object>.of(attachmentResults);

  final List<Object?> _getByIdResults;
  final List<Object> _attachmentResults;
  final Completer<void>? saveGate;
  final Object? saveError;
  final Object? softDeleteError;
  int getByIdCalls = 0;
  int saveCalls = 0;
  final List<String> getByIdCallIds = [];
  final List<ItemModel> savedItems = [];
  final List<String> softDeletedIds = [];
  final List<String> hardDeletedIds = [];

  @override
  Future<ItemModel?> getById(String id) async {
    getByIdCalls += 1;
    getByIdCallIds.add(id);
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

  @override
  Future<void> softDelete(String id) async {
    softDeletedIds.add(id);
    final error = softDeleteError;
    if (error != null) throw error;
  }

  @override
  Future<void> hardDelete(String id) async {
    hardDeletedIds.add(id);
  }
}

class _Failure {
  const _Failure(this.error);

  final Object error;
}

ItemModel _item(
  String id, {
  String? title,
  String? ocrText,
  DateTime? startAt,
}) {
  final now = DateTime.utc(2026, 7, 15, 8, 30);
  return ItemModel(
    id: id,
    type: 'meeting',
    title: title ?? 'Test item $id',
    ocrText: ocrText,
    // Save/lifecycle tests use a valid schedule time. Untimed validation is
    // covered separately by the permission-flow regression tests.
    startAt: startAt ?? now,
    inboxStatus: 'inbox',
    createdAt: now,
    updatedAt: now,
  );
}
