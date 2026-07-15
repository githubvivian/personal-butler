import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/database/database_schema.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
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

  group('ItemRepository.createOcrDraftWithAttachment', () {
    test('creates one meeting inbox draft and its attachment', () async {
      const ocrText = 'Quarterly planning\nTuesday at 10:00';
      const assetId = 'asset-123';
      const displayName = 'meeting.png';

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
}

class _GuardedItemRepository extends ItemRepository {
  _GuardedItemRepository(Future<Database> Function() databaseProvider)
    : super(databaseProvider: databaseProvider);

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
