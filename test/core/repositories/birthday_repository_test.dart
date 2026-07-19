import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/database/database_schema.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/services/reminder_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: DatabaseSchema.onCreate,
        singleInstance: false,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('BirthdayRepository reminder side effects', () {
    test(
      'create rejects an invalid solar date before database access or reminder sync',
      () async {
        var databaseRequests = 0;
        var syncCount = 0;
        final repository = BirthdayRepository(
          databaseProvider: () async {
            databaseRequests += 1;
            return database;
          },
          syncBirthdayReminder: (_) async {
            syncCount += 1;
          },
          cancelNotification: (_) async {},
        );

        await expectLater(
          repository.create(
            name: 'Invalid solar date',
            isLunar: false,
            month: 2,
            day: 30,
          ),
          throwsArgumentError,
        );

        expect(databaseRequests, 0);
        expect(syncCount, 0);
        expect(await database.query('birthdays'), isEmpty);
      },
    );

    test(
      'save rejects an invalid lunar date before database access or reminder sync',
      () async {
        var databaseRequests = 0;
        var syncCount = 0;
        final repository = BirthdayRepository(
          databaseProvider: () async {
            databaseRequests += 1;
            return database;
          },
          syncBirthdayReminder: (_) async {
            syncCount += 1;
          },
          cancelNotification: (_) async {},
        );
        final model = BirthdayModel(
          id: 'invalid-lunar-birthday',
          name: 'Invalid lunar date',
          isLunar: true,
          month: 12,
          day: 31,
          createdAt: DateTime.utc(2026, 7, 16),
        );

        await expectLater(repository.save(model), throwsArgumentError);

        expect(databaseRequests, 0);
        expect(syncCount, 0);
        expect(await database.query('birthdays'), isEmpty);
      },
    );

    test('create accepts and persists a recurring solar leap day', () async {
      var syncCount = 0;
      final repository = BirthdayRepository(
        databaseProvider: () async => database,
        syncBirthdayReminder: (_) async {
          syncCount += 1;
        },
        cancelNotification: (_) async {},
      );

      final model = await repository.create(
        name: 'Leap day',
        isLunar: false,
        month: 2,
        day: 29,
      );

      expect(syncCount, 1);
      expect(
        await database.query(
          'birthdays',
          where: 'id = ?',
          whereArgs: [model.id],
        ),
        hasLength(1),
      );
    });

    test(
      'create returns model and commits row when reminder sync throws',
      () async {
        var syncCount = 0;
        final repository = BirthdayRepository(
          databaseProvider: () async => database,
          syncBirthdayReminder: (_) async {
            syncCount += 1;
            throw StateError('forced birthday reminder sync failure');
          },
          cancelNotification: (_) async {},
        );

        final model = await repository.create(
          name: 'Taylor',
          relation: 'friend',
          isLunar: false,
          month: 8,
          day: 12,
          remindDaysBefore: 5,
        );

        expect(syncCount, 1);
        final rows = await database.query(
          'birthdays',
          where: 'id = ?',
          whereArgs: [model.id],
        );
        expect(rows, hasLength(1));
        expect(rows.single, model.toMap());
      },
    );

    test('save rethrows database failures without syncing reminders', () async {
      var syncCount = 0;
      final repository = BirthdayRepository(
        databaseProvider: () async => database,
        syncBirthdayReminder: (_) async {
          syncCount += 1;
        },
        cancelNotification: (_) async {},
      );
      final model = BirthdayModel(
        id: 'birthday-save-db-failure',
        name: 'Morgan',
        relation: 'family',
        isLunar: true,
        month: 6,
        day: 10,
        isLeapMonth: false,
        remindDaysBefore: 3,
        createdAt: DateTime.utc(2026, 7, 15),
      );
      await database.execute('''
        CREATE TRIGGER reject_birthday_insert
        BEFORE INSERT ON birthdays
        BEGIN
          SELECT RAISE(ABORT, 'forced birthday insert failure');
        END
      ''');

      await expectLater(
        repository.save(model),
        throwsA(isA<DatabaseException>()),
      );

      expect(syncCount, 0);
      expect(await database.query('birthdays'), isEmpty);
    });

    test(
      'softDelete commits tombstone and attempts both cancellations when each throws',
      () async {
        const birthdayId = 'birthday-soft-delete';
        final model = BirthdayModel(
          id: birthdayId,
          name: 'Jordan',
          relation: 'family',
          isLunar: false,
          month: 9,
          day: 18,
          createdAt: DateTime.utc(2026, 7, 15),
        );
        await database.insert('birthdays', model.toMap());
        var syncCount = 0;
        final cancelledIds = <int>[];
        final repository = BirthdayRepository(
          databaseProvider: () async => database,
          syncBirthdayReminder: (_) async {
            syncCount += 1;
          },
          cancelNotification: (notificationId) async {
            cancelledIds.add(notificationId);
            throw StateError('forced birthday cancellation failure');
          },
        );

        await repository.softDelete(birthdayId);

        final rows = await database.query(
          'birthdays',
          where: 'id = ?',
          whereArgs: [birthdayId],
        );
        expect(rows.single['is_deleted'], 1);
        expect(syncCount, 0);
        expect(cancelledIds, [
          ReminderSyncService.birthdayAdvanceId(birthdayId),
          ReminderSyncService.birthdayDayId(birthdayId),
        ]);
      },
    );

    test(
      'softDelete rethrows database failures without cancelling notifications',
      () async {
        const birthdayId = 'birthday-soft-delete-db-failure';
        final model = BirthdayModel(
          id: birthdayId,
          name: 'Casey',
          relation: 'friend',
          isLunar: false,
          month: 10,
          day: 8,
          createdAt: DateTime.utc(2026, 7, 15),
        );
        await database.insert('birthdays', model.toMap());
        final cancelledIds = <int>[];
        final repository = BirthdayRepository(
          databaseProvider: () async => database,
          syncBirthdayReminder: (_) async {},
          cancelNotification: (notificationId) async {
            cancelledIds.add(notificationId);
          },
        );
        await database.execute('''
          CREATE TRIGGER reject_birthday_soft_delete
          BEFORE UPDATE OF is_deleted ON birthdays
          BEGIN
            SELECT RAISE(ABORT, 'forced birthday update failure');
          END
        ''');

        await expectLater(
          repository.softDelete(birthdayId),
          throwsA(isA<DatabaseException>()),
        );

        final rows = await database.query(
          'birthdays',
          where: 'id = ?',
          whereArgs: [birthdayId],
        );
        expect(rows.single['is_deleted'], 0);
        expect(cancelledIds, isEmpty);
      },
    );

    test('softDelete invokes one birthday-level reminder cleanup', () async {
      const birthdayId = 'birthday-level-soft-delete';
      final model = BirthdayModel(
        id: birthdayId,
        name: 'Riley',
        relation: 'family',
        isLunar: false,
        month: 11,
        day: 9,
        createdAt: DateTime.utc(2026, 7, 15),
      );
      await database.insert('birthdays', model.toMap());
      final cleanedBirthdayIds = <String>[];
      final repository = BirthdayRepository(
        databaseProvider: () async => database,
        syncBirthdayReminder: (_) async {},
        cancelBirthdayReminders: (id) async {
          cleanedBirthdayIds.add(id);
          throw StateError('forced birthday-level cleanup failure');
        },
      );

      await repository.softDelete(birthdayId);

      expect(cleanedBirthdayIds, [birthdayId]);
      final rows = await database.query(
        'birthdays',
        where: 'id = ?',
        whereArgs: [birthdayId],
      );
      expect(rows.single['is_deleted'], 1);
    });
  });
}
