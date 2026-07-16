import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/database/database_schema.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/services/reminder_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late _GuardedItemRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: DatabaseSchema.onCreate,
        singleInstance: false,
      ),
    );
    repository = _GuardedItemRepository(() async => database);
  });

  tearDown(() async {
    await database.close();
  });

  group('ItemRepository.getById', () {
    test('returns null after the item is soft deleted', () async {
      const itemId = 'item-get-by-id-soft-deleted';
      await database.insert('items', _buildItem(itemId).toMap());

      expect(await repository.getById(itemId), isNotNull);

      await repository.softDelete(itemId);

      expect(await repository.getById(itemId), isNull);
    });
  });

  group('ItemRepository.createOcrDraftWithAttachment', () {
    test('creates one meeting inbox draft and its attachment', () async {
      const ocrText = 'Quarterly planning\nTuesday at 10:00';
      const assetId = 'asset-123';
      const displayName = 'meeting.png';
      var changes = 0;
      repository.addListener(() => changes += 1);

      final item = await repository.createOcrDraftWithAttachment(
        ocrText: ocrText,
        assetId: assetId,
        displayName: displayName,
      );

      expect(item.type, 'meeting');
      expect(item.title, '新事项');
      expect(item.owner, 'self');
      expect(item.status, 'active');
      expect(item.inboxStatus, 'inbox');
      expect(item.pendingStatus, isNull);
      expect(item.nextFollowUpAt, isNull);
      expect(item.ocrText, ocrText);
      expect(item.reminderMinutes, 60);
      expect(item.isDeleted, isFalse);
      expect(item.updatedAt, item.createdAt);

      final itemRows = await database.query('items');
      expect(itemRows, hasLength(1));
      expect(itemRows.single['id'], item.id);
      expect(itemRows.single['type'], 'meeting');
      expect(itemRows.single['title'], '新事项');
      expect(itemRows.single['owner'], 'self');
      expect(itemRows.single['status'], 'active');
      expect(itemRows.single['inbox_status'], 'inbox');
      expect(itemRows.single['ocr_text'], ocrText);
      expect(itemRows.single['created_at'], item.createdAt.toIso8601String());
      expect(itemRows.single['updated_at'], item.updatedAt.toIso8601String());

      final attachmentRows = await database.query('attachments');
      expect(attachmentRows, hasLength(1));
      final attachment = AttachmentModel.fromMap(attachmentRows.single);
      expect(attachment.itemId, item.id);
      expect(attachment.assetId, assetId);
      expect(attachment.displayName, displayName);
      expect(attachment.createdAt, item.createdAt);
      expect(repository.createDraftCalled, isFalse);
      expect(repository.addAttachmentCalled, isFalse);
      expect(changes, 1);
    });

    test('preserves a custom title and owner', () async {
      final item = await repository.createOcrDraftWithAttachment(
        ocrText: 'Planning notes',
        assetId: 'asset-custom',
        title: 'Quarterly planning',
        owner: 'family',
      );

      expect(item.title, 'Quarterly planning');
      expect(item.owner, 'family');

      final itemRows = await database.query('items');
      expect(itemRows, hasLength(1));
      expect(itemRows.single['title'], 'Quarterly planning');
      expect(itemRows.single['owner'], 'family');
    });

    test('rolls back the item when attachment insertion fails', () async {
      var changes = 0;
      repository.addListener(() => changes += 1);
      await database.execute('''
        CREATE TRIGGER reject_attachment
        BEFORE INSERT ON attachments
        BEGIN
          SELECT RAISE(ABORT, 'forced attachment failure');
        END
      ''');
      await expectLater(
        repository.createOcrDraftWithAttachment(
          ocrText: 'Private meeting notes',
          assetId: 'asset-rollback',
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await database.query('items'), isEmpty);
      expect(await database.query('attachments'), isEmpty);
      expect(repository.createDraftCalled, isFalse);
      expect(repository.addAttachmentCalled, isFalse);
      expect(changes, 0);
    });

    test('rejects blank OCR text without writing sensitive values', () async {
      const privateAssetId = 'private-asset-42';

      await expectLater(
        repository.createOcrDraftWithAttachment(
          ocrText: ' \t\n ',
          assetId: privateAssetId,
        ),
        throwsA(
          isA<ArgumentError>()
              .having(
                (error) => error.message,
                'message',
                'OCR text must not be blank.',
              )
              .having(
                (error) => error.toString(),
                'sanitized message',
                isNot(contains(privateAssetId)),
              ),
        ),
      );

      expect(await database.query('items'), isEmpty);
      expect(await database.query('attachments'), isEmpty);
    });

    test('rejects blank asset id without writing sensitive values', () async {
      const privateOcrText = 'Confidential OCR contents';

      await expectLater(
        repository.createOcrDraftWithAttachment(
          ocrText: privateOcrText,
          assetId: ' \t\n ',
        ),
        throwsA(
          isA<ArgumentError>()
              .having(
                (error) => error.message,
                'message',
                'Asset ID must not be blank.',
              )
              .having(
                (error) => error.toString(),
                'sanitized message',
                isNot(contains(privateOcrText)),
              ),
        ),
      );

      expect(await database.query('items'), isEmpty);
      expect(await database.query('attachments'), isEmpty);
    });
  });

  group('ItemRepository reminder side effects', () {
    test('createDraft publishes exactly one committed mutation', () async {
      final draftRepository = ItemRepository(
        databaseProvider: () async => database,
        syncItemReminder: (_) async {},
        cancelNotification: (_) async {},
      );
      var changes = 0;
      draftRepository.addListener(() => changes += 1);

      await draftRepository.createDraft(type: 'meeting');

      expect(changes, 1);
      expect(await database.query('items'), hasLength(1));
    });

    test('deleting an absent item does not publish a mutation', () async {
      var changes = 0;
      repository.addListener(() => changes += 1);

      await repository.softDelete('missing-soft-delete');
      await repository.hardDelete('missing-hard-delete');

      expect(changes, 0);
    });

    test('external invalidation publishes one explicit mutation', () {
      var changes = 0;
      repository.addListener(() => changes += 1);

      repository.invalidateAfterExternalWrite();

      expect(changes, 1);
    });

    test('save commits the complete row when reminder sync throws', () async {
      var syncCount = 0;
      final item = _buildItem('item-save-sync-failure');
      final saveRepository = ItemRepository(
        databaseProvider: () async => database,
        syncItemReminder: (_) async {
          syncCount += 1;
          throw StateError('forced reminder sync failure');
        },
        cancelNotification: (_) async {},
      );
      var changes = 0;
      saveRepository.addListener(() => changes += 1);

      await saveRepository.save(item);

      expect(syncCount, 1);
      final rows = await database.query(
        'items',
        where: 'id = ?',
        whereArgs: [item.id],
      );
      expect(rows, hasLength(1));
      expect(rows.single, item.toMap());
      expect(changes, 1);
    });

    test('save rethrows database failures without syncing reminders', () async {
      var syncCount = 0;
      final item = _buildItem('item-save-db-failure');
      final saveRepository = ItemRepository(
        databaseProvider: () async => database,
        syncItemReminder: (_) async {
          syncCount += 1;
        },
        cancelNotification: (_) async {},
      );
      var changes = 0;
      saveRepository.addListener(() => changes += 1);
      await database.execute('''
        CREATE TRIGGER reject_item_insert
        BEFORE INSERT ON items
        BEGIN
          SELECT RAISE(ABORT, 'forced item insert failure');
        END
      ''');

      await expectLater(
        saveRepository.save(item),
        throwsA(isA<DatabaseException>()),
      );

      expect(syncCount, 0);
      expect(await database.query('items'), isEmpty);
      expect(changes, 0);
    });

    test(
      'softDelete commits tombstone and attempts both cancellations when each throws',
      () async {
        const itemId = 'item-soft-delete';
        final item = _buildItem(itemId);
        await database.insert('items', item.toMap());
        final cancelledIds = <int>[];
        final deleteRepository = ItemRepository(
          databaseProvider: () async => database,
          syncItemReminder: (_) async {},
          cancelNotification: (notificationId) async {
            cancelledIds.add(notificationId);
            throw StateError('forced cancellation failure');
          },
        );
        var changes = 0;
        deleteRepository.addListener(() => changes += 1);

        await deleteRepository.softDelete(itemId);

        final rows = await database.query(
          'items',
          where: 'id = ?',
          whereArgs: [itemId],
        );
        expect(rows.single['is_deleted'], 1);
        expect(cancelledIds, [
          ReminderSyncService.itemId(itemId),
          ReminderSyncService.pendingId(itemId),
        ]);
        expect(changes, 1);
      },
    );

    test(
      'softDelete rethrows database failures without cancelling notifications',
      () async {
        const itemId = 'item-soft-delete-db-failure';
        final item = _buildItem(itemId);
        await database.insert('items', item.toMap());
        final cancelledIds = <int>[];
        final deleteRepository = ItemRepository(
          databaseProvider: () async => database,
          syncItemReminder: (_) async {},
          cancelNotification: (notificationId) async {
            cancelledIds.add(notificationId);
          },
        );
        var changes = 0;
        deleteRepository.addListener(() => changes += 1);
        await database.execute('''
          CREATE TRIGGER reject_item_soft_delete
          BEFORE UPDATE OF is_deleted ON items
          BEGIN
            SELECT RAISE(ABORT, 'forced item update failure');
          END
        ''');

        await expectLater(
          deleteRepository.softDelete(itemId),
          throwsA(isA<DatabaseException>()),
        );

        final rows = await database.query(
          'items',
          where: 'id = ?',
          whereArgs: [itemId],
        );
        expect(rows.single['is_deleted'], 0);
        expect(cancelledIds, isEmpty);
        expect(changes, 0);
      },
    );

    test(
      'hardDelete removes item and attachment and attempts both cancellations when each throws',
      () async {
        const itemId = 'item-hard-delete';
        final item = _buildItem(itemId);
        await database.insert('items', item.toMap());
        await database.insert('attachments', {
          'id': 'attachment-hard-delete',
          'item_id': itemId,
          'asset_id': 'asset-hard-delete',
          'display_name': 'receipt.png',
          'created_at': item.createdAt.toIso8601String(),
        });
        final cancelledIds = <int>[];
        final deleteRepository = ItemRepository(
          databaseProvider: () async => database,
          syncItemReminder: (_) async {},
          cancelNotification: (notificationId) async {
            cancelledIds.add(notificationId);
            throw StateError('forced cancellation failure');
          },
        );
        var changes = 0;
        deleteRepository.addListener(() => changes += 1);

        await deleteRepository.hardDelete(itemId);

        expect(await database.query('items'), isEmpty);
        expect(await database.query('attachments'), isEmpty);
        expect(cancelledIds, [
          ReminderSyncService.itemId(itemId),
          ReminderSyncService.pendingId(itemId),
        ]);
        expect(changes, 1);
      },
    );

    test(
      'hardDelete rethrows database failures without cancelling notifications',
      () async {
        const itemId = 'item-hard-delete-db-failure';
        final item = _buildItem(itemId);
        await database.insert('items', item.toMap());
        await database.insert('attachments', {
          'id': 'attachment-hard-delete-db-failure',
          'item_id': itemId,
          'asset_id': 'asset-hard-delete-db-failure',
          'display_name': 'receipt.png',
          'created_at': item.createdAt.toIso8601String(),
        });
        final cancelledIds = <int>[];
        final deleteRepository = ItemRepository(
          databaseProvider: () async => database,
          syncItemReminder: (_) async {},
          cancelNotification: (notificationId) async {
            cancelledIds.add(notificationId);
          },
        );
        var changes = 0;
        deleteRepository.addListener(() => changes += 1);
        await database.execute('''
          CREATE TRIGGER reject_item_hard_delete
          BEFORE DELETE ON items
          BEGIN
            SELECT RAISE(ABORT, 'forced item delete failure');
          END
        ''');

        await expectLater(
          deleteRepository.hardDelete(itemId),
          throwsA(isA<DatabaseException>()),
        );

        expect(
          await database.query('items', where: 'id = ?', whereArgs: [itemId]),
          hasLength(1),
        );
        expect(
          await database.query(
            'attachments',
            where: 'item_id = ?',
            whereArgs: [itemId],
          ),
          hasLength(1),
        );
        expect(cancelledIds, isEmpty);
        expect(changes, 0);
      },
    );
  });
}

class _GuardedItemRepository extends ItemRepository {
  _GuardedItemRepository(Future<Database> Function() databaseProvider)
    : super(
        databaseProvider: databaseProvider,
        syncItemReminder: (_) async {},
        cancelNotification: (_) async {},
      );

  bool createDraftCalled = false;
  bool addAttachmentCalled = false;

  @override
  Future<ItemModel> createDraft({
    required String type,
    String title = '',
    String inboxStatus = 'inbox',
    String? ocrText,
    String owner = 'self',
  }) async {
    createDraftCalled = true;
    throw StateError('createDraft must not be called by the OCR transaction');
  }

  @override
  Future<void> addAttachment({
    required String itemId,
    required String assetId,
    String? displayName,
  }) async {
    addAttachmentCalled = true;
    throw StateError('addAttachment must not be called by the OCR transaction');
  }
}

ItemModel _buildItem(String id) {
  final createdAt = DateTime.utc(2026, 7, 15, 8, 30);
  return ItemModel(
    id: id,
    type: 'reimbursement',
    title: 'Travel reimbursement',
    description: 'Client visit expenses',
    owner: 'self',
    startAt: DateTime.utc(2026, 7, 20, 9),
    endAt: DateTime.utc(2026, 7, 20, 10),
    location: 'Shanghai',
    participants: 'Alex, Sam',
    status: 'active',
    inboxStatus: 'confirmed',
    pendingStatus: 'submitted',
    nextFollowUpAt: DateTime.utc(2026, 7, 22, 9),
    amount: 128.5,
    ocrText: 'Receipt total 128.50',
    notes: 'Submit before Friday',
    reminderMinutes: 45,
    createdAt: createdAt,
    updatedAt: createdAt.add(const Duration(minutes: 5)),
  );
}
